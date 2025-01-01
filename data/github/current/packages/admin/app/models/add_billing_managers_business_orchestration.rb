# typed: true
# frozen_string_literal: true

class AddBillingManagersBusinessOrchestration < BusinessOrchestration
  step :grant_abilities do
    users.each do |user|
      T.must(business).billing.grant_manager_ability(user)
    end
  end

  job_start

  step :instrument do
    users.each do |user|
      payload = { user: user }
      if data[:staff_action]
        payload.update(GitHub.guarded_audit_log_staff_actor_entry(actor))
      else
        payload.update(actor: actor)
      end
      T.must(business).instrument(:add_billing_manager, payload)

      GitHub.dogstats.increment("billing.managers.count", tags: ["action:add"])
    end
  end

  step :add_user_accounts do
    return if GitHub.single_business_environment?

    users.each do |user|
      T.must(business).add_user_accounts([user.id])
      BusinessUserAccount.add_business_role_to_accounts(
        :billing_manager,
        T.must(business).user_accounts.where(user_id: user.id)
      )
    end
  end

  step :send_email_notifications do
    return unless data[:send_email_notification]

    users.each do |user|
      T.must(business).send_admin_added_email_notification(role: Business::BILLING_MANAGER_ROLE, admin: user)
    end
  end
end
