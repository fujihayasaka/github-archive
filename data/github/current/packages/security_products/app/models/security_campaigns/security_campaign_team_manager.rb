# typed: strict
# frozen_string_literal: true

class SecurityCampaigns::SecurityCampaignTeamManager < ApplicationRecord::Domain::SecurityCampaigns
  belongs_to :security_campaign, optional: false, inverse_of: :team_managers
  belongs_to :team, optional: false
end
