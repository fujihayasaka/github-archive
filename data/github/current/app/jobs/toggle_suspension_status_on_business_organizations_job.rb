# typed: true
# frozen_string_literal: true

# Toggle suspension status on all a Business' member Organizations.
class ToggleSuspensionStatusOnBusinessOrganizationsJob < ApplicationJob
  queue_as :user_suspend
  retry_on_dirty_exit

  # Perform the job.
  #
  # business - Business whose member Organizations should be suspended or unsuspended.
  # suspend - Boolean indicating whether to suspend or unsuspend.
  # reason - Reason to change the suspension status.
  # sdn_suspension - Boolean indicating whether to suspend the organizations for SDN reasons, or not.
  # actor - User who is performing the change of suspension status.
  # send_email - Boolean indicating whether to send emails to organization administrators about the suspension.
  # dsa_source - String indicating the source of the report that led to the suspension. For DSA compliance.
  def perform(business, suspend, reason, sdn_suspension, actor: nil, send_email: false, dsa_source: nil)
    return if GitHub.enterprise?
    return unless business

    # Preserve original reason before mutating in case it's needed for populating the EU DSA email notification
    tos_reason = reason

    # Add context to the reason for member orgs
    if reason.present?
      suspended_part = suspend ? "suspended" : "unsuspended"
      reason = "The owning #{business.slug} enterprise was #{suspended_part}: #{reason}"
    end

    actor = User.staff_user if actor.nil?
    business.organizations.each do |org|
      with_write do
        if suspend
          if sdn_suspension
            org.sdn_suspend(staff_user: actor, reason: reason)
          else
            org.suspend(reason, hard_flag: true, send_email: send_email, dsa_source: dsa_source, tos_reason_for_business_org: tos_reason)
          end
        else
          if sdn_suspension
            org.sdn_unsuspend(staff_user: actor, reason: reason)
          else
            org.unsuspend(reason)
          end
        end
      end
    end
  end
end
