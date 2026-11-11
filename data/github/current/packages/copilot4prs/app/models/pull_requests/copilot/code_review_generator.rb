# typed: true
# frozen_string_literal: true

module PullRequests::Copilot
  class CodeReviewGenerator
    CURRENT_JOBS = 1
    LOCK_TTL = 5.minutes
    INTERACTION_TYPE_SLUG = "code-review"
    INITIATOR_SLUG = "user"
    SNIPPY_DEFAULT_REQUEST_ID = "1"
    SNIPPY_DEFAULT_IP_ADDRESS = "127.0.0.1"
    SNIPPY_AUTH_TOKEN_HEADERS = {
      editor_version: "2",
      editor_plugin_version: "2",
      request_id: SNIPPY_DEFAULT_REQUEST_ID,
      ip_address: SNIPPY_DEFAULT_IP_ADDRESS,
    }.freeze

    APPROVAL_READINESS_READY = "This pull request is ready to be approved."
    APPROVAL_READINESS_REQUIRES_CHANGES = "This pull request requires changes."
    APPROVAL_READINESS_TOO_COMPLEX = "This pull request is too complex or risky for automated approval."

    attr_reader :requestor

    class GetSecretsError < StandardError; end
    class NotFoundError < StandardError; end
    class UnauthorizedError < StandardError; end

    # Public: Generate a code review from Copilot for the given pull request.
    # requestor - User manually requesting a review from Copilot, or PR author for automatic reviews.
    sig { params(repo: Repository, pull: PullRequest, requestor: User, request_id: T.nilable(String)).void }
    def initialize(repo:, pull:, requestor:, request_id: nil)
      @repo = repo
      @pull = pull
      @requestor = requestor
      @pr_ref = T.must(Copilot::PullRequests::CodeReviewReferenceSerializer.new.to_hash(pull, include_diff: true, include_full_files: true))
      @request_id = request_id
    end

    # Public: Generate a code review from Copilot for the given pull request.
    # This assumes that feature flag and license checks have already passed.
    sig { returns(T::Boolean) }
    def generate
      return false if repo.nil? || requestor.nil? || pull.nil? || !requestor.user?
      # returning true here will prevent submitting a failed review
      return true unless active_review_request?

      log("Kicking off code review")
      GitHub.dogstats.increment("copilot.code_review.started")

      success = T.let(true, T::Boolean)
      lock_key = "CodeReviewGenerator_#{pull.id}_#{pull.head_sha}"
      restraint = GitHub::Restraint.new
      restraint.lock!(lock_key, CURRENT_JOBS, LOCK_TTL) do
        repo_owner = T.must(repo).owner
        raise NotFoundError, "repo_owner is missing" if repo_owner.nil?

        # Mint a copilot chat app token so we can invoke CAPI on behalf of the user
        new_access = copilot_pull_request_reviewer_app.grant(requestor, entry_point: :copilot_code_review_generator_generate_access)

        # Need to be in a writing role to update oauth access
        access = ActiveRecord::Base.connected_to(role: :writing) do
          # Check if SAML would be enforced for this repository and if so create a credential authorization grant for them.
          # This should be safe to do because all mechanisms to trigger this secret provider already go through appropriate SAML CAP filtering
          # either in the API or in the Rails controllers (ex: assigning an issue to Copilot).
          if repo_owner.organization? && Organization::SamlEnforcementPolicy.new(organization: repo_owner, user: requestor).enforced?
            if !Organization::CredentialAuthorization.by_organization_credential(organization: repo_owner, credential: new_access).active.exists?
              authorization = Organization::CredentialAuthorization.grant(organization: repo_owner, credential: new_access, actor: requestor)
              raise GetSecretsError, "Could not create credential authorization grant. Org: #{repo_owner.id}, user: #{requestor.id}" if authorization.nil?
            end
          end

          scoped_access, error = copilot_pull_request_reviewer_app.grant_scoped_access_from(
            new_access,
            repo_owner,
            permissions: {
              "metadata" => :read,
              "contents" => :read,
            },
            resources: {
              repository_ids: [T.must(repo).id],
            },
            entry_point: :copilot_code_review_generator_generate_scoped_access,
          )
          if error
            raise GetSecretsError, error
          end
          scoped_access
        end

        capi_access, _ = access.redeem(extended_expiry: true)
        token = Copilot::DecryptedToken.from(capi_access)

        capi = Copilot::User::CopilotApi.new(
          requestor,
          integration_id: CopilotAPI::COPILOT_PR_REVIEWS_INTEGRATION_ID,
          session: nil, # There won't ever be a user session
          real_ip: nil, # Same as above
          token:,
          request_id: @request_id,
        )

        log("making request to CAPI")

        experiment_headers = {}

        # not a true "experiment", added this way to avoid further parameter drilling
        if FeatureFlag.vexi.enabled?(:copilot_code_reviews_create_session, repo, default: false) && active_review_request?
          experiment_headers["X-Copilot-Review-Request-Id"] = active_review_request.id
        end

        # for direct org billing we want to override the user setting with the org setting
        if FeatureFlag.vexi.enabled?(:copilot_code_review_beta_features_header, requestor, default: false) && billed_to_organization?(requestor, repo)
          experiment_headers["X-Copilot-Code-Review-Beta-Features"] = Copilot::Policies::CodeReviewBetaFeatures.enabled?(Copilot::Organization.new(repo.owner))
        end

        capi.create_code_review(
          references: code_review_references(pr_ref, repo),
          role: "user",
          experiment_headers: experiment_headers,
          interaction_id: generate_interaction_id,
          interaction_type: INTERACTION_TYPE_SLUG,
          initiator: INITIATOR_SLUG,
          snippy_token:,
        )

        log("review request enqueued")
        GitHub.dogstats.increment("copilot.code_review.enqueued")

        true
      end
    rescue GitHub::Restraint::UnableToLock
      log("Unable to lock. Restraint on #{lock_key} already exists")
      # return true to prevent submitting a failed review
      true
    end

    sig { params(reason: String).returns(T.untyped) }
    def submit_failed_review(reason:)
      resp = { choices: nil, copilot_references: [] }

      submit_review(resp, return_with_error: true, error_reason: reason)
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
        "gh.repository.id" => repo.id,
        "gh.repository.nwo" => repo.name_with_display_owner,
        "gh.user.id" => requestor.id,
        "gh.user.login" => requestor.display_login,
        "gh.pull_request.id" => pull.id,
        "gh.pull_request.url" => pull.url,
        "gh.job.aqueduct_id" => GitHub.context[:aqueduct_job_id],
        "gh.request_id" => @request_id
      )
    end

    sig { params(resp: T.untyped, duplicate_comments: T.untyped, return_with_error: T::Boolean, error_reason: T.nilable(String)).returns(Symbol) }
    def submit_review(resp, duplicate_comments: nil, return_with_error: false, error_reason: nil)
      pr_comments = review_comments(resp)
      comments = filter_review_comments(pr_comments, duplicate_comments)

      has_previous_reviews = pull.reviews.copilot.any?

      if FeatureFlag.vexi.enabled?(:ccr_filter_comments_against_diffs_filter_config, @repo, @repo.owner, @requestor, default: false)
        comments = PullRequests::Copilot::CodeReview::Comments::Filter.new(comments:).
          with_filter(:diff_filter_config).
          filter!
      end

      ref_data = pr_ref[:data]
      commit_id = ref_data[:headRevision]
      diff_start_commit_oid = ref_data[:comparisonStartOID]
      diff_end_commit_oid = ref_data[:comparisonEndOID]
      diff_base_commit_oid = ref_data[:comparisonBaseOID]
      review_body_message = PullRequests::Copilot::ReviewBodyMessageGenerator.new(
        pull:,
        repo:,
        comments:,
        model_response: resp,
        requestor: requestor,
        ref_data: ref_data,
        has_previous_reviews:,
      ).create

      # make sure that the user didn't cancel their review request
      unless active_review_request?
        return :cancelled
      end

      review_event = review_submission_event(resp)
      creator_params = {
        pull:,
        repo:,
        commit_id:,
        comments:,
        diff_start_commit_oid:,
        diff_end_commit_oid:,
        diff_base_commit_oid:,
        body: review_body_message,
        return_with_error:,
        error_reason:,
      }
      creator_params[:review_event] = review_event if review_event != :comment

      status = PullRequests::Copilot::CodeReviewCreator.new(**creator_params).create

      if status
        :succeeded
      else
        :failed
      end
    end

    sig { params(resp: T.untyped).void }
    def submit_approval_readiness(resp)
      value = approval_readiness_value(resp)
      return if value.blank?

      review_event = review_submission_event(resp)
      message = approval_readiness_feedback_message(value:, review_event:)
      return if message.blank?

      merge_requirements_note = approval_readiness_feedback_merge_requirements_note(review_event)

      body = <<~MD
        > [!WARNING]
        > This is an internal experiment to assess Copilot's ability to auto-approve PRs. #{approval_readiness_feedback_prompt(review_event)} Feedback in [#f-ccr-auto-approve](https://github-grid.enterprise.slack.com/archives/C0ADRNUL5J7) is appreciated!

        #{message}
        #{merge_requirements_note.present? ? "\n#{merge_requirements_note}" : ""}
      MD

      ActiveRecord::Base.connected_to(role: :writing) do
        ::IssueComment.create(issue: @pull.issue, user: copilot_pull_request_reviewer_app.bot, body:)
      end
    end

    sig { params(value: String, review_event: Symbol).returns(T.nilable(String)) }
    def approval_readiness_feedback_message(value:, review_event:)
      # TODO: update the hydro payload to contain the enum value and not just the string from CCRA
      case review_event
      when :approve
        return "Copilot approved this PR because it assessed the PR as ready to approve and merge." if value == APPROVAL_READINESS_READY
      when :request_changes
        return "Copilot requested changes because it assessed this PR as not ready to approve — see review comments for details." if value == APPROVAL_READINESS_REQUIRES_CHANGES
      else
        case value
        when APPROVAL_READINESS_READY
          return "Copilot thinks this PR is ready to approve and merge."
        when APPROVAL_READINESS_REQUIRES_CHANGES
          return "Copilot thinks this PR is not ready to approve — see review comments for details."
        when APPROVAL_READINESS_TOO_COMPLEX
          return "This PR is too complex or risky for Copilot to approve: human review recommended."
        end
      end

      nil
    end

    sig { params(review_event: Symbol).returns(String) }
    def approval_readiness_feedback_prompt(review_event)
      case review_event
      when :approve
        "Please 👍 this comment if Copilot approved this pull request correctly and 👎 if not."
      when :request_changes
        "Please 👍 this comment if Copilot requested changes correctly and 👎 if not."
      else
        "Please 👍 this comment if the assessment below is correct and 👎 if not."
      end
    end

    sig { params(review_event: Symbol).returns(T.nilable(String)) }
    def approval_readiness_feedback_merge_requirements_note(review_event)
      return if copilot_review_counts_toward_merge_requirements?(review_event)

      case review_event
      when :approve
        "Note: this review does not count toward required approvals for merging."
      when :request_changes
        "Note: this review does not block merging by itself."
      end
    end

    sig { params(review_event: Symbol).returns(T::Boolean) }
    def copilot_review_counts_toward_merge_requirements?(review_event)
      bot = copilot_pull_request_reviewer_app.bot
      return false unless bot

      case review_event
      when :approve
        return true if repo.feature_enabled_for_repo_or_owner?(:ccr_copilot_qualified_approvals)
      when :request_changes
        return true if repo.feature_enabled_for_repo_or_owner?(:ccr_copilot_qualified_rejections)
      else
        return false
      end

      repo.async_pushable_by?(bot).sync
    end

    private

    attr_reader :repo, :pull, :pr_ref

    sig { params(resp: T.any(T.untyped, T.untyped)).returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
    def review_comments(resp)
      resp[:copilot_references].filter_map do |ref|
        next unless ref[:type] == "github.generated-pull-request-comment"
        # Data shape corresponds to https://github.com/github/copilot-code-review-agent/blob/main/internal/pkg/comment/pull_request_review.go
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

    # Merge coding guidelines, custom-instructions, and instructions.md
    sig { params(pr_ref: T::Hash[T.untyped, T.untyped], repo: Repository).returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
    def code_review_references(pr_ref, repo)
      references = [pr_ref]
      guidelines = Copilot::CodingGuideline.references_for(repo.id)
      references.concat(guidelines)

      return references unless repo_custom_instructions_feature_enabled?

      custom_instructions = PullRequests::Copilot::CodeReview::Reference::Generator.generate(pr_ref:, repository: repo)

      references.concat(custom_instructions)
    end

    def repo_custom_instructions_feature_enabled?
      Copilot::Public::User.new(@requestor).beta_features_github_chat_enabled? ||
        @requestor.feature_flag_enabled?(:copilot_code_review_repo_copilot_instructions, default: false)
    end

    def snippy_token
      return unless FeatureFlag.vexi.enabled?(
        "copilot-code-reviews-use-snippy-checking",
        repo,
        requestor,
        default: false,
      )

      copilot_user = Copilot::User.new(requestor)
      copilot_authorizer = copilot_user.copilot_authorizer_object_no_snippy
      envelope = Copilot::Envelope.new(copilot_authorizer, SNIPPY_AUTH_TOKEN_HEADERS)
      envelope.envelope[:token]
    end

    def filter_review_comments(pr_comments, duplicate_comments)
      return pr_comments if duplicate_comments.blank?

      pr_comments.reject { |comment| duplicate_comment?(comment, duplicate_comments) }
    end

    def duplicate_comment?(comment, duplicate_comments)
      return false if duplicate_comments.blank?

      comment_id = comment[:comment_identifier]
      duplicate_comments.any? { |dup_obj| dup_obj.key?(:comment_identifier) && dup_obj[:comment_identifier] == comment_id }
    end

    def billed_to_organization?(user, repo)
      return false unless repo.owner.organization?
      access = PullRequests::Copilot::CodeReviewAccess.new(actor: user, current_repository: repo)
      access.should_bill_to_organization?
    end

    def approval_readiness_value(resp)
      reference = resp[:copilot_references]&.find { |ref| ref[:type] == "github.pull-request-approval-readiness" }
      return nil unless reference.present?

      reference.dig(:data, :body)
    end

    def review_submission_event(resp)
      case approval_readiness_value(resp)
      when APPROVAL_READINESS_READY
        return :approve if auto_approve_reviews_enabled?
      when APPROVAL_READINESS_REQUIRES_CHANGES
        return :request_changes if auto_reject_reviews_enabled?
      end

      :comment
    end

    def approval_readiness_feature_enabled?
      FeatureFlag.vexi.enabled?(:ccr_show_merge_readiness, repo, repo.owner, default: false)
    end

    def auto_approve_reviews_enabled?
      approval_readiness_feature_enabled? &&
        FeatureFlag.vexi.enabled?(:ccr_auto_approve_reviews, repo, repo.owner, default: false) &&
        PullRequests::Copilot::CodeReviewRepositorySettings.has_auto_approve_enabled?(repository: repo)
    end

    def auto_reject_reviews_enabled?
      approval_readiness_feature_enabled? &&
        FeatureFlag.vexi.enabled?(:ccr_auto_reject_reviews, repo, repo.owner, default: false) &&
        PullRequests::Copilot::CodeReviewRepositorySettings.has_auto_reject_enabled?(repository: repo)
    end
  end
end
