# typed: true
# frozen_string_literal: true

module Team::ParentChange
  class RepairAbilitiesOperation

    include AbilityHelpers

    attr_reader :org_id

    def initialize(org_id, options = {})
      @org_id    = org_id
      @throttler = options.delete(:throttler)
    end

    # Get all the teams in the organization
    # For each team
    #  * delete the indirect abilities
    #  * get the direct members
    #  * get the path (so we know the ancestors for which we create the indirect abilites)
    #  * rebuild the indirect abilities for each user and path
    def execute
      return unless Organization.find_by(id: org_id)
      lock = Team::ParentChange::Lock.new(org_id: org_id)
      locked_successfully = lock.try_lock!

      total_deleted = 0
      total_created = 0

      start = Time.now
      Team.where(organization_id: org_id).find_in_batches do |teams|
        total_deleted += delete_indirect_team_abilities(teams)
        total_created += create_indirect_team_abilities(teams)
      end
      ms = (Time.now - start) * 1000
      GitHub.dogstats.distribution("ability.repair_abilities_operation.dist.duration", ms)

      Team::ParentChange::PendingQueue.new(org_id: org_id).destroy

      GitHub.dogstats.distribution("ability.repair_abilities_operation.abilities_created", total_created)
      GitHub.dogstats.distribution("ability.repair_abilities_operation.abilities_deleted", total_deleted)
    rescue Team::ParentChange::CannotAcquireLockError => err
      locked_successfully = false
      Failbot.report(err)
      raise err
    ensure
      lock.unlock if lock.present? && locked_successfully
    end

    def delete_indirect_team_abilities(teams)
      deleted = 0
      team_ids = teams.map(&:id)
      indirect_ability_ids(team_ids).each_slice(BATCH_SIZE) do |batch|
        delete(batch)
        deleted += batch.length
      end
      deleted
    end

    def create_indirect_team_abilities(teams)
      created = 0
      teams.each do |team|
        ancestor_ids          = team.ancestor_ids
        direct_ability_tuples = direct_abilities(Array.wrap(team.id))
        direct_ability_tuples.product(ancestor_ids).each_slice(BATCH_SIZE) do |batch|
          create(batch)
          created += batch.length
        end
      end
      created
    end
  end
end
