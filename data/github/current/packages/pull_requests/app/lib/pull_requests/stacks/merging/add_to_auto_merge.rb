# typed: strict
# frozen_string_literal: true

module PullRequests
  module Stacks
    module Merging
      # Validate the PR and add the stack to the auto merge queue.
      #
      # TODO: Migrate this to the new PullRequests::Merge infrastructure once that code
      # supports stacks.
      class AddToAutoMerge
        sig do
          params(
            pull_request: PullRequest,
            actor: T.any(User, Integration),
            email: T.nilable(UserEmail),
            commit_title: T.nilable(String),
            commit_message: T.nilable(String),
            remote_ip: T.nilable(String),
            merge_method: Symbol, # One of :merge, :squash, or :rebase
          ).void
        end
        def initialize(pull_request:, actor:, email: nil, commit_title: nil, commit_message: nil, remote_ip: nil, merge_method: :merge)
          @pull_request = pull_request
          @actor = actor
          @email = email
          @commit_title = commit_title
          @commit_message = commit_message
          @remote_ip = remote_ip
          @merge_method = merge_method
        end

        sig { returns(T.any(Result::Success, Result::Error, Result::NoLongerStacked)) }
        def call
          return Result::NoLongerStacked.new unless @pull_request.stacked?
          return Result::NoLongerStacked.new unless stack = @pull_request.stack
          return Result::Error.new(message: "Error resolving repository") unless repository = @pull_request.base_repository

          if AutoMergeRequest.where(repository_id: repository.id, pull_request: stack.pull_requests.where.not(id: @pull_request.id)).exists?
            return Result::Error.new(message: "Another pull request in this stack already has auto-merge enabled")
          end

          mode = if ::MergeQueue.for(repository:, branch: stack.base_ref)
            Merge::Mode::StackedQueue.new
          else
            Merge::Mode::StackedWait.new(strategy: Merge::Enums::Strategy.deserialize(@merge_method))
          end

          command = Merge::Command.new(
            pull_request: @pull_request,
            repository:,
            actor: @actor,
            mode:,
            runtime: Merge::Enums::Runtime::Creation,
          )

          # Workaround: Validate that the given merge method is allowed.
          # Uses partial logic from PullRequests::Merge::Command#validate!
          #
          # TODO: Remove this workaround in favor of PullRequests::Merge::Command#validate!
          # after it assigns the stack's merge method correctly. See PullRequests::Merge::Rules#merge_method
          user = @actor
          result = MergeConditions::PullRequestMergeMethod.async_evaluate(@pull_request, T.cast(user, User), @merge_method).sync
          if result.failed?
            return Result::Error.new(message: T.must(result.message))
          end
          # End workaround

          case validation = command.validate!
          when Merge::ICommand::Result::Error
            Failbot.report(validation.exception)
            return Result::Error.new(message: "Unknown error occurred while validating your request")
          when Merge::Results::AlreadyMerged
            return Result::Error.new(message: "Pull request is already merged")
          when Merge::Results::Invalid
            return Result::Error.new(message: validation.message)
          when Merge::ICommand::Result::TerminalBranchRuleFailure
            return Result::Error.new(message: validation.messages&.join(", ") || "Terminal branch rule failure")
          when Merge::ICommand::Result::ResolvableBranchRuleFailure
            # Resolvable failures are acceptable — the merge queue will
            # re-evaluate these conditions before merging.
          when Merge::ICommand::Result::Success
            # continue
          else T.absurd(validation)
          end

          # TODO: Migrate to command.create_auto_merge_request once the data model supports stacks.
          @pull_request.create_auto_merge_request!(
            user: @actor,
            commit_email_address_id: @email&.id,
            commit_title: @commit_title,
            commit_message: @commit_message,
            actor_ip_address: @remote_ip,
            merge_method: stack_merge_method(mode),
            skip_create_callbacks: true,
          )

          command.request_auto_merge_job!(enqueue_reason: "auto_merge_request_created_stacked_pull_request")

          Result::Success.new
        rescue ActiveRecord::RecordNotUnique
          Result::Success.new
        rescue ActiveRecord::RecordInvalid => exception
          Result::Error.new(message: exception.record.errors.full_messages.to_sentence, exception:)
        end

        private

        sig { params(mode: T.any(Merge::Mode::StackedQueue, Merge::Mode::StackedWait)).returns(Symbol) }
        def stack_merge_method(mode)
          # Merge queue configuration determines the merge method at dequeue
          # time, so always use the generic :merge_queue_stack enum.
          return :merge_queue_stack if mode.is_a?(Merge::Mode::StackedQueue)

          case @merge_method
          when :squash then :auto_squash_and_merge_stack
          when :rebase then :auto_rebase_and_merge_stack
          else :auto_merge_stack
          end
        end
      end
    end
  end
end
