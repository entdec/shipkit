# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'fileutils'

class ShipkitVersionFileTest < Minitest::Test
  def test_reads_the_version_constant_from_an_explicit_path
    with_version_file("module Foo\n  VERSION = \"1.2.3\"\nend\n") do |path|
      assert_equal '1.2.3', Shipkit::VersionFile.new(path: path).version
    end
  end

  def test_writes_a_new_version_without_changing_the_rest_of_the_file
    with_version_file("module Foo\n  VERSION = \"1.2.3\"\nend\n") do |path|
      Shipkit::VersionFile.new(path: path).write('1.2.4')

      assert_equal "module Foo\n  VERSION = \"1.2.4\"\nend\n", File.read(path)
    end
  end

  def test_finds_the_shallowest_version_rb_under_lib_when_no_path_is_given
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('lib/foo')
        File.write('lib/foo/version.rb', "module Foo\n  VERSION = \"9.9.9\"\nend\n")

        assert_equal '9.9.9', Shipkit::VersionFile.new.version
      end
    end
  end

  def test_raises_when_no_version_rb_exists
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        assert_raises(Shipkit::VersionFile::Error) { Shipkit::VersionFile.new.version }
      end
    end
  end

  def test_raises_when_the_file_has_no_version_constant
    with_version_file("module Foo\nend\n") do |path|
      assert_raises(Shipkit::VersionFile::Error) { Shipkit::VersionFile.new(path: path).version }
    end
  end

  private

  def with_version_file(contents)
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'version.rb')
      File.write(path, contents)
      yield path
    end
  end
end
