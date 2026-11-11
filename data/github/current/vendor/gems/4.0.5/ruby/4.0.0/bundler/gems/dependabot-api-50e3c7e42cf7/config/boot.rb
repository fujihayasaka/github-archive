# frozen_string_literal: true

ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.

# Load bootsnap to speed up the app boot in development and test environments
env = ENV["RAILS_ENV"] || ENV["RACK_ENV"] || "development"
require "bootsnap/setup" if %w(development test).include?(env)
