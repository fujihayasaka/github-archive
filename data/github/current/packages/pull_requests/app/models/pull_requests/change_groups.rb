# typed: strict
# frozen_string_literal: true

module PullRequests
  module ChangeGroups
    extend GitHub::ResilienceMixin

    module GenerateResult
      extend T::Helpers
      sealed!
      abstract!
      requires_ancestor { Object }

      sig { abstract.returns(String) }
      def reason; end

      sig { abstract.returns(String) }
      def type; end

      class Unavailable < T::Struct
        include GenerateResult
        const :reason, String, override: true

        sig { override.returns(String) }
        def type = "unavailable"
      end

      class AlreadyGenerated
        include GenerateResult

        sig { returns(AlreadyGenerated) }
        def self.instance
          @instance ||= T.let(new, T.nilable(AlreadyGenerated))
        end

        private_class_method :new

        sig { override.returns(String) }
        def reason = "already_generated"

        sig { override.returns(String) }
        def type = "already_generated"
      end

      class PreviouslyFailedResult
        include GenerateResult

        sig { returns(PreviouslyFailedResult) }
        def self.instance
          @instance ||= T.let(new, T.nilable(PreviouslyFailedResult))
        end

        private_class_method :new

        sig { override.returns(String) }
        def reason = "previously_failed_result"

        sig { override.returns(String) }
        def type = "previously_failed_result"
      end

      class Queued < T::Struct
        include GenerateResult
        const :orchestration, Orchestrations::MakeChangeGroups

        sig { override.returns(String) }
        def reason = "queued"

        sig { override.returns(String) }
        def type = "queued"
      end

      class Error < T::Struct
        include GenerateResult
        const :exception, StandardError

        sig { override.returns(String) }
        def reason = exception.message

        sig { override.returns(String) }
        def type = "error"
      end
    end

    sig { params(pull_request: PullRequest, actor: User).returns(GenerateResult) }
    def self.generate_for(pull_request, actor)
      eligibility = Copilot::PullRequestGroupsAccess.new(
        actor:,
        current_repository: pull_request.repository,
      ).can_generate_automatic_groups_reason
      unless eligibility.access
        return GenerateResult::Unavailable.new(reason: eligibility.reason.to_s)
      end

      if pull_request.current_change_groups.any?
        already_generated = GenerateResult::AlreadyGenerated.instance
        log_result(pull_request, actor, already_generated)
        return already_generated
      end

      # Check for existing failed orchestrations for the current diff only if feature flag is enabled
      # This prevents repeatedly attempting to generate groups for diffs that are known to fail
      if FeatureFlag.vexi.enabled?(:persist_failed_make_change_group_orchestrations, default: false)
        existing_failed_orchestration = Orchestrations::MakeChangeGroups
          .where(repository_id: pull_request.repository_id, pull_request_id: pull_request.id)
          .order(updated_at: :desc)
          .find do |orch|
            orch.base_commit_oid == pull_request.base_sha &&
            orch.head_commit_oid == pull_request.head_sha &&
            orch.deterministic_failure?
          end

        if existing_failed_orchestration
          failure_reason = existing_failed_orchestration.failure_reason
          reason_string = failure_reason ? failure_reason.serialize : "unknown"
          previously_failed_result = GenerateResult::PreviouslyFailedResult.instance
          log_result(pull_request, actor, previously_failed_result)
          return previously_failed_result
        end
      end

      orchestration = T.let(nil, T.nilable(Orchestrations::MakeChangeGroups))
      Orchestrations::MakeChangeGroups.retry_on_find_or_create_error do
        orchestration = Orchestrations::MakeChangeGroups.active.find_by(
          repository_id: pull_request.repository_id,
          pull_request_id: pull_request.id,
        )
        if orchestration
          queued = GenerateResult::Queued.new(orchestration:)
          log_result(pull_request, actor, queued)
          return queued
        end

        orchestration = Orchestrations::MakeChangeGroups.create!(
          repository: pull_request.repository,
          pull_request:,
          actor:,
        )
      end

      if orchestration
        orchestration.execute!
      else
        # This seems unlikely in practice, because we'd have to hit the race
        # between finding an existing record and creating a new record twice
        # in the same run.
        error = GenerateResult::Error.new(exception: RuntimeError.new(
          "Exhausted retries to create a unique orchestration record"
        ))
        log_result(pull_request, actor, error)
        return error
      end

      queued = GenerateResult::Queued.new(orchestration:)
      log_result(pull_request, actor, queued)
      queued
    rescue => exception
      error = GenerateResult::Error.new(exception:)
      log_result(pull_request, actor, error)
      error
    end

    sig { params(pull_request: PullRequest, actor: User, result: GenerateResult).void }
    private_class_method def self.log_result(pull_request, actor, result)
      result_type = T.must(result.class.name).split("::").last
      GitHub.dogstats.increment("pull_requests.change_groups.generate_for.result", tags: ["type:#{result_type}"])

      GitHub.logger.info("Generate change groups result",
        "code.namespace" => "PullRequests::ChangeGroups",
        "code.function" => "generate_for",
        "result" => result_type,
        "reason" => result.reason,
        "gh.repo.id" => pull_request.repository&.id,
        "gh.user.id" => actor.id,
        "gh.user.login" => actor.display_login,
        "gh.pull_request.id" => pull_request.id,
      )
    end
  end
end
