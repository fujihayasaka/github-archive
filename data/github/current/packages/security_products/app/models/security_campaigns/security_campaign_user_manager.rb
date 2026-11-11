# typed: strict
# frozen_string_literal: true

class SecurityCampaigns::SecurityCampaignUserManager < ApplicationRecord::Domain::SecurityCampaigns
  belongs_to :security_campaign, optional: false, inverse_of: :user_managers
  belongs_to :user, optional: false
end
