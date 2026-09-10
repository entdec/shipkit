# frozen_string_literal: true

require 'test_helper'

class ShipkitReleaseCommandTest < Minitest::Test
  def test_bumps_the_patch_version_from_the_version_file_when_it_is_ahead_of_the_latest_tag
    git, calls = fake_git(tags: 'v0.0.1')
    version_file = fake_version_file(version: '0.1.0')
    config = fake_config

    tag = release_command('patch', git:, config:, version_file:).call

    assert_equal 'v0.1.1', tag
    assert_equal ['0.1.0'], config.previous_versions
    assert_equal ['0.1.1'], version_file.writes
    assert_includes calls, ['tag', '-a', 'v0.1.1', '-m', 'Release v0.1.1']
  end

  def test_bumps_the_minor_version_and_resets_patch
    git, = fake_git(tags: 'v1.2.3')

    tag = release_command('minor', git:, config: fake_config).call

    assert_equal 'v1.3.0', tag
  end

  def test_bumps_the_major_version_and_resets_minor_and_patch
    git, = fake_git(tags: 'v1.2.3')

    tag = release_command('major', git:, config: fake_config).call

    assert_equal 'v2.0.0', tag
  end

  def test_defaults_to_v0_0_0_when_there_are_no_existing_tags
    git, = fake_git(tags: '')

    tag = release_command('patch', git:, config: fake_config, version_file: fake_version_file(version: '0.0.0')).call

    assert_equal 'v0.0.1', tag
  end

  def test_pushes_the_current_branch_and_the_new_tag_to_the_remote
    git, calls = fake_git(tags: 'v1.0.0')

    release_command('patch', git:, remote: 'origin', config: fake_config,
                             version_file: fake_version_file(version: '1.0.0')).call

    assert_includes calls, %w[push origin HEAD]
    assert_includes calls, ['push', 'origin', 'v1.0.1']
  end

  def test_raises_when_the_working_tree_is_dirty
    git, = fake_git(tags: 'v1.0.0', status: " M lib/foo.rb\n")

    assert_raises(Shipkit::ReleaseCommand::Error) do
      release_command('patch', git:, config: fake_config).call
    end
  end

  def test_rejects_an_unknown_bump
    assert_raises(ArgumentError) do
      release_command('banana')
    end
  end

  def test_skips_tagging_and_the_dirty_check_when_git_tag_is_disabled
    git, calls = fake_git(tags: 'v1.0.0', status: " M lib/foo.rb\n")
    version_file = fake_version_file(version: '1.0.0')

    tag = release_command('patch', git:, config: fake_config(tag: false), version_file:).call

    assert_equal 'v1.0.1', tag
    assert_equal ['1.0.1'], version_file.writes
    refute(calls.any? { |call| call.first == 'tag' && call.include?('-a') })
    assert_includes calls, %w[push origin HEAD]
    refute_includes calls, ['push', 'origin', 'v1.0.1']
  end

  def test_skips_pushing_when_git_push_is_disabled
    git, calls = fake_git(tags: 'v1.0.0')

    release_command('patch', git:, config: fake_config(push: false),
                             version_file: fake_version_file(version: '1.0.0')).call

    assert_includes calls, ['tag', '-a', 'v1.0.1', '-m', 'Release v1.0.1']
    refute(calls.any? { |call| call.first == 'push' })
  end

  private

  def release_command(bump, version_file: fake_version_file, **options)
    Shipkit::ReleaseCommand.new(bump, **options, version_file:)
  end

  def fake_git(tags:, status: '')
    calls = []
    git = lambda do |*args|
      calls << args
      case args.first
      when 'status' then status
      when 'tag' then args.include?('-a') ? '' : tags
      when 'push' then ''
      end
    end

    [git, calls]
  end

  def fake_config(tag: true, push: true)
    Struct.new(:tag, :push, :previous_versions) do
      def git_tag? = tag
      def git_push? = push

      def write_previous_version(version)
        previous_versions << version
      end
    end.new(tag, push, [])
  end

  def fake_version_file(version: '1.2.3')
    Struct.new(:current_version, :writes) do
      def version = current_version

      def write(version)
        writes << version
      end
    end.new(version, [])
  end
end
