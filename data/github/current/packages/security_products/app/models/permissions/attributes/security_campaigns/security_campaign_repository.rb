# typed: true
# frozen_string_literal: true

module Permissions
  module Attributes
    module SecurityCampaigns
      class SecurityCampaignRepository < Default
        def subject_attributes
          super.merge(
            "subject.organization.id"        => participant.security_campaign.organization_id,
            "subject.repository.public"      => participant.repository.public?,
            "subject.repository.id"          => participant.repository_id,
            "subject.repository.owner.id"    => participant.repository.owner_id,
            "subject.repository.owner.type"  => participant.repository.owner.class.name,
            "subject.owning_organization.id" => participant.repository.owning_organization_id,
            "subject.business.id"            => participant.repository.owner&.async_business&.sync&.id,
            "subject.security_campaign.id"   =>  participant.security_campaign_id,
          )
        end
      end
    end
  end
end
