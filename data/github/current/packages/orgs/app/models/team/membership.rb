# typed: true
# frozen_string_literal: true

class Team::Membership
  extend T::Sig
  # Represents a team that no longer exists, for when we need something that
  # quacks like a team

  REMOVE_USER_ABILITIES_BATCH_SIZE = 500
  class PseudoTeam
    attr_reader :id, :name, :organization

    def initialize(id, name, organization, legacy_owners: false)
      @id = id.to_i
      @name = name
      @organization = organization
      @legacy_owners = legacy_owners
    end

    def legacy_owners?
      !!@legacy_owners
    end

    def ability_delegate
      self
    end

    def ability_id
      id
    end

    def ability_type
      "Team"
    end

    def subject?
      true
    end

    def participates?
      true
    end
  end

  RemoveTeamMembershipError = Class.new(StandardError)

  attr_reader :team, :repo_ids, :organization, :member_ids

  def initialize(team, member_ids = [], repo_ids = [], send_notification: false, team_destroyed: false)
    @team = team
    @organization = team.organization
    @repo_ids = Array(repo_ids)
    @member_ids = Array(member_ids)
    @team_destroyed = team_destroyed
    @send_notification = send_notification
  end

  # Public: Revoke the membership ability between a team and a user, wrapped in
  # a transaction, optionally yielding to a provided block to execute code
  # inside the transaction.
  #
  # block     - Optional: run code inside the database transaction for each
  # member
  #
  # Returns nothing.
  def remove(queue_delete_jobs: true, caller_type: nil)
    User.where(id: member_ids).find_each(batch_size: 500) do |member|
      Ability.throttle(noop_on_foreground: true) do
        success = T.let(false, T::Boolean)
        begin
          Ability.transaction do
            Ability.revoke(member, team)
            yield member if block_given?
            success = true
          end
        ensure
          unless success
            # there was a transaction rollback
            Failbot.report!(RemoveTeamMembershipError.new("Failed to revoke membership to team #{team.id} for member #{member}"),
              app: "github-abilities",
              org_id: team.organization.id,
              team_id: team.id,
              user: member,
            )
          end
        end
      end

      if organization.present?
        # No need to queue this job if the owning organization has been deleted
        if queue_delete_jobs
          Team.queue_clear_team_memberships(repo_ids, organization.id, { user: member.id })
        end

        # Team removal notifications can't be sent without an organization
        send_removal_notification(member) unless caller_type == :enterprise_team
      end
    end

    if queue_delete_jobs
      Team.queue_fork_cleanup(repo_ids, member_ids)
    end
  end

  sig do params(
    users: T.any(ActiveRecord::Relation, T::Array[User]),
    queue_delete_jobs: T::Boolean,
    caller_type: T.nilable(Symbol)).void
  end
  def bulk_remove(users:, queue_delete_jobs: true, caller_type: nil)
    # For now this method is to be used for only optimization of Enterprise Team Organization sync
    return unless GitHub.esm_enabled?

    # Batch bulk deletion of abilities
    users.each_slice(REMOVE_USER_ABILITIES_BATCH_SIZE) do |batch|
      success = T.let(false, T::Boolean)
      begin
        Ability.throttle(noop_on_foreground: true) do
          abilities = Ability.where(
            actor_type: "User",
            actor_id: batch.pluck(:id),
            subject_type: "Team",
            subject_id: team.id,
          )
          Ability.revoke_abilities(abilities)
          success = true
        end
      ensure
        unless success
          # there was a transaction rollback
          Failbot.report!(
            RemoveTeamMembershipError.new("Failed to bulk revoke membership to team #{team.id} for members"),
            app: "github-abilities",
            org_id: team.organization.id,
            team_id: team.id,
          )
        end
      end

      if organization.present?
        batch.each do |member|
          # No need to queue this job if the owning organization has been deleted
          if queue_delete_jobs
            Team.queue_clear_team_memberships(repo_ids, organization.id, { user: member.id })
          end

          # Team removal notifications can't be sent without an organization
          send_removal_notification(member) unless caller_type == :enterprise_team
        end
      end
    end

    if queue_delete_jobs
      Team.queue_fork_cleanup(repo_ids, member_ids)
    end
  end

  private

  def has_repositories?
    repo_ids.any?
  end

  def send_notification?
    !!@send_notification
  end

  def team_destroyed?
    !!@team_destroyed
  end

  # Internal: send a team removal email notification to the current member.
  #
  # Returns nothing.
  def send_removal_notification(member)
    if has_repositories? && send_notification? && !member.suspended?
      TeamsMailer.removed_from_team(
        member,
        team.name,
        team.organization,
        legacy_owner: team.legacy_owners?,
        team_destroyed: team_destroyed?,
      ).deliver_later
    end
  end
end
