# typed: strict
# frozen_string_literal: true

module GitHub
  module Packwerk
    class PackageYmlLinter
      class PackageYmlError < StandardError; end

      sig { void }
      def self.check!
        missing_package_ymls = []
        Dir.glob("packages/*").each do |package_path|
          full_path = File.join(Rails.root, package_path)
          next unless File.directory?(full_path)

          missing_package_ymls << package_path unless File.exist?(File.join(full_path, "package.yml"))
        end

        raise PackageYmlError, "`package.yml` is missing for the following packages: #{missing_package_ymls.join(", ")}" unless missing_package_ymls.empty?
      end
    end
  end
end
