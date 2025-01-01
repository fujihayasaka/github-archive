# typed: strict
# frozen_string_literal: true

module GitHub
  module Packwerk
    module Privacy
      class ViolationsAgainstConstant
        extend T::Sig

        sig { returns(String) }
        attr_reader :constant_name

        sig { returns(T::Hash[String, T::Array[String]]) }
        attr_reader :violations

        sig { params(constant_name: String).void }
        def initialize(constant_name)
          @constant_name = constant_name
          @violations = T.let({}, T::Hash[String, T::Array[String]])
          # { package_name: [files] }
        end

        sig { params(package_name: String, files: T::Array[String]).void }
        def add_violation(package_name, files)
          violation_sources = violations[package_name] ||= []
          violation_sources.concat(files)
        end

        sig { returns(T::Hash[String, T::Array[String]]) }
        def to_h
          # hash key insertion order ensures consistent yaml output
          sorted_package_names = violations.keys.sort!
          sorted_package_names.reduce({}) { |hash, key| hash[key] = violations[key]; hash }
        end
      end
    end
  end
end
