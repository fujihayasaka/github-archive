# typed: true
# frozen_string_literal: true

module Permissions
  module Attributes
    class MemexProject < Default
      def subject_attributes
        base = super.merge(
          "subject.creator.id"             => participant.creator_id,
          "subject.public"                 => participant.public,
          "subject.memex_project.public"   => participant.public,
          "subject.owner.id"               => participant.owner_id,
          "subject.owner.type"             => participant.owner_type,
          "subject.organization.id"        => participant.owner_type == "Organization" ? participant.owner_id : nil,
        )

        # Populate enterprise/business-related attributes once for efficiency
        # participant is expected to be the MemexProject instance
        enterprise_attrs = participant.respond_to?(:async_enterprise_authzd_attributes) ? participant.async_enterprise_authzd_attributes.sync : {}
        # Merge in business/enterprise attributes if present
        base = base.merge(enterprise_attrs) if enterprise_attrs.present?

        base
      end
    end
  end
end
