# typed: strict
# frozen_string_literal: true

class SecurityCampaigns::SecurityCampaignRepository < ApplicationRecord::Domain::SecurityCampaigns
  include ::Permissions::Attributes::Wrapper
  self.permissions_wrapper_class = ::Permissions::Attributes::SecurityCampaigns::SecurityCampaignRepository

  belongs_to :security_campaign, optional: false
  belongs_to :repository, optional: false

  sig { params(include_host: T::Boolean).returns(String) }
  def permalink(include_host: true)
    "#{T.must(repository).permalink(include_host: include_host)}/security/campaigns/#{T.must(security_campaign).number}"
  end

  sig { returns(T::Array[Authzd::Proto::Attribute]) }
  def authzd_attributes
    permissions_wrapper.serialized_subject_attributes
  end

  # The unique Message-ID header value for notifications and email.
  sig { returns(String) }
  def message_id
    "<#{T.must(repository).name_with_display_owner}/security/campaigns/#{T.must(security_campaign).number}@#{GitHub.urls.host_name}>"
  end
end
