# typed: strict
# frozen_string_literal: true

require "parse_packwerk"

module GitHub
  module Packwerk
    module Privacy
      class LegacyExemptions
        sig { returns(String) }
        attr_reader :package_name

        sig { params(package_name: String).void }
        def initialize(package_name)
          @package_name = package_name
          @_legacy_violations = T.let(nil, T.nilable(T::Hash[String, T.untyped]))
        end

        sig { returns(T::Boolean) }
        def supports_legacy_checks?
          package = ParsePackwerk.find(package_name)
          return false if !package

          !!package.metadata["enable_legacy_checks"]
        end

        sig { returns(T::Boolean) }
        def privacy_legacy_file_exists?
          File.exist?(privacy_legacy_path)
        end

        sig { params(constant: String).returns(T::Array[String]) }
        def constant_violations(constant)
          legacy_violations[constant] || []
        end

        private

        sig { returns(Pathname) }
        def privacy_legacy_path
          Pathname.new(
            File.join(package_name, "privacy_legacy.yml")
          ).cleanpath
        end

        sig { returns(T::Hash[String, T.untyped]) }
        def legacy_violations
          @_legacy_violations ||= YAML.safe_load(File.read(privacy_legacy_path))
        end
      end
    end
  end
end
