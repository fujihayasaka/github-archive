# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    module LegacyMigration
      def feature_flag_enabled?(organization)
        GitHub.flipper[:gh_migrator_import_to_dotcom].enabled?(organization) ||
          (organization.business.present? && GitHub.flipper[:gh_migrator_import_to_dotcom].enabled?(organization.business))
      end
    end
  end
end
