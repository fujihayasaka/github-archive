# typed: strict
# frozen_string_literal: true

class SecurityCampaigns::SecurityCampaignRepository < ApplicationRecord::Domain::SecurityCampaigns
  extend T::Sig
  include ::Permissions::Attributes::Wrapper
  self.permissions_wrapper_class = ::Permissions::Attributes::SecurityCampaigns::SecurityCampaignRepository

  belongs_to :security_campaign, optional: false
  belongs_to :repository, optional: false
end
