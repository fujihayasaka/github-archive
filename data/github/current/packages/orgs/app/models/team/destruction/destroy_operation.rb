# typed: true
# frozen_string_literal: true
module Team::Destruction

  # This class is reponsible for deleting a team, its descendants, and their dependants.
  # Destruction of the team hierarchy happens in the foreground, while dependants are
  # destroyed in the background.
  #
  # When Team#destroy is called, this operation is executed. The operation deletes the
  # given team and their descendants (other theams down in the hierarchy). Once those
  # teams are deleted, the workflow is delegated to `DestroyTeamDependantsJob`,
  # which will call `Team::DestroyDependantsOperation` to destroy the aforementioned team's
  # dependants (TeamInvitations, Abilities, and others)
  #
  class DestroyOperation
    attr_reader :team, :actor

    def initialize(team)
      @team  = team
      @actor = team.actor
    end

    def execute
      started_at  = Time.now
      descendants = team.descendants_depth_first
      all_teams   = descendants + [team]
      team_info   = self.class.team_info_for_dependants_destruction(all_teams)
      org_id      = team.organization_id
      member_ids = Team.members_of(team.id, immediate_only: false).pluck(:id)
      ancestor_ids = team.ancestor_ids

      destroyed_ids = team.class.transaction do
        enqueuing_hook_delivery(all_teams) do
          all_teams.each_slice(10).map do |teams|
            teams.select(&:delete)
          end.flatten.compact.map { |t| t.id.to_s }
        end
      end

      job_args = [org_id, team_info.slice(*destroyed_ids), member_ids, ancestor_ids, {}]
      DestroyTeamDependantsJob.perform_later(*job_args)
      clear_group_syncer_mappings(all_teams)

      GitHub.dogstats.distribution("team.destruction.destroy_operation.dist.duration", (Time.now - started_at) * 1000)
      GitHub.dogstats.distribution("team.destruction.dist.destroyed_team_count", all_teams.count)
    end

    # Returns a Hash containing the relevant info to destroy the team_dependants
    # after the teams have been destroyed
    #
    def self.team_info_for_dependants_destruction(teams)
      team_ids_and_info = teams.map do |team|
        id = team.id
        info = { name: team.name, slug: team.slug, legacy_owners: team.legacy_owners?, ldap_mapped: team.ldap_mapped?, enterprise_team_managed: team.enterprise_team_managed? }
        [id.to_s, info]
      end
      Hash[team_ids_and_info]
    end

    private

    # Enqueues a job to deliver hookshot events per team being removed
    # only if the actor is not spammy
    #
    def enqueuing_hook_delivery(teams)
      return yield if actor&.spammy?

      deliveries = teams.map do |team|
        event    = Hook::Event::TeamEvent.new(actor_id: actor.id, team_id: team.id, action: :deleted, triggered_at: Time.now)
        delivery = Hook::DeliverySystem.new(event)
        delivery.generate_hookshot_payloads
        delivery
      end

      result = yield

      deliveries.each(&:deliver_later)

      result
    end

    def clear_group_syncer_mappings(all_teams)
      # Only leaf node teams can be mapped to external groups
      leaf_node_teams = all_teams.reject(&:has_child_teams?)
      leaf_node_teams.each do |leaf_team|
        if leaf_team.group_mappings.any?
          ClearTeamGroupMappingsJob.perform_later(leaf_team.organization.global_relay_id, leaf_team.global_relay_id)
        end
      end
    end
  end
end
