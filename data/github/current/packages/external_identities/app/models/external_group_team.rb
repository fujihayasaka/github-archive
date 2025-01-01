# typed: true
# frozen_string_literal: true

class ExternalGroupTeam < ApplicationRecord::Domain::Users
  AllowedJobTypes = T.type_alias do
    T.any(T.class_of(ExternalGroupTeamReconcileJob),
    T.class_of(ExternalGroupTeamUnlinkJob),
    T.class_of(ExternalGroupTeamLinkJob),
    T.class_of(ExternalGroupMemberReconcileJob),
    T.class_of(DestroyExternalProviderDependentsJob))
  end

  ALLOWED_JOB_TYPE_ARGS = {
    "ExternalGroupTeamLinkJob" => { required_args: [Integer], required_kwargs: { caller: String } },
    "ExternalGroupTeamUnlinkJob" => { required_args: [Integer, Integer], required_kwargs: { caller: String } },
    "ExternalGroupTeamReconcileJob" => { required_args: [], required_kwargs: { external_group_id: Integer, team_id: Integer, caller: String } },
    "ExternalGroupMemberReconcileJob" => { required_args: [], required_kwargs: { caller: String } },
    "DestroyExternalProviderDependentsJob" => { required_args: [], required_kwargs: { provider_id: Integer, provider_type: String, business_id: Integer, caller: String } },
  }.freeze
  BATCH_SIZE = 100
  QUERY_BATCH_SIZE = 1000
  MAX_RUN_TIME = 275 # in seconds
  WAIT_INTERVAL = 30.seconds # The job will start 15 seconds after the TTL for the lock on the first job which is 5 minutes
  ENQUEUE_INTERVAL = 30
  SYNC_STATUS_JOB_DELAY = 5.minutes

  belongs_to :external_group
  belongs_to :team
  validates_presence_of :external_group, :team

  validate :team_belongs_to_same_external_identity_provider
  validate :is_team_valid_for_linking, on: :create

  after_commit :queue_external_group_team_link_job, on: [:create, :update]

  before_destroy :queue_external_group_team_unlink_job

  has_one :organization, through: :team

  enum :sync_status, {
    in_sync: 1,
    out_of_sync_generic: 2,
    out_of_sync_insufficient_licenses: 3,
  }

  def link
    reconciled_members = ActiveRecord::Base.connected_to(role: :reading) { reconcile_team_memberships }

    reconciled_members.each do |user_id, action|
      user = ActiveRecord::Base.connected_to(role: :reading) { User.find_by(id: user_id) }

      case action
      when :add
        ExternalGroupTeam.add_member_to_team(team, user)
      when :delete
        ExternalGroupTeam.remove_member_from_team(team&.organization, team, user)
      end
    end

    external_group&.instrument_event(:link, team)
  end

  def unlink
    # Removing an external-group-team will remove all members from the team without deleting the team,
    # External group members will not be impacted by this operation.
    unless team.nil?
      remove_all_team_members
      external_group&.instrument_event(:unlink, team)
    end
  end

  # Public: Calculates the difference in membership between external group and team
  # and updates the team to match the external group.
  # Parameters:
  # - user: T.nilable(User) - The user to reconcile memberships for.
  # - user_ids: T::Array[Integer] - An array of user ids to reconcile memberships for.
  # - job: T.nilable(AllowedJobTypes) - An optional enum representing the allowed job types.
  # - job_args: T::Array[T.untyped] - An array containing the positional job arguments.
  # - job_kwargs: T::Hash[Symbol, T.untyped] - A hash containing the named job arguments.
  # - start_time: T.nilable(Time) - The time that the job started.
  # - synchronous_orchestration: T::Bolean - Perform orchestration synchronously, only used in test mode.
  # Returns:
  # - void - Returns nothing
  sig do
    params(
      user: T.nilable(User),
      user_ids: T::Array[Integer],
      job: T.nilable(AllowedJobTypes),
      job_args: T::Array[T.untyped],
      job_kwargs: T::Hash[Symbol, T.untyped],
      start_time: T.nilable(Time),
      synchronous_orchestration: T::Boolean,
    ).void.checked(:always).on_failure(:raise)
  end
  def reconcile_memberships(user: nil, user_ids: [], job: nil, job_args: [], job_kwargs: {}, start_time: nil, synchronous_orchestration: false)
    return unless external_group && team

    # did we run into licensing issues when adding members to a team?
    out_of_seats = T.let(false, T::Boolean)

    start_time ||= Time.now
    past_max_run_time = T.let(false, T::Boolean)
    to_add, to_remove = calculate_membership_changes(user: user, user_ids: user_ids)

    instrument_reconcile_memberships_event(log_options: {
      "info.message" => "Calculated membership changes",
      "gh.to_add" => to_add.size,
      "gh.to_remove" => to_remove.size,
      "gh.start_time" => start_time,
    })

    users_removed = 0
    users_added = 0

    return if (to_add + to_remove).empty?

    users_removed, past_max_run_time = process_remove_members(to_remove, start_time, job: job, job_args: job_args, job_kwargs: job_kwargs)

    unless past_max_run_time
      users_added, past_max_run_time, out_of_seats = process_add_members(to_add, start_time, job: job, job_args: job_args, job_kwargs: job_kwargs, synchronous_orchestration:)
    end

    unless past_max_run_time
      enqueue_sync_status_job(out_of_seats)
    end

    if past_max_run_time && (to_remove.count != users_removed || to_add.count != users_added)
      instrument_reconcile_memberships_event(log_options: {
        "info.message" => "Partially finished reconciling memberships, starting new job to proceed with remaining membership changes",
        "gh.business.id" => team&.organization&.business,
        "gh.external_group_team.to_add" => to_add.count,
        "gh.external_group_team.to_remove" => to_remove.count,
        "gh.external_group_team.users_added" => users_added,
        "gh.external_group_team.users_removed" => users_removed,
        "gh.start_time" => start_time,
        "gh.end_time" => Time.now,
        })
    elsif to_add.size != users_added || to_remove.size != users_removed
      GitHub.dogstats.increment("#{job&.name}.reconcile_memberships_failed")
      instrument_reconcile_memberships_event(info: false, log_options: {
        "exception.message" => "Error reconciling memberships",
        "gh.business.id" => team&.organization&.business,
        "gh.external_group_team.to_add" => to_add.count,
        "gh.external_group_team.to_remove" => to_remove.count,
        "gh.external_group_team.users_added" => users_added,
        "gh.external_group_team.users_removed" => users_removed,
        "gh.start_time" => start_time,
        "gh.end_time" => Time.now,
        })
    else
      instrument_reconcile_memberships_event(log_options: {
        "info.message" => "Finished reconciling memberships",
        "gh.business.id" => team&.organization&.business,
        "gh.external_group_team.users_added" => users_added,
        "gh.external_group_team.users_removed" => users_removed,
        "gh.start_time" => start_time,
        "gh.end_time" => Time.now,
        })
    end
  rescue ActiveRecord::RecordNotFound => e
    # We see ActiveRecord::RecordNotFound when there's a race condition on the team and the team is already destroyed.
    # In these cases log the error and run DestroyDependantsOperation to clean up any data
    # that we wrote in prior to the error being thrown.
    if e.model == "Team"
      instrument_reconcile_memberships_event(info: false,  log_options: {
        "exception.message" => e.message,
        "gh.backtrace" => e.backtrace&.join("\n"),
        })

      team_info = Team::Destruction::DestroyOperation.team_info_for_dependants_destruction([team])

      ActiveRecord::Base.connected_to(role: :writing) do
        Team::Destruction::DestroyDependantsOperation.new(team&.organization_id, team_info).execute(with_instrumentation: false)
      end
    else
      enqueue_sync_status_job(out_of_seats)

      raise e
    end
  end

  # Public: Calculates the difference in membership between external group and team
  # and returns the list of users to add and remove
  #
  # Returns two arrays of user ids
  def calculate_membership_changes(user: nil, user_ids: [])
    if user_ids&.any?
      external_group_member_user_ids = external_group&.active_user_ids & user_ids
      team_member_user_ids = team&.member_ids & user_ids

      to_remove = team_member_user_ids - external_group_member_user_ids
      to_add = external_group_member_user_ids - team_member_user_ids
    elsif user
      team_member = team&.member?(user)
      should_be_team_member = external_group&.active_user?(user.id)

      # When should_be_team_member is true, only include the user in to_add if they are not already a member of the team.
      # If they are already a member of the team then we don't need to try to add them again.
      # If should_be_team_member is false, then we should try to remove the user from the team only if they're already a team member.
      to_add = should_be_team_member && !team_member ? [user.id] : []
      to_remove = !should_be_team_member && team_member ? [user.id] : []
    else
      external_group_member_user_ids = external_group&.active_user_ids
      team_member_user_ids = team&.member_ids

      to_remove = team_member_user_ids - external_group_member_user_ids
      to_add = external_group_member_user_ids - team_member_user_ids
    end

    [to_add, to_remove]
  end

  def add_member(user)
    return unless user
    ExternalGroupTeam.add_member_to_team(team, user)
  end

  def remove_member(user)
    return unless user
    ExternalGroupTeam.remove_member_from_team(organization, team, user)
  end

  def remove_all_team_members
    ExternalGroupTeam.remove_all_team_members_from_team(team)
  end

  def member?(identity_id)
    external_group&.member?(identity_id)
  end

  def self.add_member_to_team(team, user)
    return unless team
    # Do not add member twice (return here since adding will throw an exception)
    return if team.member_ids.include?(user.id)
    if GitHub.flipper[:do_not_check_license_for_org_members].enabled?(team.organization.business)
      team.add_member(user, force_emu: true, skip_organization_seat_checks: true)
    else
      team.add_member(user, force_emu: true)
    end
  end

  def self.remove_member_from_team(organization, team, user)
    return unless team
    team.remove_member(user, force: true)
  end

  sig do
    params(
      team: T.nilable(Team),
      job: T.nilable(AllowedJobTypes),
      job_args: T::Array[T.untyped],
      job_kwargs: T::Hash[Symbol, T.untyped],
      start_time: T.nilable(Time),
    ).returns(T::Boolean).checked(:always).on_failure(:raise)
  end
  def self.remove_members_from_team(team, job: nil, job_args: [], job_kwargs: {}, start_time: nil)
    return false unless team

    start_time ||= Time.now
    past_max_run_time = T.let(false, T::Boolean)

    to_remove = team.member_ids
    users_removed, past_max_run_time = process_remove_all_members(team, to_remove, start_time, job: job, job_args: job_args, job_kwargs: job_kwargs)

    if past_max_run_time && to_remove.count != users_removed
      options = {
        "info.message" => "Partially finished reconciling memberships, starting new job to proceed with remaining membership changes",
        "gh.business.id" => team.organization&.business&.id,
        "gh.external_group_team.to_remove" => to_remove.count,
        "gh.external_group_team.users_removed" => users_removed,
        "gh.start_time" => start_time,
        "gh.end_time" => Time.now,
        "code.namespace" => self.class.name,
        "code.function" => "remove_members_from_team",
        "gh.team.name" => team.name,
        "gh.team.id" => team.id,
      }

      GitHub.logger.info(options)
    end

    past_max_run_time
  end

  def self.remove_all_team_members_from_team(team)
    return unless team
    team.members.each { |user| remove_member_from_team(team.organization, team, user) }
  end

  def queue_external_group_team_link_job
    ExternalGroupTeamLinkJob.perform_later(id, caller: self.class.name)

    external_group&.instrument_event(:link, team)
  end

  def queue_external_group_team_unlink_job
    ExternalGroupTeamUnlinkJob.perform_later(team&.id, external_group&.id, caller: self.class.name)
  end

  # Public: Reconcile team memberships with external group memberships
  #
  # Returns Hash of user ids with delete or add action {1 => :add, 2 => :delete}
  def reconcile_team_memberships
    reconciled_members = team&.members.pluck(:id).to_h { |id| [id, :delete] }

    external_group&.external_identity_group_memberships&.in_batches do |memberships|
      memberships.each do |membership|
        identity = membership.external_identity

        if reconciled_members.has_key?(identity.user_id)
          reconciled_members.delete(identity.user_id) if identity.disabled_at.nil?
        else
          reconciled_members[identity.user_id] = :add if identity.disabled_at.nil?
        end
      end
    end

    reconciled_members
  end

  # Public: Get the difference between the External Group and Team memberships.
  #
  # Returns a hash containing the user ids of the group and team member mismatches.
  def calculate_group_team_mismatches
    group_member_user_ids = if external_group.nil? || external_group&.deleted_at?
      GitHub.logger.warn(
        "info.message" => "External group team belongs to external group that no longer exists.",
        "code.namespace" => self.class.name,
        "code.function" => "calculate_group_team_mismatches",
        "gh.external_group_team.id" => id,
        "gh.external_group_team.team_id" => team_id,
        "gh.external_group_team.external_group_id" => external_group_id,
      )

      []
    else
      external_group&.active_user_ids
    end

    team_member_user_ids = if team.nil?
      GitHub.logger.warn(
        "info.message" => "External group team belongs to team that no longer exists.",
        "code.namespace" => self.class.name,
        "code.function" => "calculate_group_team_mismatches",
        "gh.external_group_team.id" => id,
        "gh.external_group_team.external_group_id" => external_group_id,
        "gh.external_group_team.team_id" => team_id,
      )

      []
    else
      team&.member_ids
    end

    {
      group_member_ids_not_in_team: group_member_user_ids - team_member_user_ids,
      team_member_ids_not_in_group: team_member_user_ids - group_member_user_ids,
    }
  end

  # Public: Compare External Group and Team memberships to determine whether or not they match.
  #
  # Returns a boolean indicating whether or not the memberships are in sync.
  def calculate_memberships_in_sync?
    calculate_group_team_mismatches.values.all?(&:empty?)
  end

  # Public: Calculate the sync status of the External Group Team and set it accordingly on the record.
  #
  # out_of_seats - A boolean indicating whether an out of seats error was encountered when adding members to the team.
  def update_sync_status(out_of_seats: false)
    reconciled_sync_status = reconcile_sync_status(out_of_seats)

    # If the sync status hasn't changed, we don't need to update the record
    return if reconciled_sync_status == sync_status

    ActiveRecord::Base.connected_to(role: :writing) do
      # use update_column to avoid triggering the update callback
      update_column(:sync_status, reconciled_sync_status)
    end
  end

  # Private: Processes all of the members that need to be removed from the team.
  # Parameters:
  # - to_remove: T::Array[Integer] - An array of user ids to remove memberships for.
  # - start_time: Time - The time that the job started.
  # - job: T.nilable(AllowedJobTypes) - An optional enum representing the allowed job types.
  # - job_args: T::Array[T.untyped] - An array containing the positional job arguments.
  # - job_kwargs: T::Hash[Symbol, T.untyped] - A hash containing the named job arguments.
  # Returns:
  # - T::Array[T.untyped] - number of user removed, and past max run time flag
  sig do
    params(
      team: Team,
      to_remove: T::Array[Integer],
      start_time: Time,
      job: T.nilable(AllowedJobTypes),
      job_args: T::Array[T.untyped],
      job_kwargs: T::Hash[Symbol, T.untyped]
    ).returns(T::Array[T.untyped]).checked(:always).on_failure(:raise)
  end
  private_class_method def self.process_remove_all_members(team, to_remove, start_time, job: nil, job_args: [], job_kwargs: {})
    return [0, false] if to_remove.empty?

    past_max_run_time = T.let(false, T::Boolean)
    users_removed = 0

    to_remove.each_slice(QUERY_BATCH_SIZE) do |user_ids|
      user_hash = User.where(id: user_ids).index_by(&:id)
      next if user_hash.empty?

      ActiveRecord::Base.connected_to(role: :writing) do
        start_new_job(team, job, job_args, job_kwargs) if job && (past_max_run_time = past_max_run_time?(start_time))

        unless past_max_run_time
          users = T.let(user_hash.map { |user_id, user| user_ids.include?(user_id) ? user : nil }.compact, T::Array[User])
          user_status = team.bulk_remove_members(users:, force: true)

          removed_values = user_status.values.select { |v| v == Team::REMOVED }
          users_removed += removed_values.count
        end
      end

      break if past_max_run_time
    end

    [users_removed, past_max_run_time]
  end

  # Description: Starts a new job of the given type with the provided arguments.
  # Parameters:
  # - job: T.nilable(AllowedJobTypes) - An optional enum representing the allowed job types.
  # - job_args: T::Array[T.untyped] - An array containing the positional job arguments.
  # - job_kwargs: T::Hash[Symbol, T.untyped] - A hash containing the named job arguments.
  # Returns:
  # - T::Boolean - True if the job was started successfully, false otherwise.
  sig do
    params(
      team: Team,
      job: T.nilable(AllowedJobTypes),
      job_args: T::Array[T.untyped],
      job_kwargs: T::Hash[Symbol, T.untyped]
    ).returns(T::Boolean).checked(:always).on_failure(:raise)
  end
  private_class_method def self.start_new_job(team, job, job_args, job_kwargs)
    return false unless job

    # Check if job_args and job_kwargs are compatible with the job's required arguments
    unless ExternalGroupTeam.check_required_args_present?(job, job_args, job_kwargs)
      raise ArgumentError, "Job args are incompatible with #{job.name}'s required args."
    end

    options = {
      "info.message" => "Starting new job #{job.name} to proceed with membership changes",
      "gh.business.id" => team.organization&.business&.id,
      "code.namespace" => self.class.name,
      "code.function" => "reconcile_memberships",
      "gh.external_group.id" => job_args[1],
      "gh.team.name" => team.name,
      "gh.team.id" => team.id,
    }

    GitHub.logger.info(options)

    job.set(wait: WAIT_INTERVAL).perform_later(*job_args, **job_kwargs)

    # the job was started successfully
    true
  end

  # Checks if the required number of arguments is present for a given job type.
  # Parameters:
  # - job: AllowedJobTypes - An enum representing the allowed job types.
  # - job_args: T::Array[T.untyped] - An array containing the job arguments.
  # - job_kwargs: T::Hash[Symbol, T.untyped]) - A hash containing the job keyword arguments.
  # Returns:
  # - T::Boolean - True if the required arguments are present, false otherwise.
  sig { params(job: AllowedJobTypes, job_args: T::Array[T.untyped], job_kwargs: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
  def self.check_required_args_present?(job, job_args, job_kwargs)
    required_args = ExternalGroupTeam::ALLOWED_JOB_TYPE_ARGS[job.name][:required_args]
    required_kwargs = ExternalGroupTeam::ALLOWED_JOB_TYPE_ARGS[job.name][:required_kwargs]

    # Checks if required_args and required_kwargs are empty for the job
    # If they are, we can return true since no args are required
    return true if required_args.empty? && required_kwargs.empty?

    # Checks if the provided job_args matches the required_args
    args_match = job_args.length == required_args.length && job_args.each_with_index.all? { |arg, i| arg.is_a?(required_args[i]) }

    # Checks if the provided job_kwargs matches the required_kwargs
    kwargs_match = required_kwargs.all? do |k, v|
      job_kwargs.key?(k) && job_kwargs[k].is_a?(v)
    end

    # Return true if both args and kwargs match, otherwise false
    args_match && kwargs_match
  end

  sig { params(start_time: Time).returns(T::Boolean) }
  def self.past_max_run_time?(start_time)
    Time.now.to_i - start_time.to_i >= MAX_RUN_TIME
  end

  private

  # Private: Processes all of the members that need to be removed from the team.
  # Parameters:
  # - to_remove: T::Array[Integer] - An array of user ids to remove memberships for.
  # - start_time: Time - The time that the job started.
  # - job: T.nilable(AllowedJobTypes) - An optional enum representing the allowed job types.
  # - job_args: T::Array[T.untyped] - An array containing the positional job arguments.
  # - job_kwargs: T::Hash[Symbol, T.untyped] - A hash containing the named job arguments.
  # Returns:
  # - T::Array[T.untyped] - number of user removed, and past max run time flag
  sig do
    params(
      to_remove: T::Array[Integer],
      start_time: Time,
      job: T.nilable(AllowedJobTypes),
      job_args: T::Array[T.untyped],
      job_kwargs: T::Hash[Symbol, T.untyped]
    ).returns(T::Array[T.untyped]).checked(:always).on_failure(:raise)
  end
  def process_remove_members(to_remove, start_time, job: nil, job_args: [], job_kwargs: {})
    return [0, false] if to_remove.empty?

    past_max_run_time = T.let(false, T::Boolean)
    users_removed = 0

    to_remove.each_slice(QUERY_BATCH_SIZE) do |user_ids|
      user_hash = User.where(id: user_ids).index_by(&:id)
      next if user_hash.empty?

      ActiveRecord::Base.connected_to(role: :writing) do
        if external_group&.provider&.business&.feature_enabled?(:bulk_remove_emu_team_members) || GitHub.enterprise?
          users = T.let(user_hash.map { |user_id, user| user_ids.include?(user_id) ? user : nil }.compact, T::Array[User])
          team&.bulk_remove_members(users:, force: true)

          start_new_job(job, job_args, job_kwargs) if job && (past_max_run_time = ExternalGroupTeam.past_max_run_time?(start_time))
        else
          user_ids.each do |user_id|
            user = user_hash[user_id]
            removed_user = remove_member(user)
            users_removed += removed_user == user ? 1 : 0

            break if job && (past_max_run_time = ExternalGroupTeam.past_max_run_time?(start_time))
          end

          start_new_job(job, job_args, job_kwargs) if past_max_run_time
        end
      end

      break if past_max_run_time
    end

    [users_removed, past_max_run_time]
  end

  # Private: Processes all of the members that need to be added to the team.
  # Parameters:
  # - to_add: T::Array[Integer] - An array of user ids to remove memberships for.
  # - start_time: Time - The time that the job started.
  # - job: T.nilable(AllowedJobTypes) - An optional enum representing the allowed job types.
  # - job_args: T::Array[T.untyped] - An array containing the positional job arguments.
  # - job_kwargs: T::Hash[Symbol, T.untyped] - A hash containing the named job arguments.
  # Returns:
  # - T::Array[T.untyped] - number of user added, and past max run time flag
  sig do
    params(
      to_add: T::Array[Integer],
      start_time: Time,
      job: T.nilable(AllowedJobTypes),
      job_args: T::Array[T.untyped],
      job_kwargs: T::Hash[Symbol, T.untyped],
      synchronous_orchestration: T::Boolean
    ).returns(T::Array[T.untyped]).checked(:always).on_failure(:raise)
  end
  def process_add_members(to_add, start_time, job: nil, job_args: [], job_kwargs: {}, synchronous_orchestration: false)
    out_of_seats = T.let(false, T::Boolean)

    return [0, false, false] if to_add.empty?

    past_max_run_time = T.let(false, T::Boolean)
    users_added = 0

    to_add.each_slice(QUERY_BATCH_SIZE) do |to_add_user_ids|
      user_hash = User.where(id: to_add_user_ids).index_by(&:id)
      next if user_hash.empty?

      ActiveRecord::Base.connected_to(role: :writing) do
        to_add_user_ids.each_slice(BATCH_SIZE) do |user_ids|
          # Check that the team still exists via a reload before trying to add members.
          # If it doesn't reload it will raise an ActiveRecord::RecordNotFound error which will be rescued below.
          team&.reload

          users = user_ids.map { |user_id| user_hash[user_id] }

          if GitHub.flipper[:do_not_check_license_for_org_members].enabled?(team&.organization&.business)
            result = team&.bulk_add_members_with_failover(users, force_emu: true, skip_organization_seat_checks: true, synchronous_orchestration:)
            users_added += result.map { |r| r.success? }.size
          else
            result = team&.bulk_add_members_with_failover(users, force_emu: true, synchronous_orchestration:)
            out_of_seats = result.any? { |r| r == Team::AddMemberStatus::NO_SEAT }
            users_added += result.map { |r| r.success? }.size
          end

          result.each_with_index { |status, i|  instrument_reconcile_memberships_add_user_event(status: status, user_id: user_ids[i]) }

          # break out of the loop if the job has been running for more than MAX_RUN_TIME seconds
          break if job && (past_max_run_time = ExternalGroupTeam.past_max_run_time?(start_time))
        end

        start_new_job(job, job_args, job_kwargs) if past_max_run_time
      end

      break if past_max_run_time
    end

    [users_added, past_max_run_time, out_of_seats]
  end

  def team_belongs_to_same_external_identity_provider
    return unless team && external_group

    provider = if team&.business_team?
      T.cast(team, BusinessTeam).business&.external_provider
    else
      organization&.business&.external_provider
    end

    errors.add :team_id, "must belong to the same identity provider as external group" if provider != external_group&.provider
  end

  def is_team_valid_for_linking
    return unless team

    errors.add :team_id, "cannot have any members" if team&.members.any?
  end

  # Description: Starts a new job of the given type with the provided arguments.
  # Parameters:
  # - job: T.nilable(AllowedJobTypes) - An optional enum representing the allowed job types.
  # - job_args: T::Array[T.untyped] - An array containing the positional job arguments.
  # - job_kwargs: T::Hash[Symbol, T.untyped] - A hash containing the named job arguments.
  # Returns:
  # - T::Boolean - True if the job was started successfully, false otherwise.
  sig do
    params(
      job: T.nilable(AllowedJobTypes),
      job_args: T::Array[T.untyped],
      job_kwargs: T::Hash[Symbol, T.untyped]
    ).returns(T::Boolean).checked(:always).on_failure(:raise)
  end
  def start_new_job(job, job_args, job_kwargs)
    return false unless job

    # Check if job_args and job_kwargs are compatible with the job's required arguments
    unless ExternalGroupTeam.check_required_args_present?(job, job_args, job_kwargs)
      raise ArgumentError, "Job args are incompatible with #{job.name}'s required args."
    end

    instrument_reconcile_memberships_event(log_options: {
      "info.message" => "Starting new job #{job.name} to proceed with membership changes",
      "gh.job_args" => job_args,
    })

    if job == DestroyExternalProviderDependentsJob
      job.enqueue_once_per_interval(kwargs: job_kwargs, interval: ENQUEUE_INTERVAL, unique_id: job_kwargs[:business_id])
    else
      job.set(wait: WAIT_INTERVAL).perform_later(*job_args, **job_kwargs)
    end

    # the job was started successfully
    true
  end

  def instrument_reconcile_memberships_event(info: true, log_options: {})
    options = {
      "code.namespace" => self.class.name,
      "code.function" => "reconcile_memberships",
      "gh.external_group_team.id" => id,
      "gh.external_group.name" => external_group&.display_name,
      "gh.external_group.id" => external_group&.id,
      "gh.team.name" => team&.name,
      "gh.team.id" => team&.id,
    }.merge(log_options)

    if info
      GitHub.logger.info(options)
    else
      GitHub.logger.error(options)
    end
  end

  def instrument_reconcile_memberships_add_user_event(status:, user_id:)
    options = if status&.success?
      { "info.message" => "adding user to team succeeded" }
    else
      { "exception.message" => "failed to add user to team" }
    end

    options = options.merge({
      "gh.add_member_status" => status&.status,
      "gh.user.id" => user_id,
    })

    instrument_reconcile_memberships_event(info: status&.success?, log_options: options)
  end

  # Private: Queue a job to update the sync status of this External Group Team record.
  #
  # Returns a boolean indicating whether or not the job was queued successfully.
  def enqueue_sync_status_job(out_of_seats)
    ExternalGroupTeamSyncStatusUpdateJob.enqueue_once_per_interval(
      args: [id, out_of_seats],
      interval: SYNC_STATUS_JOB_DELAY,
      unique_id: id,
    )
  end

  # Private: Determine which sync status to assign to this External Group Team record.
  #
  # out_of_seats - A boolean indicating whether an out of seats error was encountered when adding members to the team.
  #
  # Returns an ExternalGroupTeam.sync_status enum value.
  def reconcile_sync_status(out_of_seats)
    # No mismatches between group and team memberships always means that we are in sync
    return ExternalGroupTeam.sync_statuses["in_sync"] if calculate_memberships_in_sync?

    # If we encountered a license issue when reconciling, and we know that we aren't in sync (and we know that we
    # aren't by now), we should preserve the licensing issue sync status that we found previously when adding members
    # to the team.
    return ExternalGroupTeam.sync_statuses["out_of_sync_insufficient_licenses"] if out_of_seats

    # We reserve the generic status for the generic case where we know that we are out of sync, but we don't know why.
    ExternalGroupTeam.sync_statuses["out_of_sync_generic"]
  end
end
