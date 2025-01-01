# typed: true
# frozen_string_literal: true

module Permissions
  module Attributes
    class RepositoryAdvisory < Default
      def subject_attributes
        base = super.merge(
          "subject.published"              => participant.published?,
          "subject.repository.id"          => participant.repository_id,
          "subject.repository.owner.id"    => participant.repository&.owner_id,
          "subject.repository.public"      => participant.repository&.public?,
          "subject.repository.internal"    => participant.repository&.internal?,
          "subject.owning_organization.id" => participant.repository&.owning_organization_id,
          "subject.business.id" => participant.repository.owner&.async_business&.sync&.id,
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
