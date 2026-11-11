# typed: true
# frozen_string_literal: true

# The model being Newsies::SettingsStore
# rubocop:todo GitHub/DatabaseModelsShouldHaveTests
class NotificationUserSetting < ApplicationRecord::Domain::Notifications
  # rubocop:enable GitHub/DatabaseModelsShouldHaveTests
  include Coders::CodableColumn

  # rubocop:todo GitHub/IgnoredColumns
  self.ignored_columns = [:auto_subscribe, :auto_subscribe_teams] if !Rails.env.production? || rand(100) < GitHub.environment["IGNORE_COLUMN_AUTO_SUBSCRIBE_USER_SETTING_PERCENTAGE"].to_i # rubocop:disable GitHub/DoNotBranchOnRailsEnv
  # rubocop:enable GitHub/IgnoredColumns

  belongs_to :user

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
