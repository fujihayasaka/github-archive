# typed: false
# frozen_string_literal: true

# Orchestrates the pre-destroy callback behavior when deleting a user from
# the database. This controls the order of the destroy steps as well as error
# handling. Wrapping them up in one place lets us better control
# failure conditions. This object must be used as shared instance across the
# callback chain
#
# Warning:
# All destroy callbacks (in before_destroy) will be run inside a transaction.
# Long running transactions should be avoided at all costs
#
# Examples
#
#   # rails callbacks involved in destroying users should use an instance variable

# Always reuse the same destroy user callback because we have state that
# is shared across the callback chain. This is bad, but can't be avoided without
# serious refactoring.
#
#   before_destroy :destroy_user_callbacks_before_destroy
#   after_commit   :destroy_user_callbacks_after_commit, :on => :destroy
#
#   def destroy_user_callbacks
#     @destroy_callback ||= DestroyUserCallbacks.new
#   end
#
#   def destroy_user_callbacks_before_destroy
#     destroy_user_callbacks.before_destroy(self)
#   end
#
#   def destroy_user_callbacks_after_commit
#     destroy_user_callbacks.after_commit(self)
#   end
#
class DestroyUserCallbacks
  include FeatureFlagHelper

  BATCH_SIZE = 1000
  MAX_THROTTLE_RETRIES = 5

  # Optionally can be called ahead of destroy/destroy! to run any callbacks
  # that are idempotent enough to run outside the destroy/destroy! transaction.
  # Callbacks added here should be sure to memoize themselves in order to prevent
  # them from running more than once.
  #
  # user - The User that's about to be deleted from the database.
  #
  # Returns true
  def before_transaction(user)
    # See Repository::RemovalDependency#remove
    delete_repositories(user)
    # This is a long-running idempotent operation, and therefore it's advantageous to run it before the main destroy transaction
    remove_assignments(user)
    # See item 2 of https://github.com/github/github/issues/37241#issuecomment-237975472
    delete_public_org_members_joins(user)
  end

  # Run the pre-destroy cleanup steps for the user. Because this is registered
  # as a before_destroy callback, if it returns false or throws an exception,
  # the user record will not be destroyed.
  #
  # user - The User that's about to be deleted from the database.
  #
  # Returns false to stop the destroy callback chain.
  def before_destroy(user)
    GitHub.dogstats.increment("user", tags: ["action:destroy_attempted"])
    if user.created_at
      GitHub.dogstats.gauge "user.age", (Time.current - user.created_at).to_i, tags: ["action:destroy"]
    end
    begin
      delete_spam_content(user)
      delete_repositories(user)
      delete_repository_transfers(user)
      hide_gists(user)
      delete_user_status(user)
      delete_business_organization_membership(user)
      delete_notification_subscriptions(user)
      remove_ignore_list(user)
      remove_followers(user)
      remove_followings(user)
      mark_login_as_used(user)
      remove_from_mailchimp(user)
      remove_assignments(user)
      delete_business_support_entitlements(user)
      delete_public_org_members_joins(user)
      prepare_collab_removed_events(user)
      prepare_org_memberships_removal(user)
      prepare_demilestoned_events(user)
      prepare_project_events(user)
      prepare_webhook_events(user)
      retire_namespaces(user)
      uninstall_integration_installations(user)
      instrument_billable_product_removal(user)
      notify_succession_agreement_terminations(user)
      delete_verified_domains(user)
      delete_two_factor_credentials(user)
      reset_user_notices(user)

      # explicitly find the account admins before the transaction is committed
      # and store as an instance variable to be used in after_commit
      @account_admins = find_account_admins(user)
    rescue Exception => ex # rubocop:todo Lint/GenericRescue
      GitHub.dogstats.increment("user", tags: ["action:destroy_failed"])
      GitHub.logger.error({
        exception: ex,
        "code.namespace": "DestroyUserCallbacks",
        "code.function": "before_destroy",
        "gh.user.id": user.id,
      })

      if ex.cause
        GitHub.logger.error("exception cause", {
          exception: ex.cause,
          "code.namespace": "DestroyUserCallbacks",
          "code.function": "before_destroy",
          "gh.user.id": user.id,
        })
      end
      raise
    end
  end

  def after_commit(user)
    # If email sending fails it will cause a db
    # rollback, send emails before queueing to
    # ensure we don't enqueue the deletion of
    # failed deletion attempts.
    send_destroy_confirmation(user, @account_admins)
    @account_admins = nil
    GitHub.dogstats.increment("user", tags: ["action:destroy"])
  end

  private

  def notify_succession_agreement_terminations(user)
    user.received_successor_invitations.accepted.each do |invite|
      invite.send_successor_removed_email
    end
  end

  def remove_assignments(user)
    @remove_assignments ||= begin
      user.clear_issue_assignments # domain-isolation-query-violation:ignore:packages/issues (SELECT, UPDATE)
      true
    end
  end

  def find_account_admins(user)
    user.admins.select { |admin| !admin.suspended? }
  end

  def remove_from_mailchimp(user)
    return unless GitHub.mailchimp_enabled?
    user.emails.each do |email|
      MailchimpDeleteJob.perform_later(email.email, user.id)
    end
  end

  def delete_spam_content(user)
    return if !user.spammy?
    # Temporarily send notifications to SpamNotifications room when spammy users
    # delete their accounts.
    GitHub::SpamChecker.notify("SPAM: Flagged account #{user.login} (#{user.id}) being destroyed; last_ip is #{user.last_ip}. https://admin.github.com/stafftools/audit_log?query=webevents+%7C+where+user_id+%3D%3D+#{user.id}+or+org_id+%3D%3D+#{user.id}")
  end

  def send_destroy_confirmation(user, admins)
    # Don't send the email in certain cases
    return unless user.receives_confirmation_when_destroyed?

    # Only send email for Users, not Organizations. Email is sent for Organizations on soft-deletion instead.
    if user.user?
      options = AccountMailer::Serializers.delete_user(user, admins)
      AccountMailer.delete_user(options).deliver_later
      options = AccountMailer::Serializers.delete_private(user)
      AccountMailer.delete_private(options).deliver_later
    else
      raise ArgumentError.new("Can't send destroy confirmation email to User with ID #{user.id}")
    end
  end

  def delete_repositories(user)
    @delete_repositories ||= begin
      deleter = user.deleted_by ? User.find_by_login(user.deleted_by) : user
      user.repositories.each do |repo|
        repo.remove(deleter, prevent_concurrency: true)
      end
      true
    end
  end

  def delete_verified_domains(user)
    Pages::DeleteProtectedDomainsJob.perform_later(owner_id: user.id) unless GitHub.enterprise?
  end

  # Prepare 'deleted' notifications for UserEvent.
  # OrganizationEvent is not handled here. It is handled via a subscription to the
  # org.delete event that is instrumented when an Organization is soft-deleted.
  def prepare_webhook_events(user)
    return if Rails.env.test? && !Hook.delivers_in_test?
    actor_id = self_destruction?(user) ? user.id : actor.id
    # Only handles Users, not Organizations. Organizations are handled when they are soft-deleted.
    if user.user?
      return unless GitHub.user_hooks_enabled?

      user.construct_future_event do
        Hook::Event::UserEvent.new(
          action: :deleted,
          triggered_at: Time.now,
          actor_id: actor_id,
          user_id: user.id,
        )
      end
    end
  end

  def prepare_demilestoned_events(user)
    return if Rails.env.test? && !Hook.delivers_in_test?

    actor_id = self_destruction?(user) ? user.id : actor.id
    user.repositories.each do |repo|
      repo.milestones.each do |milestone|

        milestone.open_issues.each do |issue| # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          user.construct_future_event do
            Hook::Event::IssuesEvent.new(
              action: :demilestoned,
              user_id: user.id,
              repo_id: repo.id,
              actor_id: actor_id,
              issue_id: issue.id,
              triggered_at: Time.now,
            )
          end
        end

        user.construct_future_event do
          Hook::Event::MilestoneEvent.new(
            action: :deleted,
            milestone_id: milestone.id,
            actor_id: actor_id,
            triggered_at: Time.now,
          )
        end
      end
    end
  end

  def prepare_project_events(user)
    return if Rails.env.test? && !Hook.delivers_in_test?
    return if GitHub.enterprise?
    return if GitHub.flipper[:projects_classic_webhooks_deprecation].enabled?

    actor_id = self_destruction?(user) ? user.id : actor.id
    user.repositories.each do |repo|
      repo.projects.each do |project|
        user.construct_future_event do
          Hook::Event::ProjectEvent.new(
            action: :deleted,
            project_id: project.id,
            actor_id: actor_id,
            triggered_at: Time.now,
          )
        end
        project.columns.each do |project_column|
          user.construct_future_event do
            Hook::Event::ProjectColumnEvent.new(
              action: :deleted,
              project_column_id: project_column.id,
              actor_id: actor_id,
              triggered_at: Time.now,
            )
          end
        end
        project.cards.each do |project_card|
          user.construct_future_event do
            Hook::Event::ProjectCardEvent.new(
              action: :deleted,
              project_card_id: project_card.id,
              actor_id: actor_id,
              triggered_at: Time.now,
            )
          end
        end
      end
    end
  end

  def delete_two_factor_credentials(user)
    user.two_factor_requirement_metadata&.destroy
    user.two_factor_credential&.destroy
  end

  def reset_user_notices(user)
    UserNotice.all.each do |notice|
      user.reset_notice(notice.name)
    end
  end

  def delete_repository_transfers(user)
    RepositoryTransfer.clear_target(user)
  end

  def hide_gists(user)
    user.gists.each(&:hide)
  end

  def remove_followers(user)
    user.followers.each { |f| f.unfollow(user) }

    Profiles::Kv.store.del("user.followers_count.#{user.id}")
  end

  def remove_followings(user)
    user.following.each { |f| user.unfollow(f) }

    Profiles::Kv.store.del("user.following_count.#{user.id}")
  end

  def mark_login_as_used(user)
    user.mark_login_as_used
  end

  def delete_user_status(user)
    UserStatus.where(user: user).delete_all

    if user.organization?
      UserStatus.where(organization: user).delete_all
    end
  end

  def delete_business_organization_membership(user)
    return unless user.organization?
    return if user.business.blank?
    user.business.organizations.delete(user)
  end

  def delete_notification_subscriptions(user)
    Notifications::Subscriptions.async_delete_user_subscriptions(user.id)
  end

  def remove_ignore_list(user)
    user.remove_ignore_list
  end

  def delete_business_support_entitlements(user)
    Business::SupportEntitlee.new(user).abilities.map(&:destroy)
  end

  def delete_public_org_members_joins(user)
    @delete_public_org_members_joins ||= begin
      loop do
        deleted_count = Organization.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
          affected_rows = Organization.connection.delete(Arel.sql(<<-SQL, id: user.id, batch_size: Arel.sql(BATCH_SIZE.to_s)))
            DELETE FROM public_org_members
            WHERE user_id = :id
            LIMIT :batch_size
          SQL

          affected_rows
        end

        break if deleted_count < BATCH_SIZE
      end
      true
    end
  end

  def prepare_collab_removed_events(user)
    return if Rails.env.test? && !Hook.delivers_in_test?

    user.associated_repository_ids(including: :direct).each do |repo_id|
      user.construct_future_event do
        Hook::Event::MemberEvent.new(
          action: :removed,
          user_id: user.id,
          repo_id: repo_id,
          actor_id: actor.try(:id),
          triggered_at: Time.now,
        )
      end
    end
  end

  def prepare_org_memberships_removal(user)
    user.organizations.each do |organization|
      organization.remove_member_with_instrumentation(user, actor: actor, reason: Organization::RemovedMemberNotification::USER_ACCOUNT_DELETED)
    end
  end

  def retire_namespaces(user)
    retired_namespaces = user.retired_namespaces.pluck(:name)
    repos = user.repositories.reject { |repo| retired_namespaces.include?(repo.name.downcase) }
    repos = repos.select { |repo| RetiredNamespace.should_retire?(repo) }
    repos.each { |repo| RetiredNamespace.create_from_repository!(repo) }
  end

  def uninstall_integration_installations(user)
    IntegrationInstallation.lock_target_for_deletion(user)

    IntegrationInstallation.where(target: user).each do |installation|
      installation.uninstall(actor: actor)
    end
  end

  def instrument_billable_product_removal(user)
    GlobalInstrumenter.instrument(
      "billing.plan_change",
      actor_id: actor&.id,
      user_id: user&.id,
      old_plan_name: user&.plan&.name,
      old_seat_count: user&.seats,
    )

    GlobalInstrumenter.instrument(
      "billing.lfs_change",
      actor_id: actor&.id,
      user_id: user&.id,
      old_lfs_count: user&.data_packs,
      new_lfs_count: 0,
    )

    # Marketplace and Sponsorship billable products are handled in
    # SubscriptionItem#instrument_billable_product_removal
  end

  # The user who performed the action as set in the GitHub request context. If
  # the context doesn't contain an actor, fallback to the ghost user.
  def actor
    @actor ||= (User.find_by_id(GitHub.context[:actor_id]) || User.ghost)
  end

  def self_destruction?(user)
    GitHub.context[:actor_id] == user.id
  end
end
