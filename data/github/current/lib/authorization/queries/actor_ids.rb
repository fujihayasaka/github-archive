# typed: true
# frozen_string_literal: true

require_relative "base_query"

module Authorization
  module Queries
    class ActorIds < BaseQuery
      include Scientist
      BATCH_SIZE = 1_000

      attr_reader :actor_type, :subject, :actor_ids, :action, :through

      def initialize(actor_type:, subject:, actor_ids: :any, action: :any, through: [])
        @actor_type = actor_type
        @subject = subject
        @actor_ids = actor_ids
        @action = action
        @through = through
      end

      def execute_implementation
        # get all actor_ids that have access to the subject
        # the call always specifies
        #  - Actor Type
        #  - Subject ID
        #  - Subject Type

        # The call can specify
        #  - actor ids -> see as validating if those actors have access to the subject
        #  - action -> the action a actor needs on the subject
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

        if !actor_type
          errors << validation_error(:missing_actor_type)
        end

        unless valid_subject?(subject)
          errors << validation_error(:invalid_subject, subject: subject)
        end

        if action != :any && !Array.wrap(action).all? { |a| valid_action?(a) }
          errors << validation_error(:invalid_action, action: action)
        end

        errors
      end

      private

      def direct_assignments
        direct_scope = Ability.direct.where(
          subject_id: subject.ability_id,
          subject_type: subject.ability_type,
          actor_type: actor_type,
        )

        unless action == :any
          direct_scope = direct_scope.where("action = ?", Ability.actions[action])
        end

        if actor_ids == :any
          if GitHub.flipper[:actor_id_result_batching].enabled?
            candidate_batched_result(direct_scope)
          else
            science "result_batch_direct_actor_ids" do |e|
              e.use { direct_scope.pluck(:actor_id) }
              e.try { candidate_batched_result(direct_scope) }
              e.compare { |control, candidate| control.sort == candidate.sort }
            end
          end
        else
          # the batched_scope is already limiting the result set
          direct_scope.batched_scope(:actor_id, values: actor_ids).pluck(:actor_id)
        end
      end

      def indirect_assignments
        indirect_scope = Ability.indirect_via_children.
          where(
            actor_type: actor_type,
            subject_type: through,
            children: {
              subject_id: subject.ability_id,
              subject_type: subject.ability_type
            }
          )

        if action != :any
          indirect_scope = indirect_scope.where("children.action = ?", Ability.actions[action])
        end

        if actor_ids == :any
          if GitHub.flipper[:actor_id_result_batching].enabled?
            candidate_batched_result(indirect_scope)
          else
            science "result_batch_indirect_actor_ids" do |e|
              e.use { indirect_scope.pluck(:actor_id) }
              e.try { candidate_batched_result(indirect_scope) }
              e.compare { |control, candidate| control.uniq.sort == candidate.uniq.sort }
            end
          end
        else
          indirect_scope.batched_scope(:actor_id, values: actor_ids).pluck(:actor_id)
        end
      end

      def candidate_batched_result(scope)
        result = T.let([], T::Array[T.untyped])
        iterator = GitHub::QueryBatching::ScopeIterator.new(scope.select(:id, :actor_id), batch_size: BATCH_SIZE) do |config|
          config.use_seek_batching
        end

        iterator.batches.each do |batch|
          result += batch.pluck(:actor_id)
        end
        result
      end
    end
  end
end
