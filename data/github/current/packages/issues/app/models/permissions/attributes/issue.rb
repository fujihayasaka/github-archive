# typed: true
# frozen_string_literal: true

module Permissions
  module Attributes
    class Issue < Default
      def subject_attributes
        base = super.merge(
          "subject.author.id"              => participant.user_id,
          "subject.repository.public"      => participant.repository.public?,
          "subject.repository.internal"    => participant.repository.internal?,
          "subject.repository.archived"    => participant.repository.archived?,
          "subject.closer.id"              => participant.closed? ? participant.closed_by&.id : nil,
          "subject.repository.owner.id"    => participant.repository.owner_id,
          "subject.owning_organization.id" => participant.repository.owning_organization_id,
          "subject.repository.owner.type"  => participant.repository.owner.class.name,
          "subject.repository.id"          => participant.repository.id,
          "subject.owner.id"               => participant.repository.owner_id,
          "subject.business.id"            => participant.repository.owner&.async_business&.sync&.id,
        )
        if FeatureFlag.vexi.enabled?(:authzd_include_subject_organization_id, default: false)
          base = base.merge(
            "subject.organization.id" => participant.repository.owner&.organization? ? participant.repository.owner.id : nil
          )
        end
        base
      end
    end
  end
end
