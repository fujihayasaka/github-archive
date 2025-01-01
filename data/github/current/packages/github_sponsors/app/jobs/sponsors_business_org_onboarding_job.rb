# typed: true
# frozen_string_literal: true

class SponsorsBusinessOrgOnboardingJob < ApplicationJob
  queue_as :sponsors_business_onboarding

  retry_on_dirty_exit

  attr_reader :organization
  delegate :business, to: :organization, allow_nil: true

  sig { params(organization: T.nilable(Organization), actor: T.nilable(User)).void }
  def perform(organization:, actor:)
    @organization = organization

    return unless GitHub.sponsors_enabled?
    return unless organization.present?
    return unless actor.present?
    return unless business.present?

    return if business_is_trial_account?

    return unless feature_enabled?
    return unless self_serve_business?

    with_write do
      organization.grant_sponsorships_access(actor: actor)
    end
  end

  private

  def self_serve_business?
    business.self_serve_payment?
  end

  def feature_enabled?
    business.feature_enabled?(:sponsors_self_serve_enterprise)
  end

  def business_is_trial_account?
    business.trial?
  end
end
