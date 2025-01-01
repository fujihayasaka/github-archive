# typed: strict
# frozen_string_literal: true

require "github/packwerk/privacy/violations_against_constant"

module GitHub
  module Packwerk
    module Privacy
      class ViolationsAgainstPackage
        extend T::Sig

        sig { returns(String) }
        attr_reader :package_name

        sig { returns(T::Hash[String, ViolationsAgainstConstant]) }
        attr_reader :violations

        sig { params(package_name: String).void }
        def initialize(package_name)
          @package_name = package_name
          @violations = T.let({}, T::Hash[String, ViolationsAgainstConstant])
          # { constant: ViolationsAgainstConstant }
        end

        sig { params(offending_package: String, violation: ParsePackwerk::Violation).void }
        def add_violation(offending_package, violation)
          collection = violations[violation.class_name] ||= ViolationsAgainstConstant.new(violation.class_name)
          collection.add_violation(offending_package, violation.files)
        end

        sig { returns(T::Hash[String, T::Hash[String, T::Array[String]]]) }
        def to_h
          violations.sort.to_h.transform_values(&:to_h)
        end
      end
    end
  end
end
