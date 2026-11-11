# typed: strict
# frozen_string_literal: true

module PullRequests
  module Stacks
    sig do
      type_parameters(:R)
        .params(
          stack: Stack,
          ttl: Integer,
          block: T.proc.params(arg0: GitHub::Restraint::Lock).returns(T.type_parameter(:R))
        )
        .returns(T.type_parameter(:R))
    end
    def self.lock!(stack, ttl:, &block)
      GitHub::Restraint.new.lock!(
        "pull_requests/stack#{stack.id}",
        1, # Number of simultaneous locks
        ttl,
        &block
      )
    end

    sig { params(repository: T.nilable(T.any(Repository, T::Array[Repository]))).returns(T::Boolean) }
    def self.enabled?(repository)
      case repository
      when nil
        return false
      when Array
        return false if repository.empty?
      end

      FeatureFlag.vexi.enabled?(:pull_request_stacks, repository, default: false)
    end

    sig { params(pulls: T::Array[PullRequest], actor: User).returns(Create::Service::Result) }
    def self.create(pulls, actor:)
      Stacks::Create::Service.call(pulls, actor:, log_context: {
        "gh.stacks.operation" => "create",
      })
    end

    sig { params(stack: Stack, pull_requests: T::Array[PullRequest], actor: User).returns(UpdatePulls::Service::Result) }
    def self.update_pulls(stack, pull_requests, actor:)
      UpdatePulls::Service.call(stack, pull_requests, actor:, log_context: {
        "gh.stacks.operation" => "update_pulls",
      })
    end

    sig { params(top: PullRequest, bottom: PullRequest, actor: User).returns(CreateOrAppend::Service::Result) }
    def self.create_or_append(top:, bottom:, actor:)
      CreateOrAppend::Service.call(top:, bottom:, actor:, log_context: {
        "gh.stacks.operation" => "create_or_append",
      })
    end

    sig { params(stack: Stack, actor: User).returns(Unstack::Service::Result) }
    def self.unstack(stack, actor:)
      Unstack::Service.call(stack, actor:, log_context: {
        "gh.stacks.operation" => "unstack",
      })
    end

    # Enqueue a job to rebase each branch in a given stack.
    sig do
      params(
        stack: PullRequests::Stack,
        actor: User,
        expected_head_oid_by_pr_number: T::Hash[Integer, String],
        start_pull_request: T.nilable(PullRequest),
      ).returns(UpdateAllBranches::EnqueueService::Result)
    end
    def self.update_all_branches_later(stack:, actor:, expected_head_oid_by_pr_number:, start_pull_request: nil)
      UpdateAllBranches::EnqueueService.call(
        stack:,
        actor:,
        expected_head_oid_by_pr_number:,
        start_pull_request:,
        log_context: {
          "gh.stacks.operation" => "update_all_branches_later",
        }
      )
    end

    # Rebase each branch in the given PR's stack.
    #
    # This method is too slow for a request/response cycle, and should only
    # be used in background jobs. If you want to trigger a rebase from a
    # request use `.update_all_branches_later` instead.
    sig do
      params(
        start_pull_request: ::PullRequest,
        actor: ::User,
        expected_head_oid_by_pr_number: T::Hash[String, String],
      ).returns(UpdateAllBranches::Service::Result)
    end
    def self.update_all_branches_now(start_pull_request:, actor:, expected_head_oid_by_pr_number:)
      UpdateAllBranches::Service.call(
        start_pull_request:,
        actor:,
        expected_head_oid_by_pr_number:,
        log_context: {
          "gh.stacks.operation" => "update_all_branches_now",
        }
      )
    end
  end
end
