source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }
git_source(:entdec) { |repo_name| "git@github.com:entdec/#{repo_name}.git" }

# Specify your gem's dependencies in mensa.gemspec.
gemspec

group :development, :test do
  gem 'rubocop-rails', require: false
  gem 'ruby-lsp', require: false
  gem 'ruby-lsp-rails', require: false
  gem 'standard', '>= 1.35.1', require: false
end
