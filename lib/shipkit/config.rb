# frozen_string_literal: true

require 'yaml'

module Shipkit
  # Loads .shipkit.yml, e.g.:
  #   git:
  #     push: true
  #     tag: true
  #   llm:
  #     provider: ollama
  #     model: qwen3:8b
  #     base_url: http://host.docker.internal:11434/
  # Set `llm: false` (or omit it) to disable LLM summarization entirely.
  class Config
    FILE_NAME = '.shipkit.yml'

    attr_reader :path

    def self.load(path = FILE_NAME)
      data = File.exist?(path) ? YAML.safe_load_file(path) : nil
      new(data || {}, path: path)
    end

    def initialize(data, path: FILE_NAME)
      @data = data
      @path = path
    end

    def write_previous_version(version)
      @data['previous_version'] = version
      File.write(@path, YAML.dump(@data))
    end

    def git_tag?
      fetch(%w[git tag], default: true)
    end

    def git_push?
      fetch(%w[git push], default: true)
    end

    def llm_enabled?
      fetch(%w[llm], default: false) != false
    end

    # nil means use RubyLLM's own default provider/model
    def llm_provider
      fetch(%w[llm provider], default: nil)
    end

    def llm_model
      fetch(%w[llm model], default: nil)
    end

    def llm_base_url
      fetch(%w[llm base_url], default: nil)
    end

    private

    def fetch(keys, default:)
      value = keys.reduce(@data) { |hash, key| hash[key] if hash.is_a?(Hash) }
      value.nil? ? default : value
    end
  end
end
