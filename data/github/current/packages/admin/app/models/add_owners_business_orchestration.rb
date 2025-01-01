# typed: true
# frozen_string_literal: true

class AddOwnersBusinessOrchestration < BusinessOrchestration
  step :grant_abilities do
    users.each do |user|
      T.must(business).grant_owner_ability(user)
    end
  end

  job_start

  step :add_user_accounts do
    unless GitHub.single_business_environment?
      T.must(business).add_user_accounts(user_ids)
      BusinessUserAccount.add_business_role_to_accounts(
        :owner,
        T.must(business).user_accounts.where(user_id: user_ids)
      )
    end
  end

  step :update_license_usage do
    T.must(business).update_license_usage
  end

  step :instrument do
    users.each do |user|
      payload = { user: user }
      if data[:staff_action]
        payload.update(GitHub.guarded_audit_log_staff_actor_entry(actor))
      else
        payload.update(actor: actor)
      end

      T.must(business).instrument(:add_admin, payload)
    end
  end

  step :sync_global_business_owner_and_site_admin do
    users.each do |user|
      T.must(business).sync_global_business_owner_and_site_admin(user, true)
    end
  end

  step :send_email_notifications do
    users.each do |user|
      if data[:send_email_notification]
        T.must(business).send_admin_added_email_notification(role: :owner, admin: user)
      end

      # Only send the welcome email if the user is the only owner of the business and it's not a trial account.
      if T.must(business).owner_ids == [user.id] && !T.must(business).trial?
        T.must(business).send_welcome_net_new_enterprise_account_email
      end

      if T.must(business).send_initial_premium_support_mailer?(admin: user)
        BusinessMailer.premium_support_notice(business).deliver_later
      end
    end
  end
end
