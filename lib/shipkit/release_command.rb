# frozen_string_literal: true

require 'open3'

module Shipkit
  # Bumps the latest vX.Y.Z git tag, then tags and pushes the release (à la gem-release).
  class ReleaseCommand
    class Error < StandardError; end

    BUMPS = %w[major minor patch].freeze
    TAG_PATTERN = /\Av(\d+)\.(\d+)\.(\d+)\z/

    def initialize(bump, git: nil, remote: 'origin', config: nil, version_file: VersionFile.new)
      raise ArgumentError, "bump must be one of #{BUMPS.join(', ')}" unless BUMPS.include?(bump.to_s)

      @bump = bump.to_s
      @git = git || method(:run_git)
      @remote = remote
      @config = config || Config.load
      @version_file = version_file
    end

    def call
      tag = "v#{bump_version(latest_version)}"

      raise Error, 'working tree has uncommitted changes' if @config.git_tag? && dirty?

      begin
        @config.write_previous_version(@version_file.version)
        @version_file.write(tag.delete_prefix('v'))
      rescue VersionFile::Error, SystemCallError => e
        raise Error, e.message
      end

      @git.call('tag', '-a', tag, '-m', "Release #{tag}") if @config.git_tag?

      if @config.git_push?
        @git.call('push', @remote, 'HEAD')
        @git.call('push', @remote, tag) if @config.git_tag?
      end

      tag
    end

    private

    def dirty?
      !@git.call('status', '--porcelain').strip.empty?
    end

    def latest_version
      versions = @git.call('tag', '--list', 'v*').split("\n").filter_map do |tag|
        tag.match(TAG_PATTERN)&.captures&.map(&:to_i)
      end

      versions.max || [0, 0, 0]
    end

    def bump_version(version)
      major, minor, patch = version

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
