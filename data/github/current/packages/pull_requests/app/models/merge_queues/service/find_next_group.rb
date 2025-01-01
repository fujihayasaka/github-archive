# typed: strict
# frozen_string_literal: true

module MergeQueues
  module Service
    class FindNextGroup < Base
      extend T::Sig

      sig { returns(T::Array[MergeQueueEntry]) }
      def call
        GitHub.logger.with_named_tags(
          "code.namespace": "MergeQueues::Service::FindBestEntry",
          "code.function": "call",
          "gh.repo.id": @repository.id,
          "gh.merge_queue.branch": @branch,
        ) do
          if @merge_queue.nil?
            raise ActiveRecord::RecordNotFound
          end

          next_group = Group.find_next(configuration:, entries: factory.merge_queue_entry_models)

          case next_group_state = next_group.state
          when Group::State::Mergeable
            return next_group.entries
          when Group::State::Empty, Group::State::MinimumSizeNotMet
            return []
          else
            T.absurd(next_group_state)
          end
        end
      end
    end
  end
end
