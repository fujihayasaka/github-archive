# typed: true
# frozen_string_literal: true

module Authorization
  module Commands
    class ClearAbilitiesForMultipleParticipants < Authorization::Operation

      BATCH_SIZE = 100

      attr_reader :participant_type, :participant_ids

      def initialize(participant_type:, participant_ids:)
        @participant_type = participant_type
        @participant_ids = Array.wrap(participant_ids)
      end

      def execute_implementation
        return default_result unless participant_ids.any?

        GitHub.dogstats.distribution_time "ability.clear.dist" do
          ids = Ability.connection.select_values(Arel.sql(<<-SQL, participant_ids: participant_ids, type: participant_type))
            (SELECT id FROM abilities
             WHERE actor_id IN (:participant_ids)
             AND actor_type = :type)
            UNION
            (SELECT id FROM abilities
             WHERE subject_id IN (:participant_ids)
             AND subject_type = :type)
          SQL

          if FeatureFlag.vexi.enabled_or_raise?(:clear_ability_batch_level_transactions) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
            delete_all_with_logging ids
            PermissionCache.clear
          else
            Ability.transaction do
              delete_all ids
              PermissionCache.clear
            end
          end
        end
      end

      def validation_errors
        errors = []

        if participant_type.nil?
          errors << validation_error(:need_participant_type)
        end

        errors
      end

      private

      # Internal: Deletes the abilities with the given ids and their children.
      #
      # Return nothing
      def delete_all(ids)
        ids.each_slice(BATCH_SIZE) do |slice|
          delete_children(slice)
          delete_abilities(slice)
        end
      end

      def delete_all_with_logging(ids)
        ids.each_slice(BATCH_SIZE) do |slice|
          begin

            # This will actually call delete_abilities with a slice of ids
            # so we have to separate the transaction to avoid an unbounded transaction
            # that can cause replication lag
            # this will also result in `BATCH_SIZE` transactions
            delete_children(slice)
            delete_abilities(slice)
          rescue ActiveRecord::StatementInvalid
            GitHub.logger.error(
              "ClearAbilitiesForMultipleParticipants delete failed", {
                "gh.ability.ids" => slice,
                "participant_type" => @participant_type,
              }
            )
            Failbot.report($!, :msg => "ClearAbilitiesForMultipleParticipants delete failed", "gh.ability.ids" => slice, "participant_type" => @participant_type)
          end
        end
      end

      # Internal: Deletes the abilities which parent is any of the given ids
      #
      # Return nothing
      def delete_children(ids)
        children_ids = Ability.connection.select_values(Arel.sql(<<-SQL, parent_ids: ids))
          SELECT id
          FROM abilities
          WHERE parent_id IN (:parent_ids)
          /* abilities-select-no-priority-needed */
        SQL

        children_ids.each_slice(BATCH_SIZE) do |slice|
          delete_abilities(slice)
        end
      end

      # Internal: Deletes the abilities with the given ids, throttling before the deletion
      #
      # Returns nothing
      def delete_abilities(ids)
        return if ids.empty?
        Ability.throttle do
          Ability.connection.delete(Arel.sql(<<-SQL, ids: ids))
            DELETE FROM abilities
            WHERE id IN (:ids)
          SQL
        end
      end
    end
  end
end
