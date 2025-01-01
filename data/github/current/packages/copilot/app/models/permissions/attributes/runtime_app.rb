# typed: true
# frozen_string_literal: true

module Permissions
  module Attributes
    class RuntimeApp < Default
      def subject_attributes
        result = super.merge(
          "subject.owner.id" => participant.user_id,
          # "subject.permitted_organization.id" => org from somewhere,
          "subject.visibility" => converted_visibility,
        )
        result
      end

      # To clarify for authzd policies, we rename github to logged_in_user
      def converted_visibility
        participant.visibility == "github" ? "logged_in_user" : participant.visibility
      end
    end
  end
end
