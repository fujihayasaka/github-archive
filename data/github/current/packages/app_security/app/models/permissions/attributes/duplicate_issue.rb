# typed: true
# frozen_string_literal: true

module Permissions
  module Attributes
    class DuplicateIssue < Default
      def subject_attributes
        base = super.merge(
          "subject.repository.id"         => participant.repository.id,
          "subject.repository.owner.id"   => participant.repository.owner_id,
          "subject.repository.owner.type" => participant.repository.owner.class.name,
          "subject.actor.id"              => participant.actor_id,
          "related_action"                => :mark_as_duplicate,
          "subject.owner.id"              => participant.repository.owner_id,
          "subject.business.id"           => participant.repository.owner&.async_business&.sync&.id,
        )
        if FeatureFlag.vexi.enabled?(:authzd_include_subject_organization_id, default: false)
          base = base.merge(
            "subject.organization.id" => participant.repository&.owner&.organization? ? participant.repository.owner_id : nil
          )
        end
        base
      end
    end
  end
end
