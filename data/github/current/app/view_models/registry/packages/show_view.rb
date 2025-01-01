# typed: true
# frozen_string_literal: true

module Registry
  module Packages
    class ShowView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels

      POM_EXT = ".pom"

      attr_reader :owner, :repository, :result
      attr_accessor :package, :package_version

      def maven_package_info(package_name, package_version, package_files)

        version = package_version.downcase.gsub("-snapshot", "")
        pom = package_files.find { |file| file.downcase.end_with?(POM_EXT) }

        # Default logic
        artifact_id = package_name.split(".").last

        # If pom found and pom file name matches regex that parses filename into artifact_id, version, and ext get artifact_id from file name
        if !pom.nil? && (parsed_filename = pom.downcase.match("(?<artifact_id>.+)-(?<version>(#{version})|(#{version}-\\d{8}\\.\\d{6}-\\d+))(?<ext>#{POM_EXT})"))
          artifact_id = parsed_filename[:artifact_id]
        end

        {
            artifact_id: artifact_id,
            group_id: package_name.chomp(".#{artifact_id}")
        }
      end
    end
  end
end
