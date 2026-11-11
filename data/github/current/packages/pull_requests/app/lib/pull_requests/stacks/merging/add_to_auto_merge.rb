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
            actor: T.any(User, Bot, Integration),
            email: T.nilable(UserEmail),
            commit_title: T.nilable(String),
            commit_message: T.nilable(String),
            remote_ip: T.nilable(String),
          ).void
        end
        def initialize(pull_request:, actor:, email: nil, commit_title: nil, commit_message: nil, remote_ip: nil)
          @pull_request = pull_request
          @actor = actor
          @email = email
          @commit_title = commit_title
          @commit_message = commit_message
          @remote_ip = remote_ip
        end

        sig { returns(T.any(Result::Success, Result::Error, Result::NoLongerStacked)) }
        def call
          return Result::NoLongerStacked.new unless @pull_request.stacked?
          return Result::NoLongerStacked.new unless stack = @pull_request.stack
          return Result::Error.new(message: "Error resolving repository") unless repository = @pull_request.base_repository

          mode = if ::MergeQueue.for(repository:, branch: stack.base_ref)
            Merge::Mode::Queue.new(jump: false, solo: false, strategy: Merge::Enums::Strategy::Stack)
          else
            Merge::Mode::Wait.new(strategy: Merge::Enums::Strategy::Stack)
          end

          command = Merge::Command.new(
            pull_request: @pull_request,
            repository:,
            actor: @actor,
            mode:,
            runtime: Merge::Enums::Runtime::Creation,
          )

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
            merge_method: mode.is_a?(Merge::Mode::Queue) ? :merge_queue_stack : :auto_merge_stack,
            skip_create_callbacks: true,
          )

          command.request_auto_merge_job!

          Result::Success.new
        rescue ActiveRecord::RecordNotUnique
          Result::Success.new
        rescue ActiveRecord::RecordInvalid => exception
          Result::Error.new(message: exception.record.errors.full_messages.to_sentence)
        end
      end
    end
  end
end
