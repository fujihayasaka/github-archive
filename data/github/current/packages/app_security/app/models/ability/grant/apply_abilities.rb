# typed: true
# frozen_string_literal: true
#
module Ability::Grant::ApplyAbilities
  # Internal: update the abilities table.
  def apply_abilities(rows = [], stats_key: nil)
    if !rows.empty?
      rows.each_slice(Ability::BATCH_SIZE) do |slice|
        origin = "Called from Ability::Grant#apply_abilities"
        Ability.throttle_with_retry(max_retry_count: Ability::Grant::THROTTLE_RETRIES, err_msg: origin, noop_on_foreground: true) do
          Ability.connection.insert(Arel.sql(<<-SQL, rows: Arel::Nodes::ValuesList.new(slice)))
            INSERT IGNORE INTO abilities
            (actor_id, actor_type, action, subject_id, subject_type,
             priority, parent_id, created_at, updated_at)
            :rows
          SQL
        end
      end

      if stats_key
        GitHub.dogstats.distribution "ability.granted.#{stats_key}.dist", rows.size
      end
      true
    end
  end
end
