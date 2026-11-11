# typed: true
# frozen_string_literal: true

module Permissions
  module Attributes
    class MemberFeatureRequest < Default
      def subject_attributes
        super.merge(
          subject_owner_attributes => participant.entity_id,
        )
      end

      private

      def subject_owner_attributes
        {
          "Business" => "subject.business.id",
          "User" => "subject.owning_organization.id"
        }[participant.entity_type]
      end
    end
  end
end
