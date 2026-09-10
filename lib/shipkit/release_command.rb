# frozen_string_literal: true

require 'open3'

module Shipkit
  # Bumps, commits, tags, and pushes the project's release files (à la gem-release).
  class ReleaseCommand
    class Error < StandardError; end

    BUMPS = %w[major minor patch].freeze
    VERSION_PATTERN = /\A(\d+)\.(\d+)\.(\d+)\z/

    def initialize(bump, git: nil, remote: 'origin', config: nil, version_file: VersionFile.new)
      raise ArgumentError, "bump must be one of #{BUMPS.join(', ')}" unless BUMPS.include?(bump.to_s)

      @bump = bump.to_s
      @git = git || method(:run_git)
      @remote = remote
      @config = config || Config.load
      @version_file = version_file
    end

    def call
      current_version = @version_file.version
      tag = "v#{bump_version(current_version)}"

      raise Error, 'working tree has uncommitted changes' if dirty?

      begin
        @config.write_previous_version(current_version)
        @version_file.write(tag.delete_prefix('v'))
      rescue VersionFile::Error, SystemCallError => e
        raise Error, e.message
      end

      @git.call('add', @version_file.path, @config.path)
      @git.call('commit', '-m', "Release #{tag}")
      @git.call('push', @remote, 'HEAD') if @config.git_push?

      @git.call('tag', '-a', tag, '-m', "Release #{tag}") if @config.git_tag?

      @git.call('push', @remote, tag) if @config.git_push? && @config.git_tag?

      tag
    end

    private

    def dirty?
      !@git.call('status', '--porcelain').strip.empty?
    end

    def bump_version(version)
      match = version.match(VERSION_PATTERN)
      raise Error, "invalid version: #{version}" unless match

      major, minor, patch = match.captures.map(&:to_i)

      case @bump
      when 'major' then [major + 1, 0, 0]
      when 'minor' then [major, minor + 1, 0]
      when 'patch' then [major, minor, patch + 1]
      end.join('.')
    end

    def run_git(*arguments)
      output, error, status = Open3.capture3('git', *arguments)
      raise Error, error.strip unless status.success?

      output
    end
  end
end
