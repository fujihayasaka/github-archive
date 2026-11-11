# typed: strict
# frozen_string_literal: true

module MergeQueues
  module Service
    # Clear out the Merge Queue.
    #
    # Called by MergeQueueClearQueueJob
    class Disable
      sig { params(repository: Repository).void }
      def initialize(repository)
        @repository = repository
      end

      sig { void }
      def call
        GitHub.logger.with_named_tags(
          "code.namespace": "MergeQueues::Service::Disable",
          "code.function": "call",
          "gh.repo.id": @repository.id,
        ) do
          MergeQueue.where(repository: @repository).each do |queue|
            GitHub.logger.info("removing_queue", "gh.merge_queue.branch": queue.branch)

            ActiveRecord::Base.connected_to(role: :writing) do
              Clear.new(@repository, queue.branch, queue).call(MergeQueues.system_actor)
              queue.destroy
            end
          end
        end
      end
    end
  end
end
