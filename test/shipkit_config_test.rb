# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class ShipkitConfigTest < Minitest::Test
  def test_defaults_to_tag_and_push_enabled_when_no_file_exists
    Dir.mktmpdir do |dir|
      config = Shipkit::Config.load(File.join(dir, ".shipkit.yml"))

      assert config.git_tag?
      assert config.git_push?
    end
  end

  def test_reads_git_tag_and_push_from_the_file
    with_config("git:\n  push: false\n  tag: false\n") do |config|
      refute config.git_tag?
      refute config.git_push?
    end
  end

  def test_defaults_missing_keys_to_true
    with_config("git:\n  tag: false\n") do |config|
      refute config.git_tag?
      assert config.git_push?
    end
  end

  def test_defaults_llm_provider_and_model_to_nil_when_no_file_exists
    Dir.mktmpdir do |dir|
      config = Shipkit::Config.load(File.join(dir, ".shipkit.yml"))

      assert_nil config.llm_provider
      assert_nil config.llm_model
    end
  end

  def test_reads_llm_provider_and_model_from_the_file
    with_config("llm:\n  provider: ollama\n  model: qwen3:8b\n") do |config|
      assert_equal "ollama", config.llm_provider
      assert_equal "qwen3:8b", config.llm_model
    end
  end

  def test_defaults_llm_base_url_to_nil_when_no_file_exists
    Dir.mktmpdir do |dir|
      config = Shipkit::Config.load(File.join(dir, ".shipkit.yml"))

      assert_nil config.llm_base_url
    end
  end

  def test_reads_llm_base_url_from_the_file
    with_config("llm:\n  provider: ollama\n  base_url: http://host.docker.internal:11434/\n") do |config|
      assert_equal "http://host.docker.internal:11434/", config.llm_base_url
    end
  end

  def test_llm_is_disabled_when_no_file_exists
    Dir.mktmpdir do |dir|
      config = Shipkit::Config.load(File.join(dir, ".shipkit.yml"))

      refute config.llm_enabled?
    end
  end

  def test_llm_is_disabled_when_set_to_false
    with_config("llm: false\n") do |config|
      refute config.llm_enabled?
    end
  end

  def test_llm_is_enabled_when_configured
    with_config("llm:\n  provider: ollama\n  model: qwen3:8b\n") do |config|
      assert config.llm_enabled?
    end
  end

  private

  def with_config(yaml)
    Dir.mktmpdir do |dir|
      path = File.join(dir, ".shipkit.yml")
      File.write(path, yaml)
      yield Shipkit::Config.load(path)
    end
  end
end
