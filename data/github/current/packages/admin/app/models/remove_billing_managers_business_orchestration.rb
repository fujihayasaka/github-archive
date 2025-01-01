# typed: true
# frozen_string_literal: true

class RemoveBillingManagersBusinessOrchestration < BusinessOrchestration

  step :cancel_invitations do
    users.each do |user|
      T.must(business).cancel_all_invitations_involving(user)
    end
  end

  step :revoke_abilities do
    users.each do |user|
      T.must(business).billing.revoke_ability(user)
    end
  end

  job_start

  step :cleanup_removed_users do
    # Do not remove business user accounts if the users are enterprise managed
    unless T.must(business).enterprise_managed?
      T.must(business).cleanup_removed_users(user_ids)
    end
  end

  step :instrument do
    users.each do |user|
      T.must(business).instrument(
        :remove_billing_manager,
        user: user,
        actor: actor,
        reason: data[:reason]
      )
      GlobalInstrumenter.instrument("enterprise_account.remove_admin", {
        enterprise: business,
        actor: actor,
        user: user,
        role: :billing_manager,
        reason: data[:reason],
        new_role: data[:new_role],
      })
      GitHub.dogstats.increment("billing.managers.count", tags: ["action:remove"])
    end
  end

  step :send_email_notifications do
    if data[:send_email_notification]
      users.each do |user|
        T.must(business).send_admin_removed_email_notification(
          role: Business::BILLING_MANAGER_ROLE,
          admin: user,
          reason: data[:reason]&.to_s
        )
      end
    end
  end
end
