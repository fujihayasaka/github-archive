# typed: true
# frozen_string_literal: true

class SecurityCenterAlertSeverity < ApplicationRecord::Notify
  extend GitHub::SimplePagination

  belongs_to :repository

  belongs_to :repository_security_center_config,
    foreign_key: :repository_id,
    primary_key: :repository_id,
    inverse_of: :repository_security_center_statuses

  enum :feature_type, {
    secret_scanning: "secret_scanning",
    code_scanning: "code_scanning",
    dependabot_alerts: "dependabot_alerts"
  }, scopes: false
end
