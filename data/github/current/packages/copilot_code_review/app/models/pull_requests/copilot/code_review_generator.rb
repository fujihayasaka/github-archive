# typed: true
# frozen_string_literal: true

# NOTE: Changes to this file can not be tested in review-lab.
# Hydro message job workers in dotcom aren’t part of review lab deploys.
# As a result, review-lab will always call the production version of this file.

module PullRequests::Copilot
  class CodeReviewGenerator
    include GitHub::Memoizer

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
    SITE_SCOPED_INTEGRATION_INSTALLATION_PERMISSIONS = { "metadata" => :read, "contents" => :read }.freeze

    APPROVAL_READINESS_READY = "This pull request is ready to be approved."
    APPROVAL_READINESS_REQUIRES_CHANGES = "This pull request requires changes."
    APPROVAL_READINESS_TOO_COMPLEX = "This pull request is too complex or risky for automated approval."

    sig { returns User }
    attr_reader :requestor

    class GetSecretsError < StandardError; end
    class NotFoundError < StandardError; end
    class UnauthorizedError < StandardError; end

    # Public: Generate a code review from Copilot for the given pull request.
    # requestor - User manually requesting a review from Copilot, or PR author for automatic reviews.
    # allow_bot_requestor - When true, allows bot requestors (used for direct org billing).
    sig do
      params(
        repo: Repository,
        pull: PullRequest,
        requestor: User,
        allow_bot_requestor: T.nilable(T::Boolean),
        request_id: T.nilable(String)
      ).void
    end
    def initialize(repo:, pull:, requestor:, allow_bot_requestor: nil, request_id: nil)
      @repo = repo
      @pull = pull
      @requestor = requestor
      @pr_ref = T.must(Copilot::PullRequests::CodeReviewReferenceSerializer.new.to_hash(pull, include_diff: true, include_full_files: true))
      @request_id = request_id
      @allow_bot_requestor = !!allow_bot_requestor
    end

    # Public: Generate a code review from Copilot for the given pull request.
    # This assumes that feature flag and license checks have already passed.
    sig { returns(T::Boolean) }
    def generate
      return false if !requestor.user? && !@allow_bot_requestor
      # returning true here will prevent submitting a failed review
      return true unless active_review_request?

      log("Kicking off code review")
      generate_start_time = GitHub::Dogstats.monotonic_time
      generate_outcome = "error"
      GitHub.dogstats.increment("copilot.code_review.started")

      success = T.let(true, T::Boolean)
      lock_key = "CodeReviewGenerator_#{pull.id}_#{pull.head_sha}"
      restraint = GitHub::Restraint.new
      restraint.lock!(lock_key, CURRENT_JOBS, LOCK_TTL) do
        repo_owner = repo.owner
        raise NotFoundError, "repo_owner is missing" if repo_owner.nil?

        # When the requestor is a bot, use the PR author (or another human user) for OAuth token minting,
        # CAPI client, and per-user feature flag/billing checks, since OauthAccess requires a human user
        # and CAPI uses the user ID for auth/billing attribution. The requestor is kept for logging and
        # review attribution metadata only.
        grant_user = oauth_grant_user
        if grant_user.nil?
          GitHub.logger.warn("copilot_code_review_generate: No human user available for OAuth grant. Requestor: #{requestor.id}, PR author: #{pull.user&.id}",
            "gh.repository.id" => repo.id,
            "gh.repository.nwo" => repo.name_with_display_owner,
            "gh.pull_request.id" => pull.id,
          )
          GitHub.dogstats.increment("copilot.code_review.no_human_grant_user")
          generate_outcome = "no_human_grant_user"
          next false
        end

        capi_kwargs = build_capi_kwargs(pr_ref, repo)

        used_stateless = if OauthAccessTokens.domain.stateless_u2s_tokens_enabled?(repo, repo_owner)
          create_code_review_with_stateless_token(capi_kwargs, repo_owner: repo_owner, grant_user: grant_user)
        end

        unless used_stateless
          create_code_review_with_oauth_token(capi_kwargs, repo_owner: repo_owner, grant_user: grant_user)
        end

        dismiss_active_copilot_approvals! if auto_approve_reviews_enabled?

        log("review request enqueued")
        GitHub.dogstats.increment("copilot.code_review.enqueued")
        generate_outcome = "success"

        true
      end
    rescue GitHub::Restraint::UnableToLock
      log("Unable to lock. Restraint on #{lock_key} already exists")
      generate_outcome = "lock_contention"
      # return true to prevent submitting a failed review
      true
    ensure
      if generate_start_time
        GitHub.dogstats.distribution("copilot.code_review.generate.latency", GitHub::Dogstats.duration(generate_start_time), tags: ["outcome:#{generate_outcome}"])
      end
    end

    sig { params(reason: String, error_review_body: T.nilable(String)).returns(Symbol) }
    def submit_failed_review(reason:, error_review_body: nil)
      resp = { choices: nil, copilot_references: [] }

      submit_review(resp, return_with_error: true, error_reason: reason, error_review_body:)
    end

    sig { returns T.nilable(T::Boolean) }
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

    sig do
      params(
        resp: T.untyped,
        duplicate_comments: T.nilable(T::Array[CodeReview::DuplicationIdentifiers::Base::Duplicate]),
        return_with_error: T::Boolean,
        error_reason: T.nilable(String),
        error_review_body: T.nilable(String)
      ).returns(Symbol)
    end
    def submit_review(resp, duplicate_comments: nil, return_with_error: false, error_reason: nil, error_review_body: nil)
      pr_comments = review_comments(resp)
      comments = filter_review_comments(pr_comments, duplicate_comments)

      has_previous_reviews = if FeatureFlag.vexi.enabled?(:"ccr-has-previous-reviews-check", @requestor, default: false)
        pull.reviews.where(user: copilot_pull_request_reviewer_app.bot).any?
      else
        pull.reviews.copilot.any?
      end

      if FeatureFlag.vexi.enabled?(:ccr_filter_comments_against_diffs_filter_config, @repo, @repo.owner, oauth_grant_user, default: false)
        comments = PullRequests::Copilot::CodeReview::Comments::Filter.new(comments:).
          with_filter(:diff_filter_config).
          filter!
      end

      ref_data = pr_ref[:data]
      # Use the SHA that CCRA actually analyzed (carried in metadata) when
      # available, so comments anchor to the reviewed commit rather than
      # whatever the PR head happens to be now. This closes the race where a
      # push between review-start and comment-post misaligns comments.
      reviewed_sha = resp.dig(:metadata, :reviewed_commit_sha).presence
      commit_id = reviewed_sha || ref_data[:headRevision]
      diff_start_commit_oid = ref_data[:comparisonStartOID]
      diff_end_commit_oid = reviewed_sha || ref_data[:comparisonEndOID]
      diff_base_commit_oid = ref_data[:comparisonBaseOID]
      parsed_experiment_flags = experiment_flags(resp)
      review_event = review_submission_event(resp, experiment_flags: parsed_experiment_flags)
      inline_approval_readiness_reasoning =
        inline_approval_readiness_reasoning_enabled?(experiment_flags: parsed_experiment_flags) &&
        approval_readiness_code(resp).present?
      assessment_message = if inline_approval_readiness_reasoning
        approval_readiness_assessment_message(resp:, review_event:)
      end
      assessment_feedback_note = if inline_approval_readiness_reasoning && assessment_message.present?
        approval_readiness_assessment_feedback_note
      end
      review_body_message = PullRequests::Copilot::ReviewBodyMessageGenerator.new(
        pull:,
        repo:,
        comments:,
        model_response: resp,
        requestor: requestor,
        ref_data: ref_data,
        has_previous_reviews:,
        assessment_message:,
        assessment_feedback_note:,
        collapse_pr_overview: inline_approval_readiness_reasoning && assessment_message.present?,
      ).create

      # make sure that the user didn't cancel their review request
      unless active_review_request?
        return :cancelled
      end

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
        error_review_body:,
        response_request_id: response_request_id(resp),
        approval_readiness_code: approval_readiness_code(resp),
        experiment_flags: parsed_experiment_flags,
        experiment_assignment_context: experiment_assignment_context(resp),
        decision_assessment_required: decision_assessment_required(parsed_experiment_flags),
      }
      creator_params[:review_event] = review_event if review_event != :comment

      dismiss_active_copilot_approvals! if review_event == :approve

      status = PullRequests::Copilot::CodeReviewCreator.new(**creator_params).create

      if status
        sync_suggestions_to_head(reviewed_sha:)
        :succeeded
      else
        :failed
      end
    end

    sig { params(review_event: Symbol, review_counts_toward_merge_requirements: T::Boolean).returns(T.nilable(String)) }
    def approval_readiness_feedback_merge_requirements_note(review_event, review_counts_toward_merge_requirements: copilot_review_counts_toward_merge_requirements?(review_event))
      return if review_counts_toward_merge_requirements

      case review_event
      when :approve
        "Note: this review does not count toward required approvals for merging."
      end
    end

    sig { params(review_event: Symbol).returns(T::Boolean) }
    def copilot_review_counts_toward_merge_requirements?(review_event)
      bot = copilot_pull_request_reviewer_app.bot
      return false unless bot

      case review_event
      when :approve
        if copilot_qualified_approvals_enabled?
          return approval_policy.approval_counts_toward_merge_requirements_for_pull_request?(pull)
        end
      else
        return false
      end

      repo.async_pushable_by?(bot).sync
    end

    private

    sig { returns Repository }
    attr_reader :repo

    sig { returns PullRequest }
    attr_reader :pull

    sig { returns T::Hash[T.untyped, T.untyped] }
    attr_reader :pr_ref

    # Private: Attempts to create a Copilot code review using a stateless token. Returns a Boolean indicating success.
    sig do
      params(
        capi_kwargs: T::Hash[Symbol, T.untyped],
        repo_owner: T.any(User, Organization),
        grant_user: User
      ).returns(T::Boolean)
    end
    def create_code_review_with_stateless_token(capi_kwargs, repo_owner:, grant_user:)
      stateless_token = generate_stateless_u2s_token(repo_owner)
      unless stateless_token
        GitHub.dogstats.increment("copilot.code_review.token_type", tags: %w(type:stateless phase:issuance_failure))
        log("Stateless U2S token issuance failed, falling back to stateful token")
        return false
      end

      log("Attempting CAPI request with stateless U2S token")
      GitHub.dogstats.increment("copilot.code_review.token_type", tags: %w(type:stateless phase:attempt))
      capi = build_capi(grant_user, stateless_token)

      begin
        capi.create_code_review(**T.unsafe(capi_kwargs))
      rescue CopilotAPI::UnauthorizedError => e
        GitHub.dogstats.increment("copilot.code_review.token_type", tags: %w(type:stateless phase:capi_401))
        log("Stateless U2S token received 401 from CAPI, falling back to stateful token: #{e.message}")
        return false
      end

      GitHub.dogstats.increment("copilot.code_review.token_type", tags: %w(type:stateless phase:success))
      true
    rescue GetSecretsError => e
      GitHub.dogstats.increment("copilot.code_review.token_type", tags: %w(type:stateless phase:issuance_failure))
      log("Stateless U2S token setup failed, falling back to stateful token: #{e.message}")
      false
    end

    sig do
      params(capi_kwargs: T::Hash[Symbol, T.untyped], repo_owner: T.any(User, Organization), grant_user: User).void
    end
    def create_code_review_with_oauth_token(capi_kwargs, repo_owner:, grant_user:)
      token = generate_oauth_access_token(repo_owner, grant_user)
      log("Attempting CAPI request with OAuth token")
      GitHub.dogstats.increment("copilot.code_review.token_type", tags: %w(type:oauth phase:attempt))

      capi = build_capi(grant_user, token)
      capi.create_code_review(**T.unsafe(capi_kwargs))
      GitHub.dogstats.increment("copilot.code_review.token_type", tags: %w(type:oauth phase:success))
    end

    sig { returns(T::Boolean) }
    def copilot_qualified_approvals_enabled?
      repo.feature_enabled_for_repo_or_owner?(:ccr_copilot_qualified_approvals) ||
        FeatureFlag.vexi.enabled?(
          :ccr_force_copilot_qualified_approvals,
          repo,
          repo.owner,
          default: false,
        )
    end

    sig { params(repo_owner: T.any(User, Organization), user: User).returns(Copilot::DecryptedToken) }
    def generate_oauth_access_token(repo_owner, user)
      # Mint a copilot chat app token so we can invoke CAPI on behalf of the user
      new_access = copilot_pull_request_reviewer_app.grant(user, entry_point: :copilot_code_review_generator_generate_access)

      # Need to be in a writing role to update oauth access
      oauth_access = ActiveRecord::Base.connected_to(role: :writing) do
        # Check if SAML would be enforced for this repository and if so create a credential authorization grant for them.
        # This should be safe to do because all mechanisms to trigger this secret provider already go through appropriate SAML CAP filtering
        # either in the API or in the Rails controllers (ex: assigning an issue to Copilot).
        if saml_enforced_for?(repo_owner, user: user)
          if !Organization::CredentialAuthorization.by_organization_credential(organization: repo_owner, credential: new_access).active.exists?
            authorization = Organization::CredentialAuthorization.grant(organization: repo_owner, credential: new_access, actor: user)
            raise GetSecretsError, "Could not create credential authorization grant. Org: #{repo_owner.id}, user: #{user.id}" if authorization.nil?
          end
        end

        scoped_access, error = copilot_pull_request_reviewer_app.convert_to_scoped_access(
          new_access,
          repo_owner,
          permissions: {
            "metadata" => :read,
            "contents" => :read,
          },
          resources: {
            repository_ids: [repo.id],
          },
          entry_point: :copilot_code_review_generator_generate_scoped_access,
        )
        if error
          raise GetSecretsError, error
        end
        scoped_access
      end

      capi_access, _ = oauth_access.redeem(extended_expiry: true)
      Copilot::DecryptedToken.from(capi_access)
    end

    # Private: Finds or creates an OauthAuthorization for the requestor and the
    # copilot pull request reviewer app. Unlike the stateful flow, this
    # does not create an OauthAccess record.
    #
    # Checks for an existing authorization first (read replica) to avoid
    # unnecessary writes and side effects (e.g. MarketplaceOauthAppInstallJob).
    sig { returns OauthAuthorization }
    def find_or_create_oauth_authorization
      app = copilot_pull_request_reviewer_app

      existing = requestor.oauth_authorizations.github_apps.find_by(application_id: app.id)
      return existing if existing

      result = ActiveRecord::Base.connected_to(role: :writing) do
        OauthAuthorization::Creator.perform(
          user: requestor,
          application: app,
          integration_version_context: build_authorization_version_context(app),
        )
      end
      raise GetSecretsError, "Could not find or create OauthAuthorization: #{result.error}" if result.failed?

      result.authorization
    end

    # Private: Builds the integration_version_context required by OauthAuthorization::Creator
    # for the VersionReconciler. Since this is a new authorization (no existing version to
    # reconcile against), all three version slots use the app's latest version.
    sig { params(app: Integration).returns(T::Hash[Symbol, OauthAuthorization::VersionContext]) }
    def build_authorization_version_context(app)
      latest = app.latest_version
      version_context = OauthAuthorization::VersionContext.new(
        default_content_references: latest.default_content_references,
        default_events: latest.default_events,
        default_permissions: latest.default_permissions,
        number: latest.number,
        single_file_paths: latest.single_file_paths,
        user_permissions: latest.user_permissions,
      )

      { current_version: version_context, target_version: version_context, latest_version: version_context }
    end

    # Private: Attempts to issue a stateless user-to-server token via authnd for the CAPI request.
    #
    # Returns a token if issuance succeeded, else nil
    sig { params(repo_owner: T.any(User, Organization)).returns(T.nilable(Copilot::DecryptedToken)) }
    def generate_stateless_u2s_token(repo_owner)
      oauth_authorization = find_or_create_oauth_authorization
      scoped_installation = find_or_create_scoped_integration_installation(repo_owner)

      stateless_result = OauthAccessTokens.domain.create_stateless_u2s_token(
        actor_id: requestor.id,
        authorization_id: oauth_authorization.id,
        scoped_installation_id: scoped_installation.id,
        integration: copilot_pull_request_reviewer_app,
        expires_at: Apps::Privileged::CopilotPullRequestReviewer::MAX_SESSION_TIME.seconds.from_now,
      )

      unless stateless_result.ok?
        GitHub.dogstats.increment("copilot.code_review.stateless_u2s_token", tags: %w(result:failure reason:issuance))
        err_msg = stateless_result.error&.message
        log("Stateless U2S token issuance failed, falling back to stateful token: #{err_msg}, " \
          "repo: #{repo.id} (#{repo.name_with_display_owner})")
        return nil
      end

      token_result = stateless_result.unwrap!
      ghu_token = token_result.token

      if saml_enforced_for?(repo_owner)
        return nil unless find_or_create_credential_authorization_for_stateless_token(repo_owner, token_result)
      end

      GitHub.dogstats.increment("copilot.code_review.stateless_u2s_token", tags: %w(result:success))
      GitHub.context.push(copilot_code_review_token_type: "stateless_u2s")
      log("Using stateless U2S token for repo: #{repo.id} (#{repo.name_with_display_owner})")
      Copilot::DecryptedToken.from(ghu_token)
    end

    # Private: Creates a SiteScopedIntegrationInstallation for the Copilot pull request
    # reviewer app, scoped to the given repo. The Copilot PR reviewer app is
    # globally installed, so we use SiteScopedIntegrationInstallation::Creator.
    sig { params(repo_owner: T.any(User, Organization)).returns(SiteScopedIntegrationInstallation) }
    def find_or_create_scoped_integration_installation(repo_owner)
      result = ActiveRecord::Base.connected_to(role: :writing) do
        SiteScopedIntegrationInstallation::Creator.perform(
          copilot_pull_request_reviewer_app,
          repo_owner,
          repositories: [repo],
          permissions: SITE_SCOPED_INTEGRATION_INSTALLATION_PERMISSIONS,
          entry_point: :copilot_code_review_generator_stateless_token,
        )
      end
      raise GetSecretsError, "Failed to create scoped installation: #{result.error}" if result.failed?

      result.installation
    end

    # Private: Creates an Organization::CredentialAuthorization for a stateless JSON web token.
    # Unlike the stateful flow, the jti from the token is stored in the jti column for identification.
    #
    # Returns the credential authorization, or nil on failure.
    sig do
      params(
        repo_owner: T.any(User, Organization),
        token_result: OauthAccessTokens::Domain::StatelessTokenResult
      ).returns(T.nilable(Organization::CredentialAuthorization))
    end
    def find_or_create_credential_authorization_for_stateless_token(repo_owner, token_result)
      existing = Organization::CredentialAuthorization.active.by_organization(organization: repo_owner)
        .by_credential(credential: token_result)
        .by_actor(actor: requestor).first
      if existing # the JWT has already been used
        GitHub.dogstats.increment("copilot.code_review.stateless_u2s_token",
          tags: %w(result:failure reason:jwt_already_used))
        return nil
      end

      authorization = ActiveRecord::Base.connected_to(role: :writing) do
        Organization::CredentialAuthorization.grant(organization: repo_owner, credential: token_result,
          actor: requestor)
      end
      unless authorization.present?
        GitHub.dogstats.increment("copilot.code_review.stateless_u2s_token",
          tags: %w(result:failure reason:credential_authorization_grant_failure))
        return nil
      end

      authorization
    end

    sig { params(repo_owner: T.any(User, Organization), user: User).returns(T::Boolean) }
    def saml_enforced_for?(repo_owner, user: requestor)
      return false unless repo_owner.organization?
      Organization::SamlEnforcementPolicy.new(organization: repo_owner, user: user).enforced?
    end

    # Private: Builds a CopilotApi client for making CAPI requests with the given token.
    sig do
      params(grant_user: User, token: T.any(Copilot::DecryptedToken, Copilot::EncryptedToken))
        .returns(Copilot::User::CopilotApi)
    end
    def build_capi(grant_user, token)
      Copilot::User::CopilotApi.new(grant_user,
        integration_id: CopilotAPI::COPILOT_PR_REVIEWS_INTEGRATION_ID,
        session: nil, # There won't ever be a user session
        real_ip: nil, # Same as above
        token: token,
        request_id: @request_id,
      )
    end

    # Private: Builds the keyword arguments for the CopilotApi client, including experiment headers.
    # Extracted so the call can be retried with a different token without re-computing these values.
    sig { params(pr_ref: T::Hash[T.untyped, T.untyped], repo: Repository).returns(T::Hash[Symbol, T.untyped]) }
    def build_capi_kwargs(pr_ref, repo)
      experiment_headers = {}

      if active_review_request?
        experiment_headers["X-Copilot-Review-Request-Id"] = T.must(active_review_request).id
      end

      # Resolve preview opt-in against the repo's preview-policy authority
      # (the owning org for org-owned repos, the owning user for user-owned
      # repos) and send it as the `X-Copilot-Code-Review-Beta-Features` header.
      # Without this header, copilot-api falls back to the actor's
      # user-aggregated `CodeReviewBetaFeaturesSetting`, which is true whenever
      # ANY of the user's Copilot grants enables preview — letting a seat from
      # another org/enterprise leak preview-feature access into a repo whose
      # owning org has the policy disabled.
      #
      # `preview_features_enabled_for_repo?` is the same helper used below for
      # the effort-level gate, and intentionally dispatches on `repo.owner`
      # (not `repo.in_organization?`) so user-owned private forks of org repos
      # consult the owning user's policy rather than the inherited parent org.
      experiment_headers["X-Copilot-Code-Review-Beta-Features"] = Copilot::CodeReview::Features.preview_features_enabled_for_repo?(repo)

      mcp_ff_enabled = FeatureFlag.vexi.enabled?("copilot-code-reviews-enable-mcp-proxy", repo, repo.owner, default: false)
      effort_level_enabled = Copilot::CodeReview::Features.preview_features_enabled_for_repo?(repo)

      # Read the (at most one) settings row for this repo and derive both headers
      # from it. The table's unique index is on `repository_id` alone, so there
      # is exactly zero or one row per repo. `pick` returns `[mcp_enabled, effort_level]`
      # for the row, or `nil` when no row exists.
      if mcp_ff_enabled || effort_level_enabled
        row = PullRequests::Copilot::CodeReviewRepositorySettings
          .where(repository: repo)
          .pick(:repo_mcp_enabled, :repo_review_effort_level)

        if mcp_ff_enabled
          # MCP is disabled only when the repo has explicitly turned it off.
          # If no row exists, MCP defaults to enabled.
          experiment_headers["X-Copilot-Code-Review-Mcp-Enabled"] = row.nil? || row.first != false
        end

        if effort_level_enabled
          # The column defaults to "unknown" (integer 0) for any row created
          # as a side-effect of toggling an unrelated setting like MCP, so we
          # treat that as "no preference" and skip the header. The agent uses
          # "low" as its default behavior when the header is absent, so omitting
          # it is semantically correct.
          effort_level = row&.last
          if effort_level.present? && effort_level != "unknown"
            experiment_headers["X-Copilot-Code-Review-Effort-Level"] = effort_level
          end
        end
      end

      {
        references: code_review_references(pr_ref, repo),
        role: "user",
        experiment_headers: experiment_headers,
        interaction_id: generate_interaction_id,
        interaction_type: INTERACTION_TYPE_SLUG,
        initiator: INITIATOR_SLUG,
        snippy_token: snippy_token(T.must(oauth_grant_user)),
      }
    end

    sig { params(resp: T.untyped).returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
    def review_comments(resp)
      resp[:copilot_references].filter_map do |ref|
        next unless ref[:type] == "github.generated-pull-request-comment"
        # Data shape corresponds to https://github.com/github/copilot-code-review-agent/blob/main/internal/pkg/comment/pull_request_review.go
        # path, line, body, side, problem_type, guideline_id
        ref[:data]
      end
    end

    sig { params(resp: T.untyped).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def experiment_flags(resp)
      raw = resp[:experiment_flags]
      return nil unless raw.present?

      raw.to_h.deep_symbolize_keys.transform_values { |v| v == true || v.to_s == "true" }
    end

    sig { params(flags: T.nilable(T::Hash[Symbol, T.untyped])).returns(T::Boolean) }
    def decision_assessment_required(flags)
      flags&.fetch(:decision_assessment_required, false) == true
    end

    sig { params(resp: T.untyped).returns(T.nilable(String)) }
    def experiment_assignment_context(resp)
      raw = resp[:experiment_assignment_context]
      return nil if raw.blank?

      raw.to_s
    end

    sig { returns String }
    def generate_interaction_id
      SecureRandom.uuid
    end

    sig { returns Integration }
    def copilot_pull_request_reviewer_app
      return @app if defined?(@app)
      @app = ::Apps::Privileged.integration(:copilot_pull_request_reviewer)
    end

    sig { returns T::Boolean }
    def active_review_request?
      active_review_request.present?
    end

    sig { returns T.nilable(ReviewRequest) }
    memoize def active_review_request
      bot = copilot_pull_request_reviewer_app.bot
      review_request = @pull.direct_review_request_for(bot)
      GitHub.dogstats.increment("copilot_api.code_review.cancelled", tags: ["mode:review"]) if review_request.nil?

      review_request
    end

    # When the review was generated against an older commit, sync newly created
    # suggestions to the current HEAD so they are appliable or correctly marked
    # outdated without waiting for the next push-triggered sync.
    sig { params(reviewed_sha: T.nilable(String)).void }
    def sync_suggestions_to_head(reviewed_sha:)
      return if reviewed_sha.blank?
      return if reviewed_sha == pull.head_sha
      # Dedicated flag so this post-review sync trigger can be rolled out and
      # disabled independently of `automated_review_comment_outdated`, which
      # is fully shipped and gates the broader outdate behavior (including the
      # push-triggered sync path inside `mark_outdated_suggestions!` itself).
      return unless FeatureFlag.vexi.enabled?(:ccr_anchor_suggestions, repo, default: false)

      ActiveRecord::Base.connected_to(role: :writing) do
        PullRequests::CommentPosition::Synchronization
          .new(pull_request: pull, repository: repo)
          .mark_outdated_suggestions!(new_head_commit_oid: pull.head_sha)
      end
    rescue => e
      # Best-effort: don't fail the review if sync errors
      GitHub.logger.error(
        "Failed to sync suggestions to HEAD after stale review",
        "exception.message": e.message,
        "gh.pull_request.id": pull.id,
        "gh.reviewed_sha": reviewed_sha,
        "gh.head_sha": pull.head_sha,
      )
    end

    sig { void }
    def dismiss_active_copilot_approvals!
      bot = copilot_pull_request_reviewer_app.bot
      return if bot.nil?

      ActiveRecord::Base.connected_to(role: :writing) do
        pull.reviews
          .where(user_id: bot.id, state: PullRequestReview.state_value(:approved))
          .find_each do |review|
            T.unsafe(review).dismiss!(bot, message: "A newer Copilot review was requested.")
          end
      end
    end

    # Merge the pull request reference and custom instructions references.
    sig { params(pr_ref: T::Hash[T.untyped, T.untyped], repo: Repository).returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
    def code_review_references(pr_ref, repo)
      attach_comment_resolution_status!(pr_ref)

      references = [pr_ref]
      custom_instructions = PullRequests::Copilot::CodeReview::Reference::Generator.generate(pr_ref:, repository: repo)

      references.concat(custom_instructions)
    end


    # Attaches a `comments` map to the PR reference data hash when enabled.
    # Maps prior Copilot review comment IDs to `{ status, resolvedAt }`, derived from the
    # associated review thread's resolution/outdated state so CCRA can transition documents accordingly.
    sig { params(pr_ref: T::Hash[T.untyped, T.untyped]).void }
    def attach_comment_resolution_status!(pr_ref)
      return unless FeatureFlag.vexi.enabled?(
        :ccr_prior_aware_rereview,
        repo,
        default: false,
      )

      arcs = pull.automated_review_comments
        .source_copilot
        .where.not(pull_request_review_comment_id: nil)
        .includes(pull_request_review_comment: :pull_request_review_thread)
        .to_a

      return if arcs.empty?

      resolution_map = arcs.each_with_object({}) do |arc, map|
        comment = arc.pull_request_review_comment
        next unless comment

        thread = comment.pull_request_review_thread
        next unless thread

        status = if thread.resolved?
          "Resolved"
        elsif thread.outdated?
          "Outdated"
        else
          "Appliable"
        end

        entry = { status: status }
        entry[:resolvedAt] = thread.resolved_at.iso8601 if thread.resolved? && thread.resolved_at

        map[arc.pull_request_review_comment_id.to_s] = entry
      end

      data = pr_ref[:data] || pr_ref["data"]
      return unless data

      data[:comments] = resolution_map
    end

    def snippy_token(user = requestor)
      return unless FeatureFlag.vexi.enabled?(
        "copilot-code-reviews-use-snippy-checking",
        repo,
        user,
        default: false,
      )

      copilot_user = Copilot::User.new(user)
      copilot_authorizer = copilot_user.copilot_authorizer_object_no_snippy
      envelope = Copilot::Envelope.new(copilot_authorizer, SNIPPY_AUTH_TOKEN_HEADERS)
      envelope.envelope[:token]
    end

    sig do
      params(
        pr_comments: T::Array[T::Hash[T.untyped, T.untyped]],
        duplicate_comments: T.nilable(T::Array[CodeReview::DuplicationIdentifiers::Base::Duplicate])
      ).returns(T::Array[T::Hash[T.untyped, T.untyped]])
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

    # Returns a human user suitable for OAuth token minting.
    # Prefers the requestor if they are a human user; falls back to the PR author.
    # Returns nil if neither is a human user.
    sig { returns(T.nilable(User)) }
    memoize def oauth_grant_user
      return requestor if requestor.user?
      return pull.user if pull.user&.user?

      nil
    end

    def approval_readiness_value(resp)
      reference = approval_readiness_reference(resp)
      return nil unless reference.present?

      data_value(data_value(reference, :data), :body)
    end

    def approval_readiness_code(resp)
      structured_code = data_value(data_value(approval_readiness_reference(resp), :data), :approval_readiness_code).presence
      if structured_code.present?
        normalized_code = normalize_approval_readiness_code(structured_code)
        return normalized_code if normalized_code.present?
      end

      case approval_readiness_value(resp)
      when APPROVAL_READINESS_READY
        "ready"
      when APPROVAL_READINESS_REQUIRES_CHANGES
        "requires_changes"
      when APPROVAL_READINESS_TOO_COMPLEX
        "too_complex"
      end
    end

    def approval_readiness_reference(resp)
      data_value(resp, :copilot_references)&.find do |ref|
        data_value(ref, :type) == "github.pull-request-approval-readiness"
      end
    end

    def approval_readiness_reason(resp)
      data_value(data_value(approval_readiness_reference(resp), :data), :approval_readiness_reason).to_s.strip.presence
    end

    def normalize_approval_readiness_code(code)
      case code.to_s
      when "ready"
        "ready"
      when "requires_changes"
        "requires_changes"
      when "too_complex", "complex_or_risky"
        "too_complex"
      when "unknown"
        "unknown"
      end
    end

    def data_value(data, key)
      return nil unless data.respond_to?(:[])

      if data.respond_to?(:key?)
        return data[key] if data.key?(key)
        return data[key.to_s] if data.key?(key.to_s)
      end

      value = data[key]
      return value unless value.nil?

      data[key.to_s]
    end

    def approval_readiness_assessment_message(resp:, review_event:)
      code = approval_readiness_code(resp)
      return if code.blank?

      review_counts_toward_merge_requirements = copilot_review_counts_toward_merge_requirements?(review_event)
      message = approval_readiness_assessment_summary(
        code:,
        review_event:,
        review_counts_toward_merge_requirements:,
      )
      return if message.blank?

      reason = approval_readiness_reason(resp).presence
      merge_requirements_note = approval_readiness_feedback_merge_requirements_note(
        review_event,
        review_counts_toward_merge_requirements:,
      )

      parts = ["## #{message}"]
      parts << reason if reason.present?
      parts << merge_requirements_note if merge_requirements_note.present?

      parts.join("\n\n")
    end

    def approval_readiness_assessment_summary(code:, review_event:, review_counts_toward_merge_requirements: copilot_review_counts_toward_merge_requirements?(review_event))
      case code
      when "ready"
        return "✅ Approved" if review_event == :approve && review_counts_toward_merge_requirements

        "✅ Ready to approve"
      when "requires_changes"
        "⚠️ Not ready to approve"
      when "too_complex"
        "⚠️ Human review recommended"
      when "unknown"
        "ℹ️ Unable to assess"
      end
    end

    def approval_readiness_assessment_feedback_note
      <<~MD
        > [!NOTE]
        > Your feedback helps us improve the quality of this feature.
        > Please use 👍 or 👎 to tell us whether this assessment is correct.
      MD
    end

    # CopilotCodeReviewGenerated.metadata.request_id is the GitHub request id
    # from the CCR producer context, which downstream analytics join against.
    def response_request_id(resp)
      resp.dig(:metadata, :request_id).presence
    end

    sig { params(resp: T.untyped, experiment_flags: T.nilable(T::Hash[Symbol, T.untyped])).returns(Symbol) }
    def review_submission_event(resp, experiment_flags: nil)
      case approval_readiness_code(resp)
      when "ready"
        return :approve if auto_approve_reviews_experiment_enabled?(experiment_flags:)
        return :approve if auto_approve_reviews_enabled?
      end

      :comment
    end

    sig { params(experiment_flags: T.nilable(T::Hash[Symbol, T.untyped])).returns(T::Boolean) }
    def inline_approval_readiness_reasoning_enabled?(experiment_flags: nil)
      experiment_flags&.fetch(:inline_approval_readiness_reasoning, false) == true
    end

    sig { params(experiment_flags: T.nilable(T::Hash[Symbol, T.untyped])).returns(T::Boolean) }
    def auto_approve_reviews_experiment_enabled?(experiment_flags: nil)
      experiment_flags&.fetch(:auto_approve_reviews_experiment, false) == true
    end

    sig { returns T::Boolean }
    def auto_approve_reviews_enabled?
      return true if force_auto_approve_reviews_enabled? && force_auto_approve_reviews_allowed?
      broad_rollout_enabled = broad_auto_approval_rollout_enabled?

      return false unless broad_rollout_enabled
      return false unless private_repo_or_development?

      approval_policy.approval_enabled_for_runtime_rollout?
    end

    sig { returns T::Boolean }
    def broad_auto_approval_rollout_enabled?
      repo.feature_enabled_for_repo_or_owner?(:ccr_auto_approve_reviews)
    end

    sig { returns T::Boolean }
    memoize def force_auto_approve_reviews_enabled?
      FeatureFlag.vexi.enabled?(
        :ccr_force_auto_approve_reviews,
        repo,
        repo.owner,
        default: false,
      )
    end

    sig { returns T::Boolean }
    def force_auto_approve_reviews_allowed?
      private_repo_or_development?
    end

    sig { returns T::Boolean }
    def private_repo_or_development?
      !repo.public? || Rails.env.development?
    end

    memoize def approval_policy
      PullRequests::Copilot::QualifiedApprovalPolicy.new(repository: repo)
    end
  end
end
