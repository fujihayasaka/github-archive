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
        enabled = false
        if !repo.owner.nil? && repo.owner&.organization?
          org = T.cast(repo.owner, ::Organization)
          enabled = ::Copilot::Organization.new(org).can_use_copilot_enterprise_features?
        end

        enabled
      end
    end
  end
end
