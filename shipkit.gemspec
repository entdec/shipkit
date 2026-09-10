# frozen_string_literal: true

require_relative "lib/shipkit/version"

Gem::Specification.new do |spec|
  spec.name = "shipkit"
  spec.version = Shipkit::VERSION
  spec.authors = ["Boxture"]
  spec.summary = "Release toolkit: generate Keep a Changelog style release notes from Conventional Commits and cut tagged releases"
  spec.homepage = "https://github.com/boxture/server"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir["lib/**/*", "exe/*"]
  spec.bindir = "exe"
  spec.executables = ["shipkit"]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "ruby_llm"
end
