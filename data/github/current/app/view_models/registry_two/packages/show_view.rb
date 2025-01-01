# typed: true
# frozen_string_literal: true

module RegistryTwo
  module Packages
    class ShowView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      include RegistryTwo::PackageReadmeHelper
      attr_reader :owner, :package, :package_versions, :package_version, :package_download_counts, :assets, :package_tag, :viewer_is_admin, :viewer_can_read_repo, :user_type, :repository, :has_write_access, :is_package_page, :current_user

      DOWNLOAD_POINTS_OFFSET = 200 / 29

      def download_points
        return @download_points if @download_points

        max_val = package_download_counts.day_counts.max
        min_val = package_download_counts.day_counts.min
        divisor = max_val == min_val ? 1.0 : max_val - min_val
        @download_points = package_download_counts.day_counts.reverse.each_with_index.map do |value, ix|
          "#{ix * DOWNLOAD_POINTS_OFFSET},#{2 + (22.0 * (value - min_val) / (divisor))}"
        end.join(" ")
      end

      def manifest_formatted
        package_version.manifest
          .to_h
          .except(:uri)
          .deep_stringify_keys
          .deep_transform_keys { |key| key.camelize(:lower) }
          .tap do |manifest|
            manifest["labels"] = package_version.labels if package_version.labels.present?
          end
      end

      def readme
        package_readme(
          package_version: package_version,
          repository: repository,
          should_get_default: is_package_page,
          namespace: "#{package.namespace.downcase}/#{package.name.downcase}",
          viewer_can_read_repo: viewer_can_read_repo,
        )
      end

      def readme_name_for_display
        readme&.name&.force_encoding("utf-8")&.scrub!
      end

      def is_actions_package?
        package.is_actions_package?
      end

      def latest_version
        return package.latest_non_signature_version(current_user) if GitHub.flipper[:search_action_packages].enabled?(current_user)
        package_version
      end
    end
  end
end
