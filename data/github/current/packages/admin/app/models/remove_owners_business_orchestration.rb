# typed: true
# frozen_string_literal: true

class RemoveOwnersBusinessOrchestration < BusinessOrchestration
  step :cancel_invitations do
    users.each do |user|
      T.must(business).cancel_all_invitations_involving(user)
    end
  end

  step :revoke_abilities do
    users.each do |user|
      T.must(business).revoke_ability(user)
    end
  end

  job_start

  step :cleanup_removed_users do
    # Do not remove business user accounts if the users are enterprise managed
    unless T.must(business).enterprise_managed?
      T.must(business).cleanup_removed_users(user_ids)
    end
  end

  step :update_license_usage do
    T.must(business).update_license_usage
  end

  step :instrument do
    users.each do |user|
      T.must(business).instrument(:remove_admin, user: user, actor: actor, reason: data[:reason])
      GlobalInstrumenter.instrument("enterprise_account.remove_admin", {
        enterprise: T.must(business),
        actor: actor,
        user: user,
        role: :owner,
        reason: data[:reason],
        new_role: data[:new_role],
      })
    end
  end

  step :sync_global_business_owner_and_site_admin do
    users.each do |user|
      T.must(business).sync_global_business_owner_and_site_admin(user, false)
    end
  end

  step :send_email_notifications do
    if data[:send_notification]
      users.each do |user|
        T.must(business).send_admin_removed_email_notification(
          role: :owner,
          admin: user,
          reason: data[:reason]&.to_s
        )
      end
    end
  end
end
