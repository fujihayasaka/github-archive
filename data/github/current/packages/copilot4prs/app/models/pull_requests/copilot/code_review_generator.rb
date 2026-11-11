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
      return false if repo.nil? || requestor.nil? || pull.nil?
      # returning true here will prevent submitting a failed review
      return true unless active_review_request?

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

        true
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
        "gh.request_id" => @request_id
      )
    end

    sig { params(resp: T.untyped, duplicate_comments: T.untyped, return_with_error: T::Boolean).returns(Symbol) }
    def submit_review(resp, duplicate_comments: nil, return_with_error: false)
      pr_comments = review_comments(resp)
      filtered_review_comments = filter_review_comments(pr_comments, duplicate_comments)

      comments = FeatureFlag.vexi.enabled?(:ccr_remove_duplicate_comments, @requestor, default: false) ? filtered_review_comments : pr_comments
      has_previous_reviews = FeatureFlag.vexi.enabled?(:ccr_remove_duplicate_comments, @requestor, default: false) ? pull.reviews.copilot.any? : false

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

      status = PullRequests::Copilot::CodeReviewCreator.new(
        pull:,
        repo:,
        commit_id:,
        comments:,
        diff_start_commit_oid:,
        diff_end_commit_oid:,
        diff_base_commit_oid:,
        body: review_body_message,
        return_with_error:,
      ).create

      if status
        emit_persistence_metric(success: true)
        :succeeded
      else
        emit_persistence_metric(success: false)
        :failed
      end
    end

    private

    attr_reader :repo, :pull, :pr_ref

    sig { params(success: T::Boolean).void }
    def emit_persistence_metric(success:)
      GitHub.dogstats.increment("copilot.code_review.persistence", tags: ["success:#{success}"])
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

    # Merge coding guidelines, custom-instructions, and instructions.md
    sig { params(pr_ref: T::Hash[T.untyped, T.untyped], repo: Repository).returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
    def code_review_references(pr_ref, repo)
      references = [pr_ref]
      guidelines = Copilot::CodingGuideline.references_for(repo.id)
      references.concat(guidelines)

      # Add code review settings reference if tool selections are configured
      settings_ref = build_code_review_settings_reference
      if settings_ref.present?
        references << settings_ref
      end

      return references unless repo_custom_instructions_feature_enabled?

      custom_instructions = PullRequests::Copilot::CodeReview::Reference::Generator.generate(pr_ref:, repository: repo)
      references.concat(custom_instructions)
    end

    # Build code review settings ref based on branch rules
    # Returns nil which implies a default config (CodeQL only).
    sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def build_code_review_settings_reference
      # Get branch rule evaluator
      evaluator = @pull.base_branch_rule_evaluator
      return nil unless evaluator

      # Implys no settings override if the rule is disabled. Default config will be used.
      return nil unless evaluator.copilot_code_review_analysis_tools_enabled?

      # Map tool selections to code review settings
      settings = {
        type: "code-review-settings",
        disable_codeql: !evaluator.copilot_code_review_analysis_tools_codeql_enabled?,
        autovalidate_run_eslint: evaluator.copilot_code_review_analysis_tools_eslint_enabled?,
        autovalidate_run_pmd: evaluator.copilot_code_review_analysis_tools_pmd_enabled?,
      }

      {
        type: "github.code-review-settings",
        id: "code-review-settings (#{settings[:disable_codeql]}, #{settings[:autovalidate_run_eslint]}, #{settings[:autovalidate_run_pmd]})",
        data: settings,
      }
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
      return pr_comments unless FeatureFlag.vexi.enabled?(:ccr_remove_duplicate_comments, @requestor, default: false)

      pr_comments.reject { |comment| duplicate_comment?(comment, duplicate_comments) }
    end

    def duplicate_comment?(comment, duplicate_comments)
      return false unless FeatureFlag.vexi.enabled?(:ccr_remove_duplicate_comments, @requestor, default: false)

      return false if duplicate_comments.blank?

      comment_id = comment[:comment_identifier]
      duplicate_comments.any? { |dup_obj| dup_obj.key?(:comment_identifier) && dup_obj[:comment_identifier] == comment_id }
    end
  end
end
