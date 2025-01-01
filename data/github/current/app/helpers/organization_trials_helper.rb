# typed: strict
# frozen_string_literal: true

module OrganizationTrialsHelper
  include ActionView::Helpers::TextHelper
  include FeatureFlagHelper
  include OrganizationsHelper

  sig { params(organization: Organization, trial: Billing::EnterpriseCloudTrial, current_user: T.nilable(User)).returns(T::Boolean) }
  def should_show_enterprise_label?(organization, trial, current_user)
    return false if GitHub.enterprise?
    return false unless trial.active?

    organization.adminable_by?(current_user)
  end

  sig { params(trial_label: String, upcase: T::Boolean).returns(String) }
  def try_enterprise_trial_message(trial_label = "GitHub Enterprise Cloud free", upcase: true)
    days_suffix = pluralize(Billing::EnterpriseCloudTrial.trial_length.in_days.to_i, "day")
    message = "try #{trial_label} for #{days_suffix}"

    upcase ? message.upcase_first : message
  end

  sig { returns(String) }
  def trial_length_label
    trial_length = Billing::EnterpriseCloudTrial.trial_length.in_days.to_i
    "#{trial_length}-day"
  end

  sig { params(current_user: T.nilable(User)).returns(T::Array[Organization]) }
  def eligible_orgs_for_ghec_trial(current_user)
    return [] unless current_user.present?

    @eligible_orgs_for_ghec_trial ||= T.let(
      Billing::EnterpriseCloudTrial.eligible_orgs_only(current_user.owned_or_billing_manager_organizations),
      T.nilable(T::Array[Organization])
    )
  end
end
