# typed: strict
# frozen_string_literal: true

module GitHub
  module Packwerk
    class Metrics
      extend T::Sig

      sig { returns(T::Hash[String, T::Hash[Symbol, T::Hash[Symbol, Integer]]]) }
      def violation_counts
        all_packages = ParsePackwerk.all

        default_violations = { outbound: 0, inbound: 0 }
        default_package_hash = Hash.new { |h, k| h[k] = default_violations.dup }
        package_violations = Hash.new { |h, k| h[k] = default_package_hash.dup }

        all_packages.each do |package|
          package_violations[package.name][:dependency_enforcement] = package.enforces_dependencies?
          package_violations[package.name][:privacy_enforcement] = package.enforces_privacy?
          package.violations.each do |violation|
            package_violations[package.name][violation.type.to_sym][:outbound] += violation.files.count
            package_violations[violation.to_package_name][violation.type.to_sym][:inbound] += violation.files.count
          end
        end

        package_violations
      end
    end
  end
end
