# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    module LegacyMigration
      def feature_flag_enabled?(organization)
        ::FeatureFlag.vexi.enabled_or_raise?(:gh_migrator_import_to_dotcom, organization) || # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
          (organization.business.present? && ::FeatureFlag.vexi.enabled_or_raise?(:gh_migrator_import_to_dotcom, organization.business)) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      end
    end
  end
end
