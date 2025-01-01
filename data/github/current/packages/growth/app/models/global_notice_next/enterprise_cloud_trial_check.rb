# typed: true
# frozen_string_literal: true

class GlobalNoticeNext
  class EnterpriseCloudTrialCheck < BaseCheck
    def should_show_notice?
      organization_ids = viewer.organization_ids
      threshold_date = (Billing::EnterpriseCloudTrial.trial_length + Organizations::EnterpriseCloudOnboarding::SurveyBannerComponent::EXPIRED_DURATION_DAYS).ago.end_of_day
      Billing::EnterpriseCloudTrial.trial_exists_for?(organization_ids, created_after: threshold_date) || Business.joins(:organization_memberships).trial.where(organization_memberships: { organization_id: organization_ids }).exists?
    end
  end
end
