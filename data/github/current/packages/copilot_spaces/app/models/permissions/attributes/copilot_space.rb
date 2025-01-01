# typed: true
# frozen_string_literal: true

module Permissions
  module Attributes
    class CopilotSpace < Default
      def subject_attributes
        owner = participant.owner
        owner_type = owner.organization? ? "Organization" : participant.owner_type
        creator = participant.creator || participant.owner

        super.merge(
          "subject.owner.id"               => participant.owner_id,
          "subject.owner.type"             => owner_type,
          "subject.creator.id"             => creator.id,
          "subject.visibility"             => participant.visibility,
          "subject.business.id"            => owner.async_business&.sync&.id,
        )
      end
    end
  end
end
