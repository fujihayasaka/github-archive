# typed: strict
# frozen_string_literal: true

class SecurityCampaigns::SecurityCampaignUser < ApplicationRecord::Domain::SecurityCampaigns
  include ::Permissions::Attributes::Wrapper
  self.permissions_wrapper_class = ::Permissions::Attributes::SecurityCampaigns::SecurityCampaignUser

  belongs_to :security_campaign, optional: false
  belongs_to :user, optional: false

  sig { params(include_host: T::Boolean).returns(String) }
  def permalink(include_host: true)
    path = "/orgs/#{T.must(T.must(security_campaign).organization).to_param}/security/campaigns/#{T.must(security_campaign).number}"
    if include_host
      "#{GitHub.url}#{path}"
    else
      path
    end
  end

  sig { returns(T::Array[Authzd::Proto::Attribute]) }
  def authzd_attributes
    permissions_wrapper.serialized_subject_attributes
  end

  # The unique Message-ID header value for notifications and email.
  sig { returns(String) }
  def message_id
    "<#{T.must(T.must(security_campaign).organization).name_with_display_owner}/security/campaigns/#{T.must(security_campaign).number}@#{GitHub.urls.host_name}>"
  end
end
