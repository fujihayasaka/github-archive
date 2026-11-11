# typed: strict
# frozen_string_literal: true

require "pathname"

module OctoCore
  module AppEnvironment
    extend T::Sig

    sig { returns(T.nilable(String)) }
    def self.env
      @env ||= T.let(ENV["RAILS_ENV"], T.nilable(String))
    end

    sig { returns(T.nilable(Pathname)) }
    def self.root
      @root ||= T.let(Pathname.new(ENV["RAILS_ROOT"]), T.nilable(Pathname))
    end

    sig { returns(T::Boolean) }
    def self.development?
      env == "development"
    end

    sig { returns(T::Boolean) }
    def self.test?
      env == "test"
    end

    sig { returns(T::Boolean) }
    def self.production?
      env == "production"
    end

    sig { returns(T::Boolean) }
    def self.staging?
      env == "staging"
    end

    sig { returns(T::Boolean) }
    def self.fi?
      env == "fi"
    end

    @app_name = T.let("unnamed", String)
    sig { returns(String) }
    def self.app_name
      @app_name
    end

    @qualified_app_name = T.let(nil, T.nilable(String))
    sig { returns(String) }
    def self.qualified_app_name
      @qualified_app_name ||= [app_name, env].compact.join("-")
    end

    sig { params(name: String).void }
    def self.app_name=(name)
      @app_name = name
      @qualified_app_name = nil
    end

    @host_name = T.let("unnamed_app_host", String)
    sig { returns(String) }
    def self.host_name
      @host_name
    end

    sig { params(name: String).void }
    def self.host_name=(name)
      @host_name = name
    end
  end
end
