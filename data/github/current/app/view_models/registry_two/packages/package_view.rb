# typed: true
# frozen_string_literal: true

module RegistryTwo
  module Packages
    class PackageView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      include ActionView::Helpers::NumberHelper
      include ActionView::Helpers::DateHelper
      include UrlHelper
      include EscapeHelper
      include BlobMarkupHelper
      include RegistryTwo::PackageReadmeHelper

      attr_reader :owner, :metadata, :tagged_package_versions, :repository, :repositories, :package_download_counts, :viewer_is_admin, :viewer_can_read_repo, :user_type, :current_user

      delegate :package, :total_version_count, to: :metadata
      delegate :platforms, to: :latest_version

      def is_actions_package?
        package.is_actions_package?(current_user)
      end

      def latest_version
        return package.latest_non_signature_version(current_user) if GitHub.flipper[:search_action_packages].enabled?(current_user)
        metadata.latest_version
      end

      def last_published
        time_ago = time_ago_in_words(Time.at(latest_version.created_at))
        time_ago.gsub("about ", "")
      end

      def readme
        package_readme(package_version: latest_version, repository: repository)
      end

      def readme_name_for_display
        readme&.name&.force_encoding("utf-8")&.scrub!
      end

      def repository_action
        return nil unless is_actions_package?
        return nil unless package.repository
        @repository_action ||= RepositoryAction.find_by(repository: package.repository)
      end

      # Public: The cached count of the repository's contributors.
      #
      # Returns: Int
      def contributor_count
        @contributor_count ||= CommitContribution.contributors_count_for_repository(repository)
      end

      def formatted_count(total)
        # Should not occur, but covers the edge case
        return 0 if total < 0

        if total.between?(0, 999)
          total
        else
          number_to_human(
            total,
            format: "%n%u",
            units: {
              thousand: "K",
              million: "M",
              billion: "B"
            }
          )
        end
      end

      def show_publish_action_banner?
        return false unless GitHub.flipper[:action_package_marketplace].enabled?(current_user)
        return false unless logged_in?
        return false if GitHub.enterprise?
        return false if current_user.dismissed_notice?(UserNotice::PUBLISH_ACTION_FROM_REPO_NOTICE)
        return false unless repository&.pushable_by?(current_user)
        return false unless repository&.listable_action?
        return false if repository&.listed_action && repository_action&.action_package_listed

        true
      end
    end
  end
end
