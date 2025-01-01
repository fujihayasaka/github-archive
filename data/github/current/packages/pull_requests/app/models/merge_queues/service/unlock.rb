# typed: strict
# frozen_string_literal: true

module MergeQueues
  module Service
    class Unlock < Base
      extend T::Sig

      class Result < T::Enum
        enums do
          NextGroupEmpty = new(:empty)
          NextGroupNotLocked = new(:not_locked)
          Success = new(:success)
        end
      end

      sig { params(actor: User).returns(Result) }
      def call(actor:)
        GitHub.logger.with_named_tags(
          "code.namespace": "MergeQueues::Service::Unlock",
          "code.function": "call",
          "gh.repo.id": @repository.id,
          "gh.merge_queue.branch": @branch,
          "gh.actor.id": actor.id
        ) do
          if @merge_queue.nil?
            raise ActiveRecord::RecordNotFound
          end

          next_group = Group.find_next(
            configuration:,
            entries: factory.merge_queue_entry_models,
          )

          return Result::NextGroupEmpty if next_group.empty?
          return Result::NextGroupNotLocked unless next_group.locked?

          models = next_group.entries
          MergeQueueEntry.where(id: models.map(&:id)).update_all(locked: false)
          notify_websockets!(models)
          request_execution!

          return Result::Success
        end
      end
    end
  end
end
