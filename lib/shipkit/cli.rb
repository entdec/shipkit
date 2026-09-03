# frozen_string_literal: true

module Shipkit
  class CLI
    USAGE = <<~USAGE
      Usage: shipkit releasenotes FROM TO
             shipkit release (#{ReleaseCommand::BUMPS.join("|")})
             shipkit version
    USAGE

    def self.run(argv)
      new(argv).run
    end

    def initialize(argv)
      @argv = argv
    end

    def run
      case @argv.first
      when "releasenotes" then releasenotes(@argv[1..])
      when "release" then release(@argv[1..])
      when "version" then version(@argv[1..])
      else
        error(USAGE)
        64
      end
    end

    private

    def releasenotes(args)
      unless args.length == 2
        error("Usage: shipkit releasenotes FROM TO")
        return 64
      end

      from, to = args
      llm = Llm.new
      # rubocop:disable Rails/Output -- This is a CLI, stdout is the product.
      print Generator.new("#{from}..#{to}", llm:).generate
      # rubocop:enable Rails/Output
      # rubocop:disable Style/StderrPuts -- Ruby's warn is suppressed when RUBYOPT=-W0.
      $stderr.puts if llm.enabled?
      # rubocop:enable Style/StderrPuts
      0
    rescue Generator::GitError, ArgumentError => e
      error("shipkit: #{e.message}")
      1
    end

    def release(args)
      unless args.length == 1 && ReleaseCommand::BUMPS.include?(args.first)
        error("Usage: shipkit release (#{ReleaseCommand::BUMPS.join("|")})")
        return 64
      end

      tag = ReleaseCommand.new(args.first).call
      # rubocop:disable Rails/Output -- This is a CLI, stdout is the product.
      puts "Released #{tag}"
      # rubocop:enable Rails/Output
      0
    rescue ReleaseCommand::Error, ArgumentError => e
      error("shipkit: #{e.message}")
      1
    end

    def version(args)
      unless args.empty?
        error("Usage: shipkit version")
        return 64
      end

      # rubocop:disable Rails/Output -- This is a CLI, stdout is the product.
      puts VersionFile.new.version
      # rubocop:enable Rails/Output
      0
    rescue VersionFile::Error => e
      error("shipkit: #{e.message}")
      1
    end

    # rubocop:disable Style/StderrPuts -- Ruby's warn is suppressed when RUBYOPT=-W0.
    def error(message)
      $stderr.puts message
    end
    # rubocop:enable Style/StderrPuts
  end
end
