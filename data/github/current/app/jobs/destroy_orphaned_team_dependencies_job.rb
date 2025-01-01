# typed: strict
# frozen_string_literal: true

# This job cleans up `Team` dependent rows that were orphaned, as a result of a team being destroyed with subsequent cleanup jobs failing
# https://github.com/github/Identity-Teams/issues/510
class DestroyOrphanedTeamDependenciesJob < ApplicationJob

  queue_as :destroy_orphaned_team_dependencies
  schedule interval: 24.hours, condition: -> { false }
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  sig { void }
  def perform
    GitHub.logger.info("DestroyOrphanedTeamDependenciesJob started")

    cleanup_team_group_mapping
    cleanup_user_role
    cleanup_team_invitation
    cleanup_child_team_change_parent_request
    cleanup_parent_team_change_parent_request
    cleanup_team_membership_request
    cleanup_ldap_mapping
    cleanup_discussion_post

    GitHub.logger.info("DestroyOrphanedTeamDependenciesJob finished")
  end

  private

  sig { params(source_name: String, records_to_destroy: ActiveRecord::Relation, options: T::Hash[T.untyped, T.untyped]).void }
  def queried_for_records(source_name, records_to_destroy, options = {})
    team_id_symbol = Arel.sql(options.fetch(:team_id_symbol, :team_id).to_s)
    team_ids = records_to_destroy.pluck(team_id_symbol).uniq
    team_ids_that_currently_exist = Team.batched_scope(:id, values: team_ids).pluck(:id)

    GitHub.logger.info("DestroyOrphanedTeamDependenciesJob queried for IDs to destroy", {
      source_name: source_name,
      record_ids_to_destroy_count: records_to_destroy.count,
      record_ids_to_destroy: records_to_destroy.pluck(:id).to_s,
      team_ids_that_currently_exist_count: team_ids_that_currently_exist.count,
      team_ids_that_currently_exist: team_ids_that_currently_exist.to_s,
      team_ids_count: team_ids.count,
      team_ids: team_ids
    })

    unless team_ids_that_currently_exist.empty?
      # stop future executions
      # https://github.slack.com/archives/C94P20RGQ/p1698093467326629

      # trigger a sev3 (configure this in datadog)
      error_message = "Marked a record for deletion that belongs to an existing team"
      GitHub.dogstats.event error_message, "source:#{source_name}"
      raise error_message
    end
  end

  sig { params(source_name: String, records_destroyed: T::Array[T.untyped]).void }
  def finished_destroy(source_name, records_destroyed)
    GitHub.dogstats.distribution("team.destruction.destroy_orphaned_team_dependencies.count", records_destroyed.count, tags: ["source:#{source_name}"])

    GitHub.logger.info("DestroyOrphanedTeamDependenciesJob destroyed orphaned records", {
      source_name: source_name,
      records_destroyed_count: records_destroyed.count,
      records_destroyed_record_ids: records_destroyed.map(&:id).to_s,
    })
  end

  sig { void }
  def cleanup_team_group_mapping
    team_group_mapping_ids = Team::GroupMapping.select(:team_id).distinct.pluck(:team_id)
    orphan_team_ids = team_group_mapping_ids - Team.batched_scope(:id, values: team_group_mapping_ids).pluck(:id)

    destroyed_records = with_write do
      records_to_destroy = Team::GroupMapping.where(team_id: orphan_team_ids)
      queried_for_records("Team::GroupMapping", records_to_destroy)
      records_to_destroy.destroy_all
    end
    finished_destroy("Team::GroupMapping", destroyed_records)
  end

  sig { void }
  def cleanup_user_role
    team_ids = UserRole.where(actor_type: "Team").select(:actor_id).distinct.pluck(:actor_id)
    orphan_team_ids = team_ids - Team.batched_scope(:id, values: team_ids).pluck(:id)

    destroyed_records = with_write do
      records_to_destroy = UserRole.where(actor_type: "Team", actor_id: orphan_team_ids)
      queried_for_records("UserRole actor", records_to_destroy, team_id_symbol: :actor_id)
      records_to_destroy.destroy_all
    end
    finished_destroy("UserRole actor", destroyed_records)
  end

  sig { void }
  def cleanup_team_invitation
    orphaned_record_ids = []
    TeamInvitation.order(:team_id).find_in_batches(batch_size: 1000) do |team_invitations|
      # Load associated OrganizationInvitations and Teams
      organization_invitation_ids = OrganizationInvitation.where(id: team_invitations.pluck(:organization_invitation_id)).where.not("organization_invitations.accepted_at": nil, "organization_invitations.cancelled_at": nil).order(:id).pluck(:id).to_set
      team_ids = Team.where(id: team_invitations.map(&:team_id)).order(:id).pluck(:id).to_set

      team_invitations.each do |team_invitation|
        # Ignore invitations that belong to valid teams
        next if team_ids.include?(team_invitation.team_id)
        # We don't delete invitations that are associated with org invitations that have been accepted or cancelled
        next if organization_invitation_ids.include?(team_invitation.organization_invitation_id)

        orphaned_record_ids << team_invitation.id
      end
    end

    destroyed_records = with_write do
      records_to_destroy = TeamInvitation.where(id: orphaned_record_ids)
      queried_for_records("TeamInvitation", records_to_destroy)
      records_to_destroy.destroy_all
    end
    finished_destroy("TeamInvitation", destroyed_records)
  end

  sig { void }
  def cleanup_child_team_change_parent_request
    child_team_change_parent_request_ids = TeamChangeParentRequest.select(:child_team_id).distinct.pluck(:child_team_id)
    orphan_team_ids = child_team_change_parent_request_ids - Team.batched_scope(:id, values: child_team_change_parent_request_ids).pluck(:id)

    destroyed_records = with_write do
      records_to_destroy = TeamChangeParentRequest.where(child_team_id: orphan_team_ids)
      queried_for_records("Child TeamChangeParentRequest", records_to_destroy, team_id_symbol: :child_team_id)
      records_to_destroy.destroy_all
    end
    finished_destroy("Child TeamChangeParentRequest", destroyed_records)
  end

  sig { void }
  def cleanup_parent_team_change_parent_request
    parent_team_change_parent_request_ids = TeamChangeParentRequest.select(:parent_team_id).distinct.pluck(:parent_team_id)
    orphan_team_ids = parent_team_change_parent_request_ids - Team.batched_scope(:id, values: parent_team_change_parent_request_ids).pluck(:id)

    destroyed_records = with_write do
      records_to_destroy = TeamChangeParentRequest.where(parent_team_id: orphan_team_ids)
      queried_for_records("Parent TeamChangeParentRequest", records_to_destroy, team_id_symbol: :parent_team_id)
      records_to_destroy.destroy_all
    end
    finished_destroy("Parent TeamChangeParentRequest", destroyed_records)
  end

  sig { void }
  def cleanup_team_membership_request
    orphan_team_ids = TeamMembershipRequest
      .joins("LEFT JOIN teams ON teams.id = team_membership_requests.team_id")
      .where(teams: { id: nil })
      .pluck(:team_id)

    destroyed_records = with_write do
      records_to_destroy = TeamMembershipRequest.where(team_id: orphan_team_ids)
      queried_for_records("TeamMembershipRequest", records_to_destroy)
      records_to_destroy.destroy_all
    end
    finished_destroy("TeamMembershipRequest", destroyed_records)
  end

  sig { void }
  def cleanup_ldap_mapping
    if GitHub.enterprise?
      orphan_team_ids = LdapMapping
        .where(subject_type: "Team")
        .joins("LEFT JOIN teams ON teams.id = ldap_mappings.subject_id")
        .where(teams: { id: nil })
        .pluck(:subject_id)

      destroyed_records = with_write do
        records_to_destroy = LdapMapping.where(subject_type: "Team").where(subject_id: orphan_team_ids)
        queried_for_records("LdapMapping", records_to_destroy, team_id_symbol: :subject_id)
        records_to_destroy.destroy_all
      end
      finished_destroy("LdapMapping", destroyed_records)
    end
  end

  sig { void }
  def cleanup_discussion_post
    discussion_post_ids = DiscussionPost.select(:team_id).distinct.pluck(:team_id)
    orphan_team_ids = discussion_post_ids - Team.batched_scope(:id, values: discussion_post_ids).pluck(:id).uniq

    destroyed_records = with_write do
      records_to_destroy = DiscussionPost.where(team_id: orphan_team_ids)
      queried_for_records("DiscussionPost", records_to_destroy)
      records_to_destroy.destroy_all
    end
    finished_destroy("DiscussionPost", destroyed_records)
  end
end
