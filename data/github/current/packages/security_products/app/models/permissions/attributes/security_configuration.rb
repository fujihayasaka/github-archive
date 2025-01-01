# typed: true
# frozen_string_literal: true

module Permissions
  module Attributes
    class SecurityConfiguration < Default
      def subject_attributes
        base = super.merge(
          "subject.target_type": participant.target_type,
          "subject.target_id": participant.target_id,
          "subject.business.id": participant.target&.async_business&.sync&.id,
        )

        if participant.target_type == "User"
          base.merge(
            # NOTE: If we ever add actual User support to SecurityConfigurations, we'll need to figure out how to
            #   differentiate them from Organizations, because they'll both have `target_type: 'User'`
            "subject.organization.id" => participant.target_id,
          )
        else
          base
        end
      end
    end
  end
end
