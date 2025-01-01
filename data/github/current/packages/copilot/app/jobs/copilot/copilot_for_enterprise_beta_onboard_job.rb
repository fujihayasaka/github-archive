# typed: strict
# frozen_string_literal: true

module Copilot
  class CopilotForEnterpriseBetaOnboardJob < ApplicationJob
    extend T::Sig

    # Don't run more than one of this job at a time with the same args
    locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC

    queue_as :mailers
    retry_on_dirty_exit

    sig { params(membership: EarlyAccessMembership).void }
    def perform(membership)
      return unless membership.can_onboard?
      copilot_business = Copilot::Business.new(membership.member)

      # We plan to manually set some group of non-admin signups to can_onboard: true
      # In that case, we'll force-disable the setting before enabling the feature
      is_admin_signup = membership.member.adminable_by?(membership.actor)

      with_write do
        if !is_admin_signup
          copilot_business.copilot_for_dotcom_disabled!(send_email: false)
        end

        membership.feature_enabled = true
        membership.save!
      end
      CopilotForEnterpriseBetaMembershipMailer.waitlist_acceptance(membership).deliver_later
    end
  end
end
