# typed: strict
# frozen_string_literal: true

class Profiles::Organization::ScanSecretLeaksBannerComponent < ApplicationComponent
  include ApplicationComponent::Rescuable
  include InProductTargeting::ScanSecretLeaksConcern

  rescue_from StandardError, with: :nothing

  sig { returns(::Organization) }
  attr_reader :organization

  sig { returns(T.nilable(User)) }
  attr_reader :user

  sig { params(organization: Organization, user: T.nilable(User)).void }
  def initialize(organization:, user:)
    @organization = organization
    @user = user
  end

  sig { returns(T::Boolean) }
  def render?
    return false unless @user.present?
    return false unless show_scan_secret_leaks_promo?(@user, @organization)

    return false unless can_access_secret_risk_assessments?(@user, @organization)

    assessment, error = ::SecretScanning::Services::SecretRiskAssessmentsService.get_latest_assessment_for_org(@organization, @user)
    return false if !error && assessment

    variant = get_scan_secret_leaks_variant(@user)

    variant == 1
  end

  private

  sig { returns(String) }
  def scan_now_path
    security_center_assessments_path(organization)
  end

  sig { returns(String) }
  def dismiss_path
    growth_notice_dismissals_path(notice: "free_health_assessment_nudge", organization_id: organization.id)
  end

  sig { returns(String) }
  def remind_me_later_path
    # TODO: we plan to implement this feature if the data justifies enough engagement, but
    # for now we'll just use the same dismiss path, and the analytics event to differentiate
    # between Dismiss and RemindLater is handled onClick
    growth_notice_dismissals_path(notice: "free_health_assessment_nudge", organization_id: organization.id)
  end
end
