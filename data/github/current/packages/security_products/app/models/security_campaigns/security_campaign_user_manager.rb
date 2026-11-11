# typed: strict
# frozen_string_literal: true

class SecurityCampaigns::SecurityCampaignUserManager < ApplicationRecord::Domain::SecurityCampaigns
  belongs_to :security_campaign, optional: false, inverse_of: :user_managers
  include ::Users::BelongsToUser
  belongs_to_user_via_domain optional: false
end
