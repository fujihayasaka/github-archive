# typed: true
# frozen_string_literal: true

module Permissions
  module Attributes
    class DuplicateIssue < Default
      def subject_attributes
        super.merge(
          "subject.repository.id"         => participant.repository.id,
          "subject.repository.owner.id"   => participant.repository.owner_id,
          "subject.repository.owner.type" => participant.repository.owner.class.name,
          "subject.actor.id"              => participant.actor_id,
          "related_action"                => :mark_as_duplicate,
          "subject.owner.id"              => participant.repository.owner_id,
          "subject.business.id"           => participant.repository.owner&.async_business&.sync&.id,
          "subject.organization.id"       => participant.repository&.owner&.organization? ? participant.repository.owner_id : nil,
        )
      end
    end
  end
end
