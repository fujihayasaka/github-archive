# typed: true
# frozen_string_literal: true

class UpdateMembersOrganizationOrchestration < OrganizationOrchestration
  step :update_abilities do
    data[:previous_actions] = {}
    users.each do |user|
      is_direct_member = T.must(organization).direct_member?(user, include_indirect_abilities: false)
      # indirect members only have :read permission
      data[:previous_actions][user.id] = if is_direct_member
        Authorization.service.most_capable_action_between(actor: user, subject: T.must(organization)).to_sym
      else
        :read
      end

      if action_changed?(user)
        with_write do
          T.must(organization).update_member_without_callbacks_and_notifications(
            user,
            action: data[:action].to_sym
          )
        end
      end
    end
  end

  # Ensure SCIM-managed enterprise orgs have an OME for every direct member.
  step :add_organization_membership_entry do
    org = T.must(organization)
    return unless org.scim_managed_enterprise?
    return unless FeatureFlag.vexi.enabled?(:scim_add_org_membership_entry_on_member_update, org.business, default: false)

    with_write do
      org.bulk_add_organization_membership_entry(
        user_ids: user_ids,
        team: nil,
        adder: actor,
      )
    end
  end

  job_start

  step :instrument do
    users.each do |user|
      next unless action_changed?(user)

      instrument_options = {
        user: user,
        permission: data[:action].to_sym,
        old_permission: data[:previous_actions][user.id]
      }
      instrument_options[:actor] = actor if actor.present?
      if GitHub.context[:hide_staff_user] && GitHub.guard_audit_log_staff_actor?
        instrument_options.merge!(GitHub.guarded_audit_log_staff_actor_entry(actor))
      end

      T.must(organization).instrument(:update_member, instrument_options)
    end

    GlobalInstrumenter.instrument("organization.update_members", {
      organization: organization,
      actor: actor,
      user_ids: users.map(&:id),
      permission: data[:action].to_sym
    })
  end

  step :cancel_team_membership_requests do
    return unless data[:action].to_sym == :admin

    users.each do |user|
      next unless action_changed?(user)

      CancelTeamMembershipRequestsJob.perform_later(T.must(organization).id, user.id)
    end
  end

  step :send_email_notifications do
    return unless data[:action].to_sym == :admin

    users.each do |user|
      next unless action_changed?(user)

      OrganizationMailer.admin_added(user, T.must(organization)).deliver_later
    end
  end

  step :cleanup_repository_notifications_and_forks do
    return if data[:action].to_sym == :admin

    users.each do |user|
      next unless action_changed?(user)

      # Clean up notifications and forks for repos that the user no longer has access to
      repository_ids = Array(T.must(organization).repositories.pluck(:id))
      CleanupListNotificationsJob.perform_later(user.id, "Repository", repository_ids)
      RemoveForksForInaccessibleRepositoriesJob.perform_later(repository_ids, Array(user.id))
    end
  end

  step :unlink_billing_contacts do
    return if data[:action].to_sym == :admin

    users.each do |user|
      next unless action_changed?(user)

      if T.must(organization).has_linked_billing_contact_to_actor?(actor: user)
        T.must(organization).unlink_billing_contact(actor: user)
      end
    end
  end

  step :revoke_programmatic_access_grants do
    users.each do |user|
      next unless action_changed?(user)

      T.must(organization).revoke_org_programmatic_access_grants_if_demoted_from_admin(
        user,
        data[:previous_actions][user.id]&.to_sym
      )
    end
  end

  step :enqueue_mailchimp_team_list_job do
    return unless MailchimpTeamListJob.enabled?

    users.each do |user|
      next unless action_changed?(user)

      if (data[:action].to_sym == :admin) || (data[:previous_actions][user.id]&.to_sym == :admin)
        # Enroll or unenroll team admin campaign when admin status changes
        MailchimpTeamListJob.perform_later(user: user, org: T.must(organization))
      end
    end
  end

  step :cancel_invitations do
    users.each do |user|
      T.must(organization).cancel_all_invitations_involving(user)
    end
  end

  private

  def action_changed?(user)
    return false if data[:previous_actions][user.id].nil?

    data[:action].to_sym != data[:previous_actions][user.id].to_sym
  end
end
