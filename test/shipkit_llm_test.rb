# frozen_string_literal: true

require "test_helper"
require "stringio"

class ShipkitLlmTest < Minitest::Test
  def test_summarize_commit_returns_nil_when_disabled
    llm = Shipkit::Llm.new(config: fake_config(enabled: false), chat: fake_chat("ignored"))

    assert_nil llm.summarize_commit(commit(subject: "add search"))
  end

  def test_summarize_release_returns_nil_when_disabled
    llm = Shipkit::Llm.new(config: fake_config(enabled: false), chat: fake_chat("ignored"))

    assert_nil llm.summarize_release([commit(subject: "add search")])
  end

  def test_summarize_release_returns_nil_when_there_are_no_commits
    llm = Shipkit::Llm.new(config: fake_config(enabled: true), chat: fake_chat("ignored"))

    assert_nil llm.summarize_release([])
  end

  def test_summarize_commit_asks_the_configured_chat_when_enabled
    llm = Shipkit::Llm.new(config: fake_config(enabled: true), chat: fake_chat("Adds search to the app."))

    assert_equal "Adds search to the app.", llm.summarize_commit(commit(subject: "feat: add search"))
  end

  def test_summarize_release_asks_the_configured_chat_when_enabled
    llm = Shipkit::Llm.new(config: fake_config(enabled: true), chat: fake_chat("This release adds search."))

    assert_equal "This release adds search.", llm.summarize_release([commit(subject: "feat: add search")])
  end

  def test_summarize_commit_returns_nil_and_reports_the_error_when_the_chat_raises
    failing_chat = Object.new.tap { |chat| def chat.ask(_prompt) = raise("boom") }
    llm = Shipkit::Llm.new(config: fake_config(enabled: true), chat: failing_chat)

    result, stderr = capture_stderr { llm.summarize_commit(commit(subject: "feat: add search")) }

    assert_nil result
    assert_includes stderr, "boom"
  end

  def test_configures_the_provider_api_base_from_llm_base_url
    require "ruby_llm"
    config = fake_config(enabled: true, provider: "ollama", model: "qwen3:8b", base_url: "http://example.test/v1")
    llm = Shipkit::Llm.new(config: config)

    llm.send(:build_chat)

    assert_equal "http://example.test/v1", RubyLLM.config.ollama_api_base
  ensure
    RubyLLM.config.ollama_api_base = nil
  end

  private

  def capture_stderr
    original_stderr = $stderr
    $stderr = StringIO.new
    result = yield
    [result, $stderr.string]
  ensure
    $stderr = original_stderr
  end

  def commit(subject:)
    Shipkit::Generator::Commit.new(
      sha: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      short_sha: "aaaaaaa",
      date: "2026-08-30",
      decorations: "",
      type: "feat",
      scope: nil,
      subject:,
      breaking_changes: []
    )
  end

  def fake_config(enabled:, provider: nil, model: nil, base_url: nil)
    Class.new do
      define_method(:llm_enabled?) { enabled }
      define_method(:llm_provider) { provider }
      define_method(:llm_model) { model }
      define_method(:llm_base_url) { base_url }
    end.new
  end

  def fake_chat(response)
    Class.new do
      define_method(:ask) { |_prompt| Struct.new(:content).new(response) }
    end.new
  end
end
