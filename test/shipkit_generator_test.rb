# frozen_string_literal: true

require "test_helper"

class ShipkitGeneratorTest < Minitest::Test
  def test_generates_sections_and_version_headings_from_an_angular_style_commit_log
    output = git_record(
      sha: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      short_sha: "aaaaaaa",
      date: "2026-08-30",
      message: "feat(api): add changelog endpoint\n\nExpose releases to clients.\n"
    ) + git_record(
      sha: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      short_sha: "bbbbbbb",
      date: "2026-08-29",
      decorations: "tag: v2.0.0",
      message: "fix: handle an empty range\n\nBREAKING CHANGE: return an empty string instead of nil\n"
    )

    changelog = Shipkit::Generator.new("v1.0.0..HEAD", git: ->(*) { output }).generate

    assert_equal <<~CHANGELOG, changelog
      # Unreleased

      ## Features
      * **api:** add changelog endpoint (aaaaaaa)

      # v2.0.0 (2026-08-29)

      ## Bug Fixes
      * handle an empty range (bbbbbbb)

      ## BREAKING CHANGES
      * return an empty string instead of nil (bbbbbbb)
    CHANGELOG
  end

  def test_groups_older_commits_below_the_tag_that_ends_their_version
    output = git_record(date: "2026-08-30", message: "chore: prepare next release") +
      git_record(date: "2026-08-29", decorations: "tag: v1.1.0", message: "feat(ui): add search") +
      git_record(date: "2026-08-28", message: "fix(ui): clear search") +
      git_record(date: "2026-08-20", decorations: "tag: v1.0.0", message: "feat: launch")

    changelog = Shipkit::Generator.new("v0.9.0..HEAD", git: ->(*) { output }).generate

    assert_match(/# Unreleased.*prepare next release/m, changelog)
    assert_match(/# v1\.1\.0.*add search.*clear search/m, changelog)
    assert_match(/# v1\.0\.0.*launch/m, changelog)
  end

  def test_renders_reverts_and_moves_commits_outside_the_convention_into_a_notes_section
    output = git_record(message: "revert: feat(api): add search\n\nThis reverts commit abcdef1.") +
      git_record(short_sha: "ddddddd", message: "Merge branch 'main'")

    changelog = Shipkit::Generator.new("HEAD~2..HEAD", git: ->(*) { output }).generate

    assert_includes changelog, "## Reverts"
    assert_includes changelog, "feat(api): add search"
    assert_includes changelog, "## Notes"
    assert_includes changelog, "* Merge branch 'main' (ddddddd)"
  end

  def test_ignores_messages_containing_a_line_longer_than_100_characters
    output = git_record(message: "feat: #{"a" * 95}")

    assert_equal "", Shipkit::Generator.new("HEAD~1..HEAD", git: ->(*) { output }).generate
  end

  def test_renders_notes_after_other_sections_within_a_version
    output = git_record(short_sha: "aaaaaaa", message: "feat: add search") +
      git_record(short_sha: "bbbbbbb", message: "Update README")

    changelog = Shipkit::Generator.new("HEAD~2..HEAD", git: ->(*) { output }).generate

    assert_equal <<~CHANGELOG, changelog
      # Unreleased

      ## Features
      * add search (aaaaaaa)

      ## Notes
      * Update README (bbbbbbb)
    CHANGELOG
  end

  def test_passes_the_range_as_a_single_argument_to_git
    arguments = nil
    generator = Shipkit::Generator.new("15074c016be489aa8f180e16ac06303b5e90855e..HEAD", git: lambda { |*args|
      arguments = args
      ""
    })

    generator.generate

    assert_includes arguments, "15074c016be489aa8f180e16ac06303b5e90855e..HEAD"
  end

  def test_rejects_ranges_that_could_be_interpreted_as_git_options
    assert_raises(ArgumentError) do
      Shipkit::Generator.new("--all", git: ->(*) { flunk }).generate
    end
  end

  def test_resolves_a_bad_revision_to_a_v_prefixed_tag
    output = git_record(message: "feat: add search")
    calls = []

    git = lambda do |*args|
      calls << args

      case args.first
      when "rev-parse"
        raise Shipkit::Generator::GitError, "bad revision" if args.last == "2026.2^{commit}"
        "sha\n"
      when "tag"
        (args.last == "v2026.2") ? "v2026.2\n" : ""
      when "log"
        output
      when "remote"
        ""
      end
    end

    changelog = Shipkit::Generator.new("2026.2..HEAD", git: git).generate

    assert_includes changelog, "add search"
    assert_includes calls, ["log", "--no-color", "--date=short", "--format=#{Shipkit::Generator::LOG_FORMAT}", "v2026.2..HEAD", "--"]
  end

  def test_resolves_a_bad_revision_to_a_tag_without_the_v_prefix
    output = git_record(message: "feat: add search")

    git = lambda do |*args|
      case args.first
      when "rev-parse"
        raise Shipkit::Generator::GitError, "bad revision" if args.last == "v2023.2^{commit}"
        "sha\n"
      when "tag"
        (args.last == "2023.2") ? "2023.2\n" : ""
      when "log"
        output
      when "remote"
        ""
      end
    end

    changelog = Shipkit::Generator.new("v2023.2..HEAD", git: git).generate

    assert_includes changelog, "add search"
  end

  def test_leaves_the_range_untouched_when_no_matching_tag_exists
    git = lambda do |*args|
      case args.first
      when "rev-parse"
        raise Shipkit::Generator::GitError, "fatal: bad revision '2026.2^{commit}'" if args.last == "2026.2^{commit}"
        "sha\n"
      when "tag" then ""
      when "log" then raise Shipkit::Generator::GitError, "fatal: bad revision '2026.2..HEAD'"
      end
    end

    error = assert_raises(Shipkit::Generator::GitError) do
      Shipkit::Generator.new("2026.2..HEAD", git: git).generate
    end

    assert_match(/bad revision/, error.message)
  end

  def test_links_commit_shas_to_github_when_a_repo_url_is_given
    output = git_record(sha: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", short_sha: "aaaaaaa", message: "feat: add search")

    changelog = Shipkit::Generator.new("HEAD~1..HEAD", repo_url: "https://github.com/boxture/server", git: ->(*) { output }).generate

    assert_includes changelog, "* add search ([aaaaaaa](https://github.com/boxture/server/commit/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa))"
  end

  def test_auto_detects_the_repo_url_from_the_origin_remote
    output = git_record(sha: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", short_sha: "aaaaaaa", message: "feat: add search")

    changelog = Shipkit::Generator.new("HEAD~1..HEAD", git: lambda { |*args|
      (args.first == "remote") ? "git@github.com:boxture/server.git\n" : output
    }).generate

    assert_includes changelog, "* add search ([aaaaaaa](https://github.com/boxture/server/commit/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa))"
  end

  def test_falls_back_to_a_plain_sha_when_the_origin_remote_isnt_a_github_url
    output = git_record(sha: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", short_sha: "aaaaaaa", message: "feat: add search")

    changelog = Shipkit::Generator.new("HEAD~1..HEAD", git: lambda { |*args|
      (args.first == "remote") ? "git@gitlab.com:boxture/server.git\n" : output
    }).generate

    assert_includes changelog, "* add search (aaaaaaa)"
  end

  def test_uses_the_llm_to_summarize_commits_and_the_release_when_enabled
    output = git_record(short_sha: "aaaaaaa", message: "feat: add search")
    llm = fake_llm(commit_summary: "Adds search to the app.", release_summary: "This release adds search.")

    changelog = Shipkit::Generator.new("HEAD~1..HEAD", git: ->(*) { output }, llm:).generate

    assert_equal <<~CHANGELOG, changelog
      # Unreleased

      This release adds search.

      ## Features
      * Adds search to the app.
        * add search (aaaaaaa)
    CHANGELOG
  end

  def test_merges_commits_with_identical_subjects_into_one_line_with_both_shas
    output = git_record(short_sha: "aaaaaaa", message: "feat: add search") +
      git_record(short_sha: "bbbbbbb", message: "feat: add search")

    changelog = Shipkit::Generator.new("HEAD~2..HEAD", git: ->(*) { output }).generate

    assert_equal <<~CHANGELOG, changelog
      # Unreleased

      ## Features
      * add search (aaaaaaa, bbbbbbb)
    CHANGELOG
  end

  def test_merges_duplicate_notes_into_one_line_and_summarizes_them_only_once
    output = git_record(short_sha: "aaaaaaa", message: "Update README") +
      git_record(short_sha: "bbbbbbb", message: "Update README")
    summarized_shas = []
    llm = Class.new do
      define_method(:summarize_commit) do |commit|
        summarized_shas << commit.short_sha
        "The README was updated."
      end
      define_method(:summarize_release) { |_commits| nil }
    end.new

    changelog = Shipkit::Generator.new("HEAD~2..HEAD", git: ->(*) { output }, llm:).generate

    assert_equal <<~CHANGELOG, changelog
      # Unreleased

      ## Notes
      * The README was updated.
        * Update README (aaaaaaa)
        * Update README (bbbbbbb)
    CHANGELOG
    assert_equal 1, summarized_shas.length
  end

  private

  def fake_llm(commit_summary:, release_summary:)
    Class.new do
      define_method(:summarize_commit) { |_commit| commit_summary }
      define_method(:summarize_release) { |_commits| release_summary }
    end.new
  end

  def git_record(message:, sha: "cccccccccccccccccccccccccccccccccccccccc", short_sha: "ccccccc", date: "2026-08-30", decorations: "")
    [
      Shipkit::Generator::RECORD_SEPARATOR,
      sha,
      Shipkit::Generator::FIELD_SEPARATOR,
      short_sha,
      Shipkit::Generator::FIELD_SEPARATOR,
      date,
      Shipkit::Generator::FIELD_SEPARATOR,
      decorations,
      Shipkit::Generator::FIELD_SEPARATOR,
      message
    ].join
  end
end
