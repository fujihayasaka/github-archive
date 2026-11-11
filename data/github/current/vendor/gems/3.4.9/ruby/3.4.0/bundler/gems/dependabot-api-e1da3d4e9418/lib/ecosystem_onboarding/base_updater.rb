# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

# Base class for ecosystem onboarding file updaters
class EcosystemOnboarding
  class BaseUpdater
    extend T::Sig

    sig { returns(String) }
    attr_reader :ecosystem_name

    sig { returns(String) }
    attr_reader :package_manager_name

    sig { returns(Pathname) }
    attr_reader :root_path

    sig { returns(String) }
    attr_reader :mode

    sig do
      params(
        ecosystem_name: String,
        package_manager_name: String,
        root_path: Pathname,
        mode: String
      ).void
    end
    def initialize(ecosystem_name:, package_manager_name:, root_path:, mode:)
      @ecosystem_name = T.let(ecosystem_name, String)
      @package_manager_name = T.let(package_manager_name, String)
      @root_path = T.let(root_path, Pathname)
      @mode = T.let(mode, String)
    end

    sig { returns(T::Hash[Symbol, T::Array[String]]) }
    def update
      raise NotImplementedError, "Subclasses must implement #update"
    end

    private

    sig { params(file_path: Pathname, change_description: String).returns(T::Boolean) }
    def should_proceed?(file_path, change_description)
      return true if mode == "overwrite"
      return false if mode == "skip"

      Rails.logger.debug { "\n#{change_description} in #{file_path}? [y/N] " }
      response = ($stdin.gets&.chomp || "").downcase
      %w(y yes).include?(response)
    end

    sig { returns(String) }
    def protobuf_constant_name
      ecosystem_name.upcase.tr("-", "_")
    end

    sig { returns(String) }
    def package_manager_constant_name
      package_manager_name.upcase.tr("-", "_")
    end
  end
end
