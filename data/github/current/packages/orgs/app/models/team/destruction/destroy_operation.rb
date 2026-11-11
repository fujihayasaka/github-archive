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

    def initialize(team, actor: nil)
      @team  = team
      @actor = actor || team.actor
    end

    def execute
      GitHub.logger.info(
        "Starting Team::Destruction::DestroyOperation",
        "gh.actor.id" => @actor.id,
        "gh.team.id" => @team.id,
        "gh.business.id" => @team.business_id
      )

      customer = team.business&.customer
      team_cost_centers_enabled = FeatureFlag.vexi.enabled?(:enterprise_teams_emit_team_destroy_memberships, customer, default: false) ||
        FeatureFlag.vexi.enabled?(:billing_cost_centers_enterprise_teams, customer, default: false)

      started_at  = Time.now
      descendants = team.descendants_depth_first
      all_teams   = descendants + [team]
      team_info   = self.class.team_info_for_dependants_destruction(all_teams)
      member_ids = Team.members_of(team.id, immediate_only: false, with_business_teams: team_cost_centers_enabled).pluck(:id)
      ancestor_ids = team.ancestor_ids

      destroyed_ids = team.class.transaction do
        enqueuing_hook_delivery(all_teams) do
          all_teams.each_slice(10).map do |teams|
            teams.select(&:delete)
          end.flatten.compact.map { |t| t.id.to_s }
        end
      end

      opts = team.business_team? ? { business: team.business } : {}
      opts[:parent_team_id] = team.id if descendants.any?
      job_args = [team.organization_ids, team_info.slice(*destroyed_ids), member_ids, ancestor_ids, opts]

      DestroyTeamDependantsJob.perform_later(*job_args)
      clear_group_syncer_mappings(all_teams)

      team.members_or_organizations_updated(action: :remove, operation: :team) if team.business_team?

      GitHub.dogstats.distribution("team.destruction.destroy_operation.dist.duration", (Time.now - started_at) * 1000)
      GitHub.dogstats.distribution("team.destruction.dist.destroyed_team_count", all_teams.count)

      GitHub.logger.info(
        "Finished Team::Destruction::DestroyOperation",
        "gh.actor.id" => @actor.id,
        "gh.team.id" => @team.id,
        "gh.business.id" => @team.business_id
      )

      all_teams.each do |destroyed_team|
        if destroyed_team.business_team?
          log_data = {
            actor: actor,
            team: destroyed_team,
            business: destroyed_team.business,
            type: destroyed_team.team_type,
          }
        else
          log_data = {
            actor: actor,
            team: destroyed_team,
            organization: destroyed_team.organization,
            type: destroyed_team.team_type,
          }
        end

        GlobalInstrumenter.instrument("team.destroy", log_data)
      end

      # Emit the destroyed team's membership list to billing platform so it can
      # retire each member's cost center attribution for this team. Scoped to the
      # destroyed enterprise team itself; organization teams and descendants are
      # intentionally skipped for now.
      if team.business_team? && team_cost_centers_enabled
        # The full member list is passed in a single enqueue. Teams are currently
        # capped at 5k members, but even if that grows substantially (~100k,
        # ~1 MB serialized) this stays well under Aqueduct's 5 MB inline payload
        # limit; the job splits it into batches when publishing to Hydro.
        HydroEmitTeamDestroyMembershipsJob.perform_later(Hydro::EntitySerializer.team(team), customer.id, member_ids)
      end
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
          leaf_team.organizations.each do |org|
            ClearTeamGroupMappingsJob.perform_later(org.global_relay_id, leaf_team.global_relay_id)
          end
        end
      end
    end
  end
end
