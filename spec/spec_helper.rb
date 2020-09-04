# frozen_string_literal: true

require 'bundler/setup'
require 'timecop'
require 'webmock/rspec'

# Configure Rails dummary app
ENV['RAILS_ENV'] ||= 'test'
require File.expand_path('dummy/config/environment.rb', __dir__)
require 'rspec/rails'

# Require main library (after Rails has done so)
require 'cloudenvoy'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
