# frozen_string_literal: true

module Shipkit
  # Reads the VERSION constant from a project's lib/version.rb (e.g. lib/<name>/version.rb).
  class VersionFile
    class Error < StandardError; end

    PATTERN = /VERSION\s*=\s*["']([^"']+)["']/

    def initialize(path: nil)
      @path = path || find_path
    end

    def version
      raise Error, "no version.rb found under lib/" unless @path
      raise Error, "no such file: #{@path}" unless File.exist?(@path)

      match = File.read(@path).match(PATTERN)
      raise Error, "no VERSION constant found in #{@path}" unless match

      match[1]
    end

    private

    def find_path
      Dir.glob("lib/**/version.rb").min_by { |path| path.count("/") }
    end
  end
end
