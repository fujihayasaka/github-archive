# typed: true
# frozen_string_literal: true

class ExternalGroupMemberReconcileJob < ApplicationJob
  include BusinessesHelper
  include ExternalGroupsHelper

  queue_as :external_group_member_reconcile

  MAX_CONCURRENT_JOBS_IDENTITY = 8
  MAX_CONCURRENT_JOBS_IDENTITY_EXTERNAL_GROUP = 1
  MAX_CONCURRENT_JOBS_EXTERNAL_GROUP = 1
  RESTRAINT_LOCK_TTL = 5.minutes
  LOCK_KEY = "external-group-member-reconcile-job"

  MAX_RETRY_ATTEMPTS = 3
  RETRY_DELAY = 5.minutes

  SQL_BATCH_SIZE = 100

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  retry_on GitHub::Restraint::UnableToLock, wait: RETRY_DELAY, attempts: MAX_RETRY_ATTEMPTS do |_job, error|
    GitHub.dogstats.increment(
      "external_identities.external_group_member_reconcile_job",
      tags: ["error:unable_to_lock"]
    )
    Failbot.report(error)
  end

  resolve_tenant_context do |args|
    # This job can be triggered with either `external_identity` or `external_group`, but not both.
    # Therefore, we need to handle both `external_identity` and `external_group` separately.
    external_identity = ExternalIdentity.find_by(id: args[:external_identity_id])
    external_group = ExternalGroup.find_by(id: args[:external_group_id])

    provider = external_identity&.provider || external_group&.provider
    provider&.business
  end

  # Public: Add or remove team memberships for an external identity based on their external group memberships and their role.
  # Also call DSR delete_user method if the external_identity is deleted as part of GDPR compliance.
  #
  # external_identity_id - An external identity id associated with a user being reconciled
  # external_group_id    - An external group id associated with a group being reconciled
  #
  # Returns nothing
  def perform(external_identity_id: nil, external_group_id: nil, caller:, operation: nil)
    Failbot.push(external_identity_id: external_identity_id, external_group_id: external_group_id)
    return if external_identity_id.nil? && external_group_id.nil?

    cache_business = nil
    external_group = nil
    user = nil

    if external_identity_id
      return unless identity = ExternalIdentity.find_by(id: external_identity_id)
      return unless user = identity.user
      return unless user.enterprise_managed_business || GitHub.single_business_environment?
      cache_business = user.enterprise_managed_business
    end

    # Call DSR delete_user method if the external_identity is deleted
    if identity&.deleted_at
      # If the call to DSR fails, we log the error and continue with the job
      begin
        Dsr.delete_user(user)
      rescue StandardError => e
        GitHub.logger.error(
          "error.message" => "Call to DSR.delete_user failed",
          "error.exception" => e,
          "gh.user.id" => user&.id,
          "gh.user.login" => user&.display_login,
          "gh.external_identity.id" => external_identity_id,
        )
      end
    end

    if external_group_id
      return unless external_group = ExternalGroup.find_by(id: external_group_id)
      return unless external_group.provider.business.enterprise_managed_user_enabled? || GitHub.single_business_environment?

      if external_identity_id.nil?
        return unless external_group.deleted_at?
      end

      cache_business ||= external_group.provider.business
    end

    return if cache_business&.feature_enabled?(:disable_external_group_member_reconcile_job)

    if operation && user && external_group
      external_group.instrument_event(operation, nil, user: user)
    end

    GitHub.logger.info(
      "info.message" => "Starting external_group_member_reconcile_job",
      "code.namespace" => self.class.name,
      "code.function" => "perform",
      "gh.external_group.id" => external_group_id,
      "gh.external_identity.id" => external_identity_id,
      "gh.business.id" => cache_business&.id,
      "gh.caller" => caller,
      "gh.business.slug" => cache_business&.slug,
    )

    external_group_teams = if external_group_id
      ExternalGroupTeam.where(external_group_id: external_group_id)
    else
      ExternalGroupTeam.joins(external_group: [:external_identity_group_memberships])
        .where(external_group: {
            external_identity_group_memberships: { external_identity_id: external_identity_id }
          })
    end

    lock!(external_identity_id: external_identity_id, external_group_id: external_group_id) do
      if external_identity_id
        reconcile_memberships_job(external_group_teams) if external_group_teams.any?
        if identity.deleted_at?
          memberships = identity.external_identity_group_memberships.pluck(:id, :external_group_id)
          instrument_external_identity_delete(memberships.map(&:second), external_identity_id)
          delete_memberships(memberships.map(&:first))
        end
      elsif external_group_id
        if enterprise_teams_enabled?(cache_business)
          instrument_enterprise_team_membership_update(external_group_ids: [external_group_id])
        end

        memberships = external_group.external_identity_group_memberships.pluck(:id, :external_identity_id)
        instrument_external_group_delete(memberships.map(&:second), external_group_id) unless operation
        delete_memberships(memberships.map(&:first))

        reconcile_memberships_job(external_group_teams) if external_group_teams.any?
      end
    end

    GitHub.logger.info(
      "info.message" => "Finished external_group_member_reconcile_job",
      "code.namespace" => self.class.name,
      "code.function" => "perform",
      "gh.external_group.id" => external_group_id,
      "gh.external_identity.id" => external_identity_id,
      "gh.business.id" => cache_business&.id,
      "gh.caller" => caller.to_s,
      "gh.business.slug" => cache_business&.slug,
    )
  end

  private

  def reconcile_memberships_job(external_group_teams)
    external_group_teams.each do |external_group_team|
      ExternalGroupTeamReconcileJob.enqueue_external_group_team_once_per_interval(external_group_team, self.class.name)
    end
  end

  def reconcile_memberships(external_group_teams, user: nil)
    external_group_teams.each { |external_group_team| external_group_team.reconcile_memberships(user: user) }
  end

  def delete_memberships(ids)
    with_write do
      ids.each_slice(SQL_BATCH_SIZE) { |slice| ExternalIdentityGroupMembership.where(id: slice).delete_all }
    end
  end

  def instrument_enterprise_team_membership_update(external_group_ids:)
    external_group_ids.each_slice(SQL_BATCH_SIZE) do |slice|
      ExternalGroup.where(id: slice).includes(:enterprise_teams).each do |external_group|
        external_group.enterprise_teams.each do |team|
          team.instrument_update
        end
      end
    end
  end

  # Private: The restraint for locking and preventing simultaneous reconcile jobs
  # for the same user.
  #
  # Returns GitHub::Restraint
  def restraint
    @restraint ||= GitHub::Restraint.new
  end

  # Private: Use a GitHub::Restraint to prevent simultaneous updates
  def lock!(external_identity_id: nil, external_group_id: nil)
    if external_group_id && external_identity_id
      restraint_key = "#{LOCK_KEY}:#{external_group_id}-#{external_identity_id}"
      max_current_jobs = MAX_CONCURRENT_JOBS_IDENTITY_EXTERNAL_GROUP
    elsif external_identity_id
      restraint_key = "#{LOCK_KEY}-identity:#{external_identity_id}"
      max_current_jobs = MAX_CONCURRENT_JOBS_IDENTITY
    else
      restraint_key = "#{LOCK_KEY}-group:#{external_group_id}"
      max_current_jobs = MAX_CONCURRENT_JOBS_EXTERNAL_GROUP
    end

    restraint.lock!(restraint_key, max_current_jobs, RESTRAINT_LOCK_TTL) do
      yield
    end
  end
end
