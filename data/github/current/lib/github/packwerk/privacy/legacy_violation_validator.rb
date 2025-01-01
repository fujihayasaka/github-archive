# typed: strict
# frozen_string_literal: true

require "github/packwerk/privacy/violations_against_packages"
require "github/packwerk/privacy/legacy_exemptions"

module GitHub
  module Packwerk
    module Privacy
      class LegacyViolationValidator
        extend T::Sig

        PRIVACY_LEGACY_FILENAME = "privacy_legacy.yml"

        class NoLegacyViolationFileError < StandardError; end

        class ViolationResults < T::Struct
          extend T::Sig

          prop :new_violations, T::Hash[String, T::Array[String]]
          prop :resolved_violations, T::Hash[String, T::Array[String]]

          sig { returns(T::Boolean) }
          def none?
            new_violations.length == 0 && resolved_violations.length == 0
          end
        end

        sig { void }
        def self.check!
          new.check!
        end

        sig { returns(ViolationsAgainstPackages) }
        attr_reader :violations_collection

        sig { void }
        def initialize
          @violations_collection = T.let(ViolationsAgainstPackages.new, ViolationsAgainstPackages)
          @_violations = T.let(nil, T.nilable(ViolationResults))
        end

        sig { returns(T::Boolean) }
        def any_violations?
          violations.new_violations.any? || violations.resolved_violations.any?
        end

        sig { void }
        def check!
          if violations.none?
            puts "No new non-legacy violations found and no resolved legacy violations found"
            return
          end

          violations.new_violations.each do |constant_name, violations|
            puts "Found new privacy violations for #{constant_name}"

            violations.each do |violation|
              puts "  - #{violation}"
            end

            puts "\nPlease fix this violation by using a public package interface or asking the relevant team for an exemption in privacy_legacy.yml\n"
          end

          violations.resolved_violations.each do |constant_name, violations|
            puts "Found resolved privacy violations for #{constant_name}"

            violations.each do |violation|
              puts "  - #{violation}"
            end

            puts "\nPlease remove these files from privacy_legacy.yml\n"
          end

          exit 1
        end

        sig { returns(ViolationResults) }
        def violations
          return @_violations if @_violations
          @_violations = ViolationResults.new(new_violations: {}, resolved_violations: {})

          violations_from_package_todos.each do |package_name, package_violations|
            legacy_excemptions = legacy_exemptions_for(package_name)
            next unless legacy_excemptions.supports_legacy_checks?

            if !legacy_excemptions.privacy_legacy_file_exists?
              raise NoLegacyViolationFileError, "Legacy checks enabled for `#{package_name}` but privacy_legacy.yml does not exist! Please disable privacy checks or create the privacy_legacy.yml file."
            end

            package_violations.to_h.each do |constant_name, constant_violations|
              all_violations = constant_violations.values.flatten
              non_legacy_exemptions = all_violations - legacy_excemptions.constant_violations(constant_name)

              if non_legacy_exemptions.length > 0
                @_violations.new_violations[constant_name] = non_legacy_exemptions
              end

              resolved_legacy_exemptions = legacy_excemptions.constant_violations(constant_name) - all_violations
              if resolved_legacy_exemptions.length > 0
                @_violations.resolved_violations[constant_name] = resolved_legacy_exemptions
              end
            end
          end

          @_violations
        end

        private

        sig { params(package_name: String).returns(LegacyExemptions) }
        def legacy_exemptions_for(package_name)
          LegacyExemptions.new(package_name)
        end

        sig { returns(T::Hash[String, ViolationsAgainstPackage]) }
        def violations_from_package_todos
          violations_collection.all_violations
        end
      end
    end
  end
end
