# typed: true
# frozen_string_literal: true

require "pathname"

module GitHub
  module AppEnvironment

    def self.env
      @env ||= ENV["RAILS_ENV"]
    end

    def self.root
      @root ||= Pathname.new(ENV["RAILS_ROOT"])
    end

    def self.development?
      env == "development"
    end

    def self.test?
      env == "test"
    end

    def self.production?
      env == "production"
    end

    def self.staging?
      env == "staging"
    end

    def self.fi?
      env == "fi"
    end
  end
end
