# typed: true
# frozen_string_literal: true

module PullRequests::Copilot::CodeReview
  class ThreadReplyGenerator
    include GitHub::Memoizer

    CURRENT_JOBS = 1
    LOCK_TTL = 5.minutes
    INTERACTION_TYPE_SLUG = "code-review"
    INITIATOR_SLUG = "user"
    # The ID of copilot instructions is hardcoded for now at a value
    # that won't conflict with any coding guideline IDs (currently max 6)
    # Currently all copilot instructions are stored in a single file and
    # sent as one additoinal coding guideline.
    COPILOT_INSTRUCTIONS_ID = 100
    CHAT_WITH_CCR_GUIDELINE_ID = 200

    attr_reader :requestor

    # Public: Generate a code review from Copilot for the given pull request.
    # requestor - User manually requesting a review from Copilot, or PR author for automatic reviews.
    sig { params(comment: PullRequestReviewComment, pull: PullRequest, repo: Repository, requestor: User, review: PullRequestReview, thread: PullRequestReviewThread).void }
    def initialize(comment:, pull:, repo:, requestor:, review:, thread:)
      @comment = comment
      @pull = pull
      @repo = repo
      @requestor = requestor
      @review = review
      @thread = thread
      @pr_ref = T.must(
        Copilot::PullRequests::CodeReviewReferenceSerializer.new.to_hash(
          pull,
          include_diff: true,
          include_full_files: true,
        ),
      )
    end

    # Public: Generate a code review thread reply from Copilot for the given thread.
    # This assumes that feature flag and license checks have already passed.
    sig { returns(T::Boolean) }
    def generate
      return false if repo.nil? || requestor.nil? || pull.nil? || thread.nil? || comment.nil?

      success = T.let(true, T::Boolean)
      lock_key = "CodeReviewThreadReplyGenerator_#{pull.id}_#{pull.head_sha}"
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
        references = code_review_references(pr_ref, repo).concat(comment_guidelines)

        response = capi.create_code_review(
          references:,
          role: "user",
          experiment_headers: {},
          interaction_id:,
          interaction_type: INTERACTION_TYPE_SLUG,
          initiator: INITIATOR_SLUG
        )

        if GitHub.flipper[:log_capi_response_for_ccr].enabled?(@requestor)
          log("received a response from CAPI: #{response.to_json}")
        end

        log("got a successful response from CAPI")

        status = submit_reply(response:)

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

        ActiveRecord::Base.connected_to(role: :writing) { unreact_to_comment }

        status != :failed
      end
    rescue GitHub::Restraint::UnableToLock
      log("Unable to lock. Restraint on #{lock_key} already exists")
      # return true to prevent submitting a failed review
      true
    end

    sig { returns(T.untyped) }
    def submit_failed_review_thread_reply
      response = { choices: nil, copilot_references: [] }

      submit_reply(response:, return_with_error: true)
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

    attr_reader :comment, :pr_ref, :pull, :repo, :review, :thread

    def interaction_id = SecureRandom.uuid

    sig { params(success: T::Boolean).void }
    def emit_persistence_metric(success:)
      GitHub.dogstats.increment("copilot.code_review_thread_reply.persistence", tags: ["success:#{success}"])
    end

    sig { params(response: T.untyped, return_with_error: T::Boolean).returns(Symbol) }
    def submit_reply(response:, return_with_error: false)
      pr_comments = review_comments(response:)
      log("Found #{pr_comments.length} comments in response")
      target_response = pr_comments.find { |c| c["line"] == thread.blob_position + 1 }
      log("Target response: #{target_response}")

      unless target_response.present?
        if return_with_error
          log("No target response found, returning with error")
          return :cancelled
        else
          log("No target response found, returning failed")
          return :failed
        end
      end

      log("creating thread reply with body: #{target_response['body']}")
      status = PullRequests::Copilot::CodeReview::ThreadReplyCreator.new(
        bot: copilot_pull_request_reviewer_app.bot,
        comment: target_response,
        pull:,
        return_with_error:,
        thread:,
      ).create

      if status
        log("Thread reply created successfully")
        :succeeded
      else
        log("Thread reply creation failed")
        :failed
      end
    end

    sig { params(response: T.untyped).returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
    def review_comments(response:)
      response[:copilot_references].filter_map do |ref|
        next unless ref[:type] == "github.generated-pull-request-comment"

        # Data shape corresponds to https://github.com/github/copilot-api/blob/main/pkg/codereviewagent/panel_code_review_comment.go
        # path, line, body, side, problem_type, guideline_id
        ref[:data]
      end
    end

    REPLY_PROMPT = <<~PROMPT
      Please ONLY reply to the comment below.
      You may take all the above directions into context, but your reply should be focused on the comment below.
      The comment starts with 'COMMENT STARTS HERE' and ends with 'COMMENT ENDS HERE'.
    PROMPT

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def comment_guidelines
      description = [
        REPLY_PROMPT,
        "COMMENT STARTS HERE",
        comment.body,
        "COMMENT ENDS HERE",
        "Here is the full thread context:",
        thread.comments.map { |c| "#{c.user.display_login}: #{c.body}" }.join("\n"),
      ].join("\n")

      [
        {
          type: "github.coding_guideline",
          id: "#{repo.name_with_display_owner}-#{CHAT_WITH_CCR_GUIDELINE_ID}",
          data: {
            id: CHAT_WITH_CCR_GUIDELINE_ID,
            type: "coding-guideline",
            repositoryId: repo.id,
            name: "chat-with-ccr-guideline",
            description:,
            filePatterns: [],
          },
        },
      ]
    end

    memoize def copilot_pull_request_reviewer_app
      ::Apps::Privileged.integration(:copilot_pull_request_reviewer)
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
            id: "#{repo.name_with_display_owner}-#{COPILOT_INSTRUCTIONS_ID}",
            data: {
              id: COPILOT_INSTRUCTIONS_ID,
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

    sig { void }
    def unreact_to_comment
      ::PullRequestReviewCommentReaction.unreact(
        user: copilot_pull_request_reviewer_app.bot,
        subject_id: comment.id,
        content: ThreadReplyProcessor::REACTION_CONTENT,
      )
    end
  end
end
