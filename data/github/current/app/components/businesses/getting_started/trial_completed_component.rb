# typed: true
# frozen_string_literal: true

class Businesses::GettingStarted::TrialCompletedComponent < ApplicationComponent
  attr_reader :business, :user_session

  def initialize(business:, user_session:)
    @business = business
    @user_session = user_session
  end

  sig { returns(T::Boolean) }
  def render?
    return false if GitHub.single_business_environment?
    return false unless business.present?
    return false unless current_user.present?
    return false unless user_session.present?
    return false unless business.owner?(current_user)
    return false unless business.trial?
    true
  end

  # Returns the count of Copilot suggestions accepted by members
  sig { returns(Integer) }
  def copilot_suggestions_count
    suggestion_count = 0

    business.organizations.each do |org|
      org_metrics = ::Copilot::UsageMetric.for_organization(org)
                                         .last_28_days

      if org_metrics.present?
        suggestion_count += org_metrics.sum(:acceptances_count).to_i
      end
    end

    suggestion_count
  end

  # Returns the count of secrets found by GitHub Advanced Security
  sig { returns(Integer) }
  def secrets_found_count
    alert_service = SecretScanning::AlertQueryService.for_business(
      business: business,
      organizations: business.organizations,
      current_user: current_user,
      user_session: user_session
    )

    _, open_alert_count, closed_alert_count, _, request_error = alert_service.get_alerts(per_page: 1)

    if request_error
      GitHub.logger.error("Error fetching secret scanning alerts for business #{business.id}: #{request_error}")
      return 0
    end

    open_alert_count + closed_alert_count
  end

  def header_text
    business.trial_expired? ? "Your GitHub Enterprise trial has expired." : "You have completed all your getting started tasks!"
  end

  def icon_color
    business.trial_expired? ? "purple" : "green"
  end

  def org_icon_color
    business.trial_expired? ? "done" : "open"
  end

  def activation_description
    if business.trial_expired?
      "Reclaim full access to all Enterprise features."
    else
      "Seamlessly transition from your trial to full access, with no interruptions to your use of all Enterprise features."
    end
  end
end
