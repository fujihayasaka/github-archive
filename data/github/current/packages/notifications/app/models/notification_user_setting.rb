# typed: true
# frozen_string_literal: true

# The model being Newsies::SettingsStore
class NotificationUserSetting < ApplicationRecord::Domain::Notifications
  self.ignored_columns += [:participating_web_push]

  include Coders::CodableColumn

  include ::Users::BelongsToUser
  belongs_to_user_via_domain

  serialize_with_coder :raw_data, Coders::NotificationUserSettingCoder

  def self.set_for_user(user, settings)
    serializable_hash = Newsies::SettingsSerializer.dump(settings)

    ActiveRecord::Base.connected_to(role: :writing) do
      attributes = {
        id: user.is_a?(User) ? user.id : user.to_i,
        raw_data: serializable_hash,
        notify_own_via_email: serializable_hash[:notify_own_via_email],
        participating_web: serializable_hash[:participating_web],
        participating_email: serializable_hash[:participating_email],
        subscribed_web: serializable_hash[:subscribed_web],
        subscribed_email: serializable_hash[:subscribed_email],
        notify_comment_email: serializable_hash[:notify_comment_email],
        notify_pull_request_review_email: serializable_hash[:notify_pull_request_review_email],
        notify_pull_request_push_email: serializable_hash[:notify_pull_request_push_email],
        vulnerability_cli: serializable_hash[:vulnerability_cli],
        vulnerability_web: serializable_hash[:vulnerability_web],
        vulnerability_email: serializable_hash[:vulnerability_email],
        continuous_integration_web: serializable_hash[:continuous_integration_web],
        continuous_integration_email: serializable_hash[:continuous_integration_email],
        continuous_integration_failures_only: serializable_hash[:continuous_integration_failures_only],
        org_deploy_key_email: serializable_hash[:org_deploy_key_email],
      }

      upsert(attributes)
    end
  end
end
