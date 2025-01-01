# typed: true
# frozen_string_literal: true

module Permissions
  module Attributes
    class DiscussionCategory < Default
      sig { returns(T.untyped) }
      def subject_attributes
        base = super.merge(
          "subject.owner.id"              => participant.repository&.owner_id,
          "subject.repository.id"         => participant.repository_id,
          "subject.repository.writable"   => participant.repository&.writable?,
          "subject.repository.internal"   => participant.repository&.internal?,
          "subject.repository.public"     => participant.repository&.public?,
          "subject.repository.owner.id"   => participant.repository&.owner_id,
          "subject.repository.owner.type" => participant.repository_owner&.class.name,
          "subject.business.id"           => participant.repository&.owner&.async_business.sync&.id,
          "subject.discussion_category.supports_announcements" => participant.supports_announcements?,
        )
        if FeatureFlag.vexi.enabled?(:authzd_include_subject_organization_id, default: false)
          base = base.merge(
            "subject.organization.id" => participant.repository&.owner&.organization? ? participant.repository.owner.id : nil
          )
        end
        base
      end
    end
  end
end
