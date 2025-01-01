# typed: true
# frozen_string_literal: true

module Permissions
  module Attributes
    module SecurityCampaigns
      class SecurityCampaignUser < Default
        def subject_attributes
          super.merge(
            "subject.organization.id"        => participant.security_campaign.organization_id,
            "subject.owning_organization.id" => participant.security_campaign.organization_id,
            "subject.business.id"            => participant.security_campaign.organization&.async_business&.sync&.id,
            "subject.security_campaign.id"   =>  participant.security_campaign_id,
          )
        end
      end
    end
  end
end
