# typed: true
# frozen_string_literal: true

module PullRequests::Copilot
  class CodeReviewGenerator
    CURRENT_JOBS = 1
    LOCK_TTL = 5.minutes
    INTERACTION_TYPE_SLUG = "code-review"

    attr_reader :requestor

    # Public: Generate a code review from Copilot for the given pull request.
    # requestor - User manually requesting a review from Copilot, or PR author for automatic reviews.
    sig { params(repo: Repository, pull: PullRequest, requestor: User).void }
    def initialize(repo:, pull:, requestor:)
      @repo = repo
      @pull = pull
      @requestor = requestor
      @pr_ref = T.must(Copilot::PullRequests::CodeReviewReferenceSerializer.new.to_hash(pull, include_diff: true, include_full_files: true))
    end

    # Public: Generate a code review from Copilot for the given pull request.
    # This assumes that feature flag and license checks have already passed.
    sig { returns(T::Boolean) }
    def generate
      return false if repo.nil? || requestor.nil? || pull.nil?

      success = T.let(true, T::Boolean)
      lock_key = "CodeReviewGenerator_#{pull.id}_#{pull.head_sha}"
      restraint = GitHub::Restraint.new
      restraint.lock!(lock_key, CURRENT_JOBS, LOCK_TTL) do
        # Load coding guideline references
        guidelines = Copilot::CodingGuideline.references_for(repo.id)

        # Mint a copilot chat app token so we can invoke CAPI on behalf of the user
        app = ::Apps::Privileged.integration(:copilot_pull_request_reviewer)
        new_access = app.grant(requestor)
        access, _ = new_access.redeem(extended_expiry: true)
        token = Copilot::DecryptedToken.from(access)

        capi = Copilot::User::CopilotApi.new(
          requestor,
          integration_id: CopilotAPI::COPILOT_PR_REVIEWS_INTEGRATION_ID,
          session: nil, # There won't ever be a user session
          real_ip: nil, # Same as above
          token:,
        )

        experiment_headers = set_experiment_headers_for_supported_languages(repo)
        resp = capi.create_code_review(
          references: [pr_ref].concat(guidelines),
          role: "user",
          experiment_headers: experiment_headers,
          interaction_id: generate_interaction_id,
          interaction_type: INTERACTION_TYPE_SLUG
        )
        log("got a successful response from CAPI")

        if !pull.can_request_review_from_copilot?(actor: requestor)
          log("actor cannot request review")
        end

        success = submit_review(resp)

      rescue CopilotAPI::NotFoundError, CopilotAPI::NetworkError => err
        log("failed to generate review: #{err}")
        GitHub.dogstats.increment("copilot_api.code_review.error", tags: ["type:#{err.class}"])
        success = submit_failed_review
      end

      if success
        log("successfully submitted review")
      else
        log("failed to submit review")
      end

      emit_persistence_metric(success:)

      success
    end

    sig { returns(T.untyped) }
    def submit_failed_review
      resp = { choices: nil, copilot_references: [] }

      submit_review(resp, return_with_error: true)
    end

    sig { params(message: String).void }
    def log(message)
      GitHub.logger.info("copilot_code_review_generate: #{message}",
        "gh.repository.id" => repo.name,
        "gh.user.id" => requestor.id,
        "gh.user.login" => requestor.display_login,
        "gh.pull_request.id" => pull.id,
        "gh.pull_request.url" => pull.url,
        "gh.job.aqueduct_id" => GitHub.context[:aqueduct_job_id],
      )
    end

    private

    attr_reader :repo, :pull, :pr_ref

    sig { params(success: T::Boolean).void }
    def emit_persistence_metric(success:)
      GitHub.dogstats.increment("copilot.code_review.persistence", tags: ["success:#{success}"])
    end

    sig { params(resp: T.any(T.untyped, T.untyped), return_with_error: T::Boolean).returns(T::Boolean) }
    def submit_review(resp, return_with_error: false)
      ref_data = pr_ref[:data]
      commit_id = ref_data[:headRevision]
      diff_start_commit_oid = ref_data[:comparisonStartOID]
      diff_end_commit_oid = ref_data[:comparisonEndOID]
      diff_base_commit_oid = ref_data[:comparisonBaseOID]
      pr_comments = review_comments(resp)
      review_body_message = PullRequests::Copilot::ReviewBodyMessageGenerator.new(
        pull:,
        repo:,
        comments: pr_comments,
        model_response: resp,
        requestor: requestor
      ).create

      PullRequests::Copilot::CodeReviewCreator.new(
        pull:,
        repo:,
        commit_id:,
        comments: pr_comments,
        diff_start_commit_oid:,
        diff_end_commit_oid:,
        diff_base_commit_oid:,
        body: review_body_message,
        return_with_error:,
      ).create
    end

    sig { params(resp: T.any(T.untyped, T.untyped)).returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
    def review_comments(resp)
      resp[:copilot_references].filter_map do |ref|
        next unless ref[:type] == "github.generated-pull-request-comment"

        # Data shape corresponds to https://github.com/github/copilot-api/blob/main/pkg/codereviewagent/panel_code_review_comment.go
        # path, line, body, side, problem_type, guideline_id
        ref[:data]
      end
    end

    def set_experiment_headers_for_supported_languages(repo)
      experiment_headers = {}
      if repo.feature_enabled_for_repo_or_owner?(:expand_supported_languages_cpp)
        experiment_headers.merge!({ "X-Experiment-Expand-Supported-Languages-Cpp" => "true" })
        log("enable C++ as supported language")
      end

      if repo.feature_enabled_for_repo_or_owner?(:copilot_code_review_enable_c_support)
        experiment_headers.merge!({ "X-Experiment-Expand-Supported-Languages-C" => "true" })
        log("enable C as supported language")
      end

      experiment_headers
    end

    def generate_interaction_id
      SecureRandom.uuid
    end
  end
end
