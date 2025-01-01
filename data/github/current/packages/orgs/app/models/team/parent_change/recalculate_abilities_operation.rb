# typed: true
# frozen_string_literal: true
module Team::ParentChange
  class RecalculateAbilitiesOperation

    include AbilityHelpers

    attr_reader :payload, :options

    def initialize(payload, options = {})
      @payload = payload
      @options = options
      @throttler = options.delete(:throttler)
    end

    # Public: recalculates abilities for indirect members of a team that's been
    # moved around in a hierarchy
    #
    # 1. Calculate old and the new set of ancestors, and the following two sets
    #   a. set of new teams in the hierarchy
    #   b. set of old teams no longer in the hierarchy
    #
    # 2. get the direct abilities of users under this team
    # or its descendants.
    #
    # 3. get the indirect abilities whose parents are any of the direct abilities in 2,
    # and whose subjects (the teams they are pointing to) are the old teams
    # no longer in the hierarchy (1b). Remove them in batches
    #
    # 4. For each of the new nodes in the hierarchy, for each of the direct abilities,
    # create one indirect ability. Apply the creation in batches.
    #
    def execute
      only_old_ancestors = payload.old_ancestors - payload.new_ancestors
      only_new_ancestors = payload.new_ancestors - payload.old_ancestors

      descendants_or_self = payload.old_descendants + [payload.team_id]
      direct_ability_batch = direct_abilities(descendants_or_self)

      total_deleted = 0
      total_created = 0

      start = Time.now
      Ability.transaction do
        direct_ability_batch.each_slice(BATCH_SIZE) do |batch|
          direct_ability_ids = batch.map { |tuple| tuple[0] }
          to_delete = indirect_ability_ids(only_old_ancestors, parent_ids: direct_ability_ids)
          delete(to_delete)
          total_deleted += to_delete.length
        end

        direct_ability_batch.product(only_new_ancestors).each_slice(BATCH_SIZE) do |batch|
          create(batch)
          total_created += batch.length
        end
      end
      ms = (Time.now - start) * 1000
      GitHub.dogstats.distribution("ability.recalculate_abilities_operation.dist.duration", ms)

      GitHub.dogstats.distribution("ability.recalculate_abilities_operation.dist.abilities_deleted", total_deleted)
      GitHub.dogstats.distribution("ability.recalculate_abilities_operation.dist.abilities_created", total_created)
    end
  end
end
