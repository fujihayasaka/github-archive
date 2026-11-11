# typed: true
# frozen_string_literal: true

class OrganizationSponsorshipAccessRevokedJob < ApplicationJob
  queue_as :sponsors_business_onboarding

  retry_on_dirty_exit

  locked_by timeout: 5.minutes, key: ->(job) {
    # we only want to run one job per organization at a time, regardless of which actor initiated the job
    job.arguments[0][:organization]
  }

  sig { params(organization: Organization, actor: User).void }
  def perform(organization:, actor:)
    return unless GitHub.sponsors_enabled?
    return unless organization.present?
    return unless actor.present?

    sponsorships_to_cancel = organization.sponsorships_as_sponsor.active
    return unless sponsorships_to_cancel.present?

    sponsorships_to_cancel.each do |sponsorship|
      Sponsorship.throttle_writes_with_retry do
        Billing::SubscriptionItem.throttle_writes_with_retry do
          sponsorship.cancel(actor: actor, reason: :BUSINESS_REVOKED_ORG_SPONSOR_ACCESS, force: true)
        end
      end
    end
  end
end
