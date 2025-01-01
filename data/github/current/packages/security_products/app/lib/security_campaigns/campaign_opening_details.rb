# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  class CampaignOpeningDetails < T::Struct
    prop :org, Organization
    prop :name, String
    prop :description, String
    prop :query_string, String
    prop :alerts, T::Hash[Integer, T::Array[Turboscan::Proto::Result]], default: {}
    prop :secret_scanning_alerts, T::Hash[Integer, T::Array[GitHub::TokenScanning::Service::Token]], default: {}
    prop :ends_at, Time
    prop :managers, T::Array[User]
    prop :team_managers, T::Array[Team]
    prop :contact_link, T.nilable(String)
    prop :generate_issues, T::Boolean, default: false
    prop :source_campaign_id, T.nilable(Integer)
    prop :created_by, T.nilable(User)
    prop :alert_type, String
  end
end
