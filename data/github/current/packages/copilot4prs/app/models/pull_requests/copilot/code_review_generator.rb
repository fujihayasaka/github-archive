# typed: true
# frozen_string_literal: true

module PullRequests::Copilot
  class CodeReviewGenerator
    CURRENT_JOBS = 1
    LOCK_TTL = 5.minutes
    INTERACTION_TYPE_SLUG = "code-review"
    INITIATOR_SLUG = "user"
    # The ID of copilot instructions is hardcoded for now at a value
    # that won't conflict with any coding guideline IDs.
    # The contents of the repository custom instructions is sent as
    # one additional coding guideline.
    COPILOT_REPO_INSTRUCTIONS_ID = 1000000

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
      # returning true here will prevent submitting a failed review
      return true unless active_review_request?

      success = T.let(true, T::Boolean)
      lock_key = "CodeReviewGenerator_#{pull.id}_#{pull.head_sha}"
      restraint = GitHub::Restraint.new
      restraint.lock!(lock_key, CURRENT_JOBS, LOCK_TTL) do
        # Mint a copilot chat app token so we can invoke CAPI on behalf of the user
        new_access = copilot_pull_request_reviewer_app.grant(requestor)
        access, _ = new_access.redeem(extended_expiry: true)
        token = Copilot::DecryptedToken.from(access)

        capi = Copilot::User::CopilotApi.new(
          requestor,
          integration_id: CopilotAPI::COPILOT_PR_REVIEWS_INTEGRATION_ID,
          session: nil, # There won't ever be a user session
          real_ip: nil, # Same as above
          token:,
        )

        log("making request to CAPI")
        resp = capi.create_code_review(
          references: code_review_references(pr_ref, repo),
          role: "user",
          experiment_headers: {},
          interaction_id: generate_interaction_id,
          interaction_type: INTERACTION_TYPE_SLUG,
          initiator: INITIATOR_SLUG
        )

        if FeatureFlag.vexi.enabled?(:log_capi_response_for_ccr, @requestor, default: false)
          log("received a response from CAPI: #{resp.to_json}")
        end

        log("got a successful response from CAPI")

        if FeatureFlag.vexi.enabled?(:ccr_duplicate_comment_tracking, requestor, default: false)
          PullRequests::Copilot::CodeReview::DuplicationIdentifier.call(response: resp, pull_request: pull)
        end

        status = submit_review(resp)

        case status
        when :succeeded
          log("submitted successful review")
          emit_persistence_metric(success: true)
        when :failed
          log("submitted failed review")
          emit_persistence_metric(success: false)
        when :cancelled
          log("review request cancelled")
        end

        status != :failed
      end
    rescue GitHub::Restraint::UnableToLock
      log("Unable to lock. Restraint on #{lock_key} already exists")
      # return true to prevent submitting a failed review
      true
    end

    sig { returns(T.untyped) }
    def submit_failed_review
      resp = { choices: nil, copilot_references: [] }

      submit_review(resp, return_with_error: true)
    end

    sig { returns(T.untyped) }
    def quota_exceeded_dismiss_review
      ActiveRecord::Base.connected_to(role: :writing) do
        active_review_request&.dismiss(via_copilot_quota: true)
        active_review_request&.save
      end
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
        "gh.request_id" => GitHub.context[:request_id]
      )
    end

    private

    attr_reader :repo, :pull, :pr_ref

    sig { params(success: T::Boolean).void }
    def emit_persistence_metric(success:)
      GitHub.dogstats.increment("copilot.code_review.persistence", tags: ["success:#{success}"])
    end

    sig { params(resp: T.untyped, return_with_error: T::Boolean).returns(Symbol) }
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

      # make sure that the user didn't cancel their review request
      unless active_review_request?
        return :cancelled
      end

      status = PullRequests::Copilot::CodeReviewCreator.new(
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

      status ? :succeeded : :failed
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

    def generate_interaction_id
      SecureRandom.uuid
    end

    def copilot_pull_request_reviewer_app
      return @app if defined?(@app)
      @app = ::Apps::Privileged.integration(:copilot_pull_request_reviewer)
    end

    def active_review_request?
      active_review_request.present?
    end

    def active_review_request
      bot = copilot_pull_request_reviewer_app.bot
      review_request = @pull.direct_review_request_for(bot)
      GitHub.dogstats.increment("copilot_api.code_review.cancelled", tags: ["mode:review"]) if review_request.nil?

      review_request
    end

    # Merge coding guidelines and custom-instructions.md (if ff set)
    # into a single array of references.
    sig { params(pr_ref: T::Hash[T.untyped, T.untyped], repo: Repository).returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
    def code_review_references(pr_ref, repo)
      guidelines = Copilot::CodingGuideline.references_for(repo.id)

      if @requestor.feature_enabled?(:copilot_code_review_repo_copilot_instructions)
        instructions = Copilot::CustomInstructions.for_repository(repo)

        if instructions&.key?(:prompt)
          guidelines << {
            type: "github.coding_guideline",
            id: "#{repo.name_with_display_owner}-#{COPILOT_REPO_INSTRUCTIONS_ID}",
            data: {
              id: COPILOT_REPO_INSTRUCTIONS_ID,
              type: "coding-guideline",
              repositoryId: repo.id,
              name: ".github/copilot-instructions.md",
              description: instructions[:prompt],
              filePatterns: [],
            }
          }
        end
      end
      [pr_ref].concat(guidelines)
    end
  end
end
