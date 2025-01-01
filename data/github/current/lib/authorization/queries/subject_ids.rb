# typed: true
# frozen_string_literal: true

require_relative "base_query"

module Authorization
  module Queries
    class SubjectIds < BaseQuery
      include Scientist
      BATCH_SIZE = 1_000

      attr_reader :actor, :subject_type, :through, :actions, :subject_ids

      def initialize(actor:, subject_type:, through: [], actions: :any, subject_ids: :all)
        @actor = actor
        @subject_type = subject_type
        @subject_ids = subject_ids
        @through = through
        @actions = actions
      end

      def execute_implementation
        # get all subject_ids that the actor has access to
        # the call always specifies
        #  - Actor Type
        #  - Actor ID
        #  - Subject Type

        # The call can specify
        #  - Subject IDs -> see as validating if those aubjects can be access by the actor
        #  - actions -> list of actions a actor needs one of on the subject
        result = direct_assignments

        unless through.empty?
          result += indirect_assignments
        end
        result.flatten.uniq
      end

      def default_result
        []
      end

      def validation_errors
        errors = []

        unless valid_actor?(actor)
          errors << validation_error(:invalid_actor, actor: actor)
        end

        errors
      end

      private

      def direct_assignments
        direct_scope = Ability.direct.where(
          actor_type: actor.ability_type,
          actor_id: actor.ability_id,
          subject_type: subject_type,
        )

        unless actions == :any
          direct_scope = direct_scope.where(action: actions.map { |action| Ability.actions[action] })
        end

        if subject_ids == :all
          if FeatureFlag.vexi.enabled_or_raise?(:subject_id_result_batching) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
            candidate_batched_result(direct_scope, :subject_id)
          else
            science "result_batch_direct_subject_ids" do |e|
              e.use { direct_scope.pluck(:subject_id) }
              e.try { candidate_batched_result(direct_scope, :subject_id) }
              e.compare { |control, candidate| control.sort == candidate.sort }
            end
          end
        else
          # the batched_scope is already limiting the result set
          direct_scope.batched_scope(:subject_id, values: subject_ids).pluck(:subject_id)
        end
      end

      def indirect_assignments
        result = []
        indirect_scope = Ability.indirect_via_children.
          where(
            actor_id: actor.ability_id,
            actor_type: actor.ability_type,
            subject_type: through,
            children: {
              subject_type: subject_type,
              priority: Ability.priorities[:direct]
            }
          )

        if actions != :any
          indirect_scope = indirect_scope.where("children.action": actions.map { |action| Ability.actions[action] })
        end

        if subject_ids == :all
          result = if FeatureFlag.vexi.enabled_or_raise?(:subject_id_result_batching) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
            candidate_batched_result(indirect_scope, "children.subject_id")
          else
            science "result_batch_indirect_subject_ids" do |e|
              e.use { indirect_scope.pluck("children.subject_id") }
              e.try { candidate_batched_result(indirect_scope, "children.subject_id") }
              e.compare { |control, candidate| control.uniq.sort == candidate.uniq.sort }
            end
          end
        else
          # the batched_scope is already limiting the result set
          subject_ids.each_slice(BATCH_SIZE) do |batch|
            result << indirect_scope.where("children.subject_id": batch).pluck("children.subject_id")
          end
        end
        result
      end

      def candidate_batched_result(scope, column)
        result = T.let([], T::Array[T.untyped])
        iterator = GitHub::QueryBatching::ScopeIterator.new(scope.select(:id, column), batch_size: BATCH_SIZE)  do |config|
          config.use_seek_batching
        end

        iterator.batches.each do |batch|
          result += batch.pluck(column)
        end
        result
      end
    end
  end
end
