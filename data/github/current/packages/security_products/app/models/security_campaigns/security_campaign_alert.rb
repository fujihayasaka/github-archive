# typed: true
# frozen_string_literal: true

class SecurityCampaigns::SecurityCampaignAlert < ApplicationRecord::Domain::SecurityCampaigns
  belongs_to :security_campaign
  belongs_to :repository

  validates :security_campaign_id, presence: true
  validates :repository_id, presence: true
  validates :logical_alert_number, presence: true
end
