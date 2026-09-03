# frozen_string_literal: true

require "open3"

module Shipkit
  class Generator
    class GitError < StandardError; end

    TYPES = {
      "feat" => "Features",
      "fix" => "Bug Fixes",
      "docs" => "Documentation",
      "style" => "Styles",
      "refactor" => "Code Refactoring",
      "test" => "Tests",
      "chore" => "Chores",
      "revert" => "Reverts"
    }.freeze

    TYPE_ORDER = TYPES.values.freeze
    NOTE_TYPE = "note"
    RECORD_SEPARATOR = "\x1e"
    FIELD_SEPARATOR = "\x1f"
    LOG_FORMAT = "%x1e%H%x1f%h%x1f%ad%x1f%D%x1f%B"

    Commit = Data.define(:sha, :short_sha, :date, :decorations, :type, :scope, :subject, :breaking_changes)

    def initialize(range, repo_url: nil, git: nil, llm: nil)
      @range = range.to_s
      @git = git || method(:run_git)
      @repo_url = repo_url
      @llm = llm || Llm.new
    end

    def generate
      validate_range!
      versions = group_by_version(parse(log))

      versions.filter_map { |version, commits| render_version(version, commits) }
        .join("\n\n")
        .then { |changelog| changelog.empty? ? "" : "#{changelog}\n" }
    end

    private

    def validate_range!
      return unless @range.empty? || @range.start_with?("-") || @range.match?(/[\s\0]/)

      raise ArgumentError, "range must be a non-empty Git revision range without whitespace"
    end

    def log
      @git.call("log", "--no-color", "--date=short", "--format=#{LOG_FORMAT}", resolved_range, "--")
    end

    def resolved_range
      return @range if @range.include?("...")

      from, to = @range.split("..", 2)
      return @range unless to

      [resolve_revision(from), resolve_revision(to)].join("..")
    end

    def resolve_revision(revision)
      return revision if valid_revision?(revision)

      alternate = revision.start_with?("v") ? revision.delete_prefix("v") : "v#{revision}"
      tag_exists?(alternate) ? alternate : revision
    end

    def valid_revision?(revision)
      @git.call("rev-parse", "--verify", "--quiet", "#{revision}^{commit}")
      true
    rescue GitError
      false
    end

    def tag_exists?(name)
      !@git.call("tag", "--list", name).to_s.strip.empty?
    end

    def run_git(*arguments)
      output, error, status = Open3.capture3("git", *arguments)
      raise GitError, error.strip unless status.success?

      output
    end

    def repo_url
      return @repo_url if @repo_url_detected

      @repo_url_detected = true
      @repo_url ||= begin
        url = @git.call("remote", "get-url", "origin").strip
        match = url.match(%r{github\.com[:/]([^/]+)/(.+?)(?:\.git)?\z})
        "https://github.com/#{match[1]}/#{match[2]}" if match
      rescue GitError
        nil
      end
    end

    def commit_link(commit)
      repo_url ? "[#{commit.short_sha}](#{repo_url}/commit/#{commit.sha})" : commit.short_sha
    end

    def parse(output)
      output.split(RECORD_SEPARATOR).filter_map do |record|
        next if record.strip.empty?

        sha, short_sha, date, decorations, message = record.split(FIELD_SEPARATOR, 5)
        parse_commit(sha, short_sha, date, decorations, message.to_s.strip)
      end
    end

    def parse_commit(sha, short_sha, date, decorations, message)
      return if message.lines.any? { |line| line.chomp.length > 100 }

      header, *body = message.lines(chomp: true)
      type, scope, subject = parse_header(header)

      Commit.new(
        sha:,
        short_sha:,
        date:,
        decorations:,
        type: type || NOTE_TYPE,
        scope: (scope unless scope.to_s.empty?),
        subject: subject || header,
        breaking_changes: extract_breaking_changes(body.join("\n"))
      )
    end

    def parse_header(header)
      if (match = header.match(/\Arevert:\s+(.+)\z/i))
        return ["revert", nil, match[1]]
      end

      match = header.match(/\A(#{TYPES.keys.reject { |type| type == "revert" }.join("|")})(?:\(([^)]+)\))?: ([^\n]+)\z/)
      match&.captures
    end

    def extract_breaking_changes(message)
      message.scan(/(?:\A|\n)BREAKING CHANGES?:\s*(.*?)(?=\n[A-Z][A-Z -]+:\s|\z)/m)
        .flatten
        .map { |change| change.strip.gsub(/\n+/, " ") }
    end

    def group_by_version(commits)
      versions = Hash.new { |hash, key| hash[key] = [] }
      version = "Unreleased"

      commits.each do |commit|
        version = tag_for(commit.decorations) || version
        versions[version] << commit
      end

      versions
    end

    def tag_for(decorations)
      decorations.to_s.split(", ").filter_map do |decoration|
        decoration.delete_prefix("tag: ") if decoration.start_with?("tag: ")
      end.first
    end

    def render_version(version, commits)
      notes, conventional = commits.partition { |commit| commit.type == NOTE_TYPE }
      sections = conventional.group_by { |commit| TYPES.fetch(commit.type) }
      breaking_changes = commits.flat_map do |commit|
        commit.breaking_changes.map { |change| [commit, change] }
      end
      return if sections.empty? && breaking_changes.empty? && notes.empty?

      date = commits.first.date
      heading = (version == "Unreleased") ? "# Unreleased" : "# #{version} (#{date})"
      summary = @llm.summarize_release(commits)
      content = TYPE_ORDER.filter_map do |section|
        render_section(section, sections[section]) if sections[section]&.any?
      end
      content << render_breaking_changes(breaking_changes) if breaking_changes.any?
      content << render_notes(notes) if notes.any?

      ([heading] + [summary].compact + content).join("\n\n")
    end

    def render_section(title, commits)
      lines = group_duplicates(commits) { |commit| [commit.scope, commit.subject] }.map do |group|
        commit = group.first
        scope = commit.scope ? "**#{commit.scope}:** " : ""
        render_commit_line(group, prefix: scope)
      end

      (["## #{title}"] + lines).join("\n")
    end

    def render_breaking_changes(changes)
      lines = group_duplicates(changes) { |(commit, change)| [commit.scope, change] }.map do |group|
        commit, change = group.first
        scope = commit.scope ? "**#{commit.scope}:** " : ""
        "* #{scope}#{change} (#{commit_links(group.map(&:first))})"
      end

      (["## BREAKING CHANGES"] + lines).join("\n")
    end

    def render_notes(commits)
      lines = group_duplicates(commits) { |commit| commit.subject }.map { |group| render_commit_line(group) }

      (["## Notes"] + lines).join("\n")
    end

    # Renders the (optionally summarized) line for a group of duplicate commits, with the original
    # commit message(s) shown beneath when a summary is available. SHAs only appear on the original
    # message lines, not next to the summary.
    def render_commit_line(group, prefix: "")
      commit = group.first
      summary = @llm.summarize_commit(commit)
      originals = group.map { |c| "  * #{c.subject} (#{commit_link(c)})" }

      return "* #{prefix}#{commit.subject} (#{commit_links(group)})" unless summary

      (["* #{prefix}#{summary}"] + originals).join("\n")
    end

    # Groups commits that render identically so they're listed (and summarized) once, with all their SHAs.
    def group_duplicates(items, &key)
      items.group_by(&key).values
    end

    def commit_links(commits)
      commits.map { |commit| commit_link(commit) }.join(", ")
    end
  end
end
