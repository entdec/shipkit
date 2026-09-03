# frozen_string_literal: true

require "test_helper"
require "open3"

class ShipkitCommandTest < Minitest::Test
  EXE = File.expand_path("../exe/shipkit", __dir__)

  def test_requires_a_known_subcommand
    _output, error, status = Open3.capture3(EXE)

    assert_equal 64, status.exitstatus
    assert_match(/Usage: shipkit releasenotes FROM TO/, error)
  end

  def test_releasenotes_requires_two_revision_arguments
    _output, error, status = Open3.capture3(EXE, "releasenotes", "HEAD")

    assert_equal 64, status.exitstatus
    assert_equal "Usage: shipkit releasenotes FROM TO\n", error
  end

  def test_releasenotes_reports_invalid_revisions_without_a_stack_trace
    _output, error, status = Open3.capture3(EXE, "releasenotes", "revision-that-does-not-exist", "HEAD")

    assert_equal 1, status.exitstatus
    assert_match(/shipkit: fatal:/, error)
    refute_match(/generator\.rb:\d+/, error)
  end

  def test_release_requires_a_valid_bump_argument
    _output, error, status = Open3.capture3(EXE, "release", "banana")

    assert_equal 64, status.exitstatus
    assert_match(/Usage: shipkit release \(major\|minor\|patch\)/, error)
  end

  def test_version_prints_the_version_from_lib_version_rb
    output, _error, status = Open3.capture3(EXE, "version", chdir: File.expand_path("..", __dir__))

    assert_equal 0, status.exitstatus
    assert_equal "#{Shipkit::VERSION}\n", output
  end

  def test_version_rejects_extra_arguments
    _output, error, status = Open3.capture3(EXE, "version", "extra")

    assert_equal 64, status.exitstatus
    assert_equal "Usage: shipkit version\n", error
  end
end
