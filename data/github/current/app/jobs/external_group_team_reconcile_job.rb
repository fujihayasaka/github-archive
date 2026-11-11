# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class ExternalGroupTeamReconcileJob < ApplicationJob
  include BusinessesHelper
  include ExternalGroupsHelper

  queue_as :external_group_team_reconcile

  MAX_CONCURRENT_JOBS = 1
  RESTRAINT_LOCK_TTL = 5.minutes
  LOCK_KEY = "external-group-team-reconcile-job:"

  MAX_RETRY_ATTEMPTS = 3
  RETRY_DELAY = 5.minutes
  ENQUEUE_INTERVAL = 30

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  retry_on GitHub::Restraint::UnableToLock, wait: RETRY_DELAY, attempts: MAX_RETRY_ATTEMPTS do |_job, error|
    GitHub.dogstats.increment("external_identities.external_group_team_reconcile_job.retry_exhausted", tags: ["exception_class:#{error.class.name}"])
    Failbot.report(error)
  end
  retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: MAX_RETRY_ATTEMPTS do |_job, error|
    GitHub.dogstats.increment("external_identities.external_group_team_reconcile_job.retry_exhausted", tags: ["exception_class:#{error.class.name}"])
    Failbot.report(error)
  end

  resolve_tenant_context do |args|
    external_group = ExternalGroup.find_by(id: args[:external_group_id])
    external_group&.provider&.business
  end

  # Public: Calculate the the membership differences between an external group
  # and a team and updates the team to match the external group.
  #
  # external_group_id - The ID of the external group that is linked to the team.
  # team_id - The ID of the team that links the team with the external_group.
  # caller - Determines where the job is triggered from. Used for logging purposes only where parameters are recorded.
  #
  # Returns nothing
  def perform(external_group_id:, team_id:, caller:)
    Failbot.push(external_group_id: external_group_id, team_id: team_id)

    unless external_group_id && team_id
      GitHub.dogstats.increment("external_identities.external_group_team_reconcile_job.no_external_group_id_team_id")
      return
    end

    external_group = ExternalGroup.find_by(id: external_group_id)
    unless external_group
      GitHub.dogstats.increment("external_identities.external_group_team_reconcile_job.no_external_group")
      return
    end

    business = external_group.provider&.business

    # Clear provisioning-specific audit context that may have been serialized
    # from the enqueuing request. When an IdP suspends multiple EMU users
    # concurrently, enqueue_once_per_interval coalesces reconciliation into a
    # single job run. The serialized linked_user_id / external_identity from
    # the enqueuing user's SCIM request would otherwise contaminate
    # team.remove_member audit events for every other user in the batch.
    if FeatureFlag.vexi.enabled?(:external_identities_clean_reconcile_audit_context, business, default: false)
      Audit.context.pop_key(:linked_user_id)
      Audit.context.pop_key(:external_identity)
      GitHub.context.pop_key(:linked_user_id)
      GitHub.context.pop_key(:external_identity)
    end

    GitHub.logger.info(
      "info.message" => "Starting external_group_team_reconcile job",
      "code.namespace" => self.class.name,
      "code.function" => "perform",
      "gh.external_group.id" => external_group_id,
      "gh.team.id" => team_id,
      "gh.business.id" => business&.id,
      "gh.business.slug" => business&.slug,
      "gh.caller" => caller
    )

    begin
      external_group_team = ExternalGroupTeam.find_by(external_group_id: external_group_id, team_id: team_id)
      unless external_group_team
        GitHub.dogstats.increment("external_identities.external_group_team_reconcile_job.no_external_group_team")
        return
      end

      unless external_group_team.team.present?
        GitHub.dogstats.increment("external_identities.external_group_team_reconcile_job.no_team")
        with_write do
          external_group_team.destroy
        end
        return
      end

      # When the org is soft-deleted, skip the add/remove reconcile so we don't
      # consume licenses for users in deleted orgs. Run cleanup for a
      # mark-group-deleted external group below before bailing out so we don't
      # leak external_identity_group_memberships during the soft-delete window.
      org_soft_deleted = FeatureFlag.vexi.enabled?(:external_identities_skip_reconcile_for_soft_deleted_orgs, business, default: false) &&
        T.must(external_group_team.team).organization&.soft_deleted?

      if org_soft_deleted
        GitHub.dogstats.increment("external_identities.external_group_team_reconcile_job.org_soft_deleted")
        GitHub.logger.info(
          "info.message" => "Skipping reconcile - organization is soft deleted",
          "code.namespace" => self.class.name,
          "code.function" => "perform",
          "gh.external_group.id" => external_group_id,
          "gh.team.id" => team_id,
          "gh.business.id" => business&.id,
        )

        if external_group.deleted_at?
          lock!(external_group_id, team_id) do
            cleanup_deleted_external_group(external_group, external_group_id, business)
          end
        end

        return
      end

      unless FeatureFlag.vexi.enabled?(:skip_reconcile_precheck_for_external_teams, business, default: false)
        if external_group_team.calculate_memberships_in_sync?
          GitHub.dogstats.increment(
            "external_identities.external_group_team_reconcile_job.memberships_already_in_sync",
            tags: ["sync_status:#{external_group_team.sync_status}"]
          )
          unless external_group_team.in_sync?
            # We already computed calculate_memberships_in_sync? above, so write in_sync directly
            # instead of calling update_sync_status, which recalculates memberships again.
            with_write do
              external_group_team.update_column(:sync_status, ExternalGroupTeam.sync_statuses["in_sync"])
            end
          end
          return
        end
      end

      lock!(external_group_id, team_id) do
        cleanup_deleted_external_group(external_group, external_group_id, business)

        external_group_team.reconcile_memberships(job: ExternalGroupTeamReconcileJob, job_args: [],
          job_kwargs: { external_group_id: external_group_id, team_id: team_id, caller: self.class.name })
      end

      business&.update_license_usage
    rescue StandardError => error
      GitHub.logger.error(
        "exception.message" => error.message,
        "exception.class" => error.class.name,
        "gh.backtrace" => error.backtrace&.join("\n"),
        "code.namespace" => self.class.name,
        "code.function" => "perform",
        "gh.external_group.id" => external_group_id,
        "gh.team.id" => team_id,
        "gh.business.id" => business&.id,
        "gh.business.slug" => business&.slug,
        "gh.caller" => caller
      )
      raise
    ensure
      GitHub.logger.info(
        "info.message" => "Finished external_group_team_reconcile job",
        "code.namespace" => self.class.name,
        "code.function" => "perform",
        "gh.external_group.id" => external_group_id,
        "gh.team.id" => team_id,
        "gh.business.id" => business&.id,
        "gh.business.slug" => business&.slug,
        "gh.caller" => caller
      )
    end
  end

  def self.enqueue_interval
    ENQUEUE_INTERVAL
  end

  def self.enqueue_external_group_team_once_per_interval(external_group_team, caller)
    args = { external_group_id: external_group_team.external_group_id, team_id: external_group_team.team_id, caller: caller }
    enqueue_once_per_interval(kwargs: args, interval: enqueue_interval, unique_id: external_group_team.id)
  end

  private

  def cleanup_deleted_external_group(external_group, external_group_id, business)
    return unless external_group.deleted_at?

    memberships = external_group.external_identity_group_memberships.pluck(:id, :external_identity_id)
    instrument_external_group_delete(memberships.map(&:second), external_group_id)
    delete_memberships(memberships.map(&:first))

    with_write do
      if external_group.external_identity_group_memberships.present?
        GitHub.dogstats.increment("external_identities.external_group_team_reconcile_job.group_membership_deletion_failed")
        GitHub.logger.error({
          "exception.message" => "Group membership deletion failed",
          "gh.business.id" => business&.id,
          "gh.external_group.id" => external_group_id,
        })
      end
    end
  end

  def delete_memberships(ids)
    with_write do
      ids.each_slice(1000) { |slice| ExternalIdentityGroupMembership.where(id: slice).delete_all }
    end
  end

  # Private: The restraint for locking and preventing simultaneous reconcile jobs
  # for the same external group team.
  #
  # Returns GitHub::Restraint
  def restraint
    @restraint ||= GitHub::Restraint.new
  end

  # Private: Use a GitHub::Restraint to prevent simultaneous updates
  def lock!(external_group_id, team_id)
    restraint_key = "#{LOCK_KEY}#{external_group_id}-#{team_id}"
    restraint.lock!(restraint_key, MAX_CONCURRENT_JOBS, RESTRAINT_LOCK_TTL) do
      yield
    end
  end
end
