# typed: strict
# frozen_string_literal: true

module PullRequests
  module Stacks
    module CreateOrAppend
      # This service takes two PRs, and attempts to combine them into a stack.
      #
      # If the bottom PR is already part of a stack, we will attempt to append
      # the top PR onto that stack by delegating to the
      # `Stacks::UpdatePulls::Service`.
      #
      # If the bottom PR is not already part of a stack, we will attempt to
      # create a new stack by delegating to the `Stacks::Create::Service`.
      class Service
        class Success < T::Struct
          const :stack, Stack
          const :created, T::Boolean
        end

        Result = T.type_alias { T.any(Success, Error) }

        sig { params(top: PullRequest, bottom: PullRequest, actor: User, log_context: T::Hash[String, String]).returns(Result) }
        def self.call(top:, bottom:, actor:, log_context: {})
          new(top:, bottom:, actor:, log_context:).call
        end

        sig { params(top: PullRequest, bottom: PullRequest, actor: User, log_context: T::Hash[String, String]).void }
        def initialize(top:, bottom:, actor:, log_context:)
          @top = top
          @bottom = bottom
          @actor = actor
          @log_context = log_context
        end

        sig { returns(Result) }
        def call
          if stack = @bottom.stack
            add_to_existing_stack(stack)
          else
            create_new_stack
          end
        end

        private

        sig { params(stack: Stack).returns(Result) }
        def add_to_existing_stack(stack)
          result = PullRequests::Stacks::UpdatePulls::Service.call(
            stack, stack.pull_requests + [@top],
            actor: @actor,
            log_context: @log_context,
          )
          case result
          when PullRequests::Stacks::Error
            result
          when PullRequests::Stacks::UpdatePulls::Service::Success
            Success.new(stack:, created: false)
          else
            T.absurd(result)
          end
        end

        sig { returns(Result) }
        def create_new_stack
          result = PullRequests::Stacks::Create::Service.call(
            [@bottom, @top],
            actor: @actor,
            log_context: @log_context,
          )
          case result
          when PullRequests::Stacks::Error
            result
          when Stack
            Success.new(stack: result, created: true)
          else
            T.absurd(result)
          end
        end
      end
    end
  end
end
