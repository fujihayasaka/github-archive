# typed: strict
# frozen_string_literal: true

module Copilot
  module Users
    module ContentExclusion
      extend T::Helpers

      include GitHub::Memoizer
      include Copilot::Users::Signatures

      abstract!

      # This method is used to check if the user can access the repo control/content exclusion functionality
      sig { override.returns(T::Boolean) }
      def copilot_content_exclusion_enabled?
        org_ids = copilot_organizations.map(&:id)
        neighbor_org_ids = Copilot::ContentExclusion.only_neighboring_org_ids(org_ids)

        Copilot::ContentExclusionConfiguration.with_business_or_organization_ids(
          copilot_businesses.map(&:id),
          org_ids + neighbor_org_ids,
          neighbor_org_ids
        ).any?
      end

      sig { params(url_strings: T::Array[String]).returns(T::Array[Copilot::ContentExclusion::ConfigAndRules]) }
      def content_exclusion_rules_for_repo_urls(url_strings)
        config_rules_arr = Copilot::ContentExclusion.rules_for_repo_urls(
          url_strings,
          business_ids: copilot_businesses.map(&:id),
          organization_ids: copilot_organizations.map(&:id),
        )

        config_rules_arr.map do |config_rules_hash|
          config_rules_hash.select do |config, _|
            # Neighboring configs includes private repos by default. Filter out those that the user does not have access to.
            config.resource.is_a?(::Repository) ? config.resource.pullable_by?(user_object) : true
          end
        end
      end

      sig { returns(Copilot::ContentExclusion::ConfigAndRules) }
      def content_exclusion_rules_for_all_files
        Copilot::ContentExclusion.rules_for_all_files_scope(
          business_ids: copilot_businesses.map(&:id),
          organization_ids: copilot_organizations.map(&:id)
        )
      end
    end
  end
end
