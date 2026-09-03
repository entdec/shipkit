# frozen_string_literal: true

module Shipkit
  # Summarizes commits and releases via RubyLLM (https://rubyllm.com). No-ops when disabled in config.
  class Llm
    def initialize(config: Config.load, chat: nil)
      @config = config
      @chat = chat
    end

    def enabled?
      @config.llm_enabled?
    end

    def summarize_commit(commit)
      return nil unless enabled?

      ask(<<~PROMPT)
        Rewrite the following Git commit subject as a single, clear sentence for a changelog aimed at end users.
        Do not mention the commit type or scope prefix, do not add information that isn't in the subject.
        Respond with the rewritten sentence only, no quotes, no extra commentary.

        Commit subject: #{commit.subject}
      PROMPT
    end

    def summarize_release(commits)
      return nil unless enabled?
      return nil if commits.empty?

      subjects = commits.map { |commit| "- #{commit.subject}" }.join("\n")
      ask(<<~PROMPT)
        Write a short summary (2-4 sentences) of this software release for end users, based on the list of changes below.
        Respond with the summary only, no heading, no bullet points.

        Changes:
        #{subjects}
      PROMPT
    end

    private

    def ask(prompt)
      report_progress
      chat.ask(prompt).content.to_s.strip
    rescue => e
      report_error(e)
      nil
    end

    def chat
      @chat ||= build_chat
    end

    def build_chat
      require "ruby_llm"
      configure!

      options = {assume_model_exists: true}
      options[:provider] = @config.llm_provider.to_sym if @config.llm_provider
      options[:model] = @config.llm_model if @config.llm_model
      RubyLLM.chat(**options)
    end

    # RubyLLM doesn't read these from ENV itself, so wire up the providers we support.
    def configure!
      RubyLLM.configure do |config|
        config.openai_api_key ||= ENV["OPENAI_API_KEY"]
        config.anthropic_api_key ||= ENV["ANTHROPIC_API_KEY"]
        config.ollama_api_base ||= ENV.fetch("OLLAMA_API_BASE", "http://localhost:11434/v1")
        config.ollama_api_key ||= ENV["OLLAMA_API_KEY"]

        if @config.llm_provider && @config.llm_base_url
          config.public_send("#{@config.llm_provider}_api_base=", @config.llm_base_url)
        end
      end
    end

    # rubocop:disable Style/StderrPuts -- Ruby's warn is suppressed when RUBYOPT=-W0.
    def report_error(error)
      $stderr.puts "shipkit: LLM summarization failed (#{error.class}: #{error.message})"
    end

    def report_progress
      $stderr.print "."
    end
    # rubocop:enable Style/StderrPuts
  end
end
