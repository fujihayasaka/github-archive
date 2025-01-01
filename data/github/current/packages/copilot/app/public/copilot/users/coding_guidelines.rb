# typed: strict
# frozen_string_literal: true

module Copilot
  module Users
    module CodingGuidelines
      extend T::Helpers

      include Copilot::Users::Signatures

      abstract!

      # This method is used to check if the user can access the coding guidelines for copilot code review.
      sig { override.params(repo: Repository).returns(T::Boolean) }
      def copilot_coding_guidelines_enabled?(repo)
        return false unless copilot_user_object.feature_enabled?(:copilot_coding_guidelines) || repo.feature_enabled_for_repo_or_owner?(:copilot_coding_guidelines)
        return false unless repo.owner&.organization?
        return false unless repo.adminable_by?(copilot_user_object)
        copilot_enterprise_organizations.any?
      end
    end
  end
end
