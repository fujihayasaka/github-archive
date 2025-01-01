# typed: strict
# frozen_string_literal: true

module MergeQueues
  module Service
    class RollBackLockedGroup < Base
      extend T::Sig

      class Result < T::Enum
        enums do
          NoLockedGroup = new(:no_locked_group)
          Success = new(:success)
        end
      end

      sig { params(actor: User).returns(Result) }
      def call(actor:)
        GitHub.logger.with_named_tags(
          "code.namespace": "MergeQueues::Service::RollBackLockedGroup",
          "code.function": "call",
          "gh.repo.id": @repository.id,
          "gh.merge_queue.branch": @branch,
          "gh.actor.id": actor.id
        ) do
          if @merge_queue.nil?
            raise ActiveRecord::RecordNotFound
          end

          group = Group.find_next(configuration:, entries: factory.merge_queue_entry_models)

          return Result::NoLockedGroup unless group.locked?

          command = command_without_status_check_models

          remove_result = with_merge_mutex do
            ICommand::Result.with_retry do
              command.remove!(
                group.entries,
                actor:,
                reason: MergeQueues::Entry::RemovalReason::RollBack,
              )
            end
          end

          case remove_result
          when ICommand::Result::Error
            raise remove_result.as_exception
          when ICommand::Result::Success
            notify_websockets!(group.entries)
            request_execution!
            Result::Success
          else
            T.absurd(remove_result)
          end
        end
      end
    end
  end
end
