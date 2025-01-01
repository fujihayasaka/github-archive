# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  class CampaignOpeningDetails < T::Struct
    prop :org, Organization
    prop :name, String
    prop :description, String
    prop :query_string, String
    prop :alerts, T::Hash[Integer, T::Array[Turboscan::Proto::Result]]
    prop :ends_at, Time
    prop :managers, T::Array[User]
    prop :team_managers, T::Array[Team]
    prop :contact_link, T.nilable(String)
    prop :generate_autofix_pull_requests, T::Boolean, default: false
    prop :generate_issues, T::Boolean, default: false
    prop :source_campaign_id, T.nilable(Integer)
    prop :created_by, T.nilable(User)
  end
end
