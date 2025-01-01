# typed: true
# frozen_string_literal: true

class RepositorySecurityCenterStatus < ApplicationRecord::Notify
  extend GitHub::SimplePagination

  belongs_to :repository
  belongs_to :owner,
    class_name: "User"

  belongs_to :repository_security_center_config,
    foreign_key: :repository_id,
    primary_key: :repository_id,
    inverse_of: :repository_security_center_statuses

  enum :feature_type, {
    secret_scanning: "secret_scanning",
    secret_scanning_push_protection: "secret_scanning_push_protection",
    code_scanning: "code_scanning",
    code_scanning_pr_reviews: "code_scanning_pr_reviews",
    code_scanning_auto_codeql: "code_scanning_auto_codeql",
    dependabot_alerts: "dependabot_alerts",
    dependabot_security_updates: "dependabot_security_updates",
    dependabot_version_updates: "dependabot_version_updates"
  }, scopes: false

  enum :scanning_status, {
    not_enrolled: "not_enrolled",
    enrolled: "enrolled",
    failed: "failed",
    eligible: "eligible",
    not_eligible: "not_eligible",
  }, scopes: false

  def self.use_index(index)
    from("#{self.table_name} USE INDEX(#{index})")
  end

  def self.all_feature_types
    RepositorySecurityCenterStatus.feature_types.keys
  end

  def self.primary_feature_types
    [
      :dependabot_alerts,
      :code_scanning,
      :secret_scanning
    ]
  end

  sig { params(primary_feature: T.any(Symbol, String)).returns(T::Array[Symbol]) }
  def self.subfeatures_for(primary_feature)
    case primary_feature.to_sym
    when :dependabot_alerts
      [
        :dependabot_security_updates,
        :dependabot_version_updates
      ]
    when :code_scanning
      [
        :code_scanning_pr_reviews,
        :code_scanning_auto_codeql
      ]
    when :secret_scanning
      [
        :secret_scanning_push_protection
      ]
    else
      []
    end
  end

  def self.primary_feature_for(feature_type)
    primary_feature_types.each do |primary_feature|
      return primary_feature if feature_type.to_sym == primary_feature
      return primary_feature if subfeatures_for(primary_feature).include?(feature_type.to_sym)
    end
  end

  sig { params(feature: Symbol).returns(String) }
  def self.feature_display_name_for(feature)
    feature =
      case feature
      when :dependabot_alerts
        :dependabot
      when :code_scanning_auto_codeql
        :default_setup
      else
        feature
      end

    feature.to_s.humanize
  end

  sig { params(feature: Symbol).returns(String) }
  def self.coverage_display_name_for(feature)
    case feature.to_sym
    when :dependabot_alerts then "Alerts"
    when :dependabot_security_updates then "Security updates"
    when :dependabot_version_updates then "Version updates"
    when :code_scanning then "Alerts"
    when :code_scanning_pr_reviews then "Pull request alerts"
    when :code_scanning_auto_codeql then "Default setup"
    when :secret_scanning then "Alerts"
    when :secret_scanning_push_protection then "Push protection"
    when :secret_scanning_partners then "Alerts to partners"
    else feature.to_s.humanize
    end
  end
end
