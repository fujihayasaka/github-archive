# typed: strict
# frozen_string_literal: true

require "parse_packwerk"
require "github/packwerk/privacy/violations_against_package"

module GitHub
  module Packwerk
    module Privacy
      class ViolationsAgainstPackages
        sig { void }
        def initialize
          @packwerk_packages = T.let([], T::Array[ParsePackwerk::Package])
          @packwerk_todos = T.let([], T::Array[ParsePackwerk::PackageTodo])
          @all_violations = T.let({}, T::Hash[String, ViolationsAgainstPackage])
          # { package_name: ViolationsAgainstPackage }
        end

        sig { returns(T::Hash[String, ViolationsAgainstPackage]) }
        def all_violations
          parse_from_package_todos if @all_violations.empty?
          @all_violations
        end

        sig { returns(T::Array[ParsePackwerk::Package]) }
        def packwerk_packages
          return @packwerk_packages unless @packwerk_packages.empty?

          @packwerk_packages = ParsePackwerk.all
        end

        sig { returns(T::Array[ParsePackwerk::PackageTodo]) }
        def packwerk_todos
          return @packwerk_todos unless @packwerk_todos.empty?

          @packwerk_todos = packwerk_packages.map { |package| ParsePackwerk::PackageTodo.for(package) }
        end

        private

        sig { void }
        def parse_from_package_todos
          packwerk_packages.each do |package|
            package.violations.each do |violation|
              add_violation(package, violation)
            end
          end
        end

        sig { params(package: ParsePackwerk::Package, violation: ParsePackwerk::Violation).void }
        def add_violation(package, violation)
          return unless violation.privacy?

          collection = @all_violations[violation.to_package_name] ||= ViolationsAgainstPackage.new(violation.to_package_name)
          collection.add_violation(package.name, violation)
        end
      end
    end
  end
end
