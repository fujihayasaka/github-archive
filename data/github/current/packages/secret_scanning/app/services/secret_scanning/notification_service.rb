# typed: strict
# frozen_string_literal: true

module SecretScanning
  # NotificationService provides shared helpers for delivering secret scanning
  # email notifications and recording associated metrics.
  class NotificationService
    include SecretScanning::Features::FeatureFlagHelper

    METRIC_PREFIX = "secret_scanning.notification_service"

    sig { params(caller_namespace: String).void }
    def initialize(caller_namespace:)
      @caller_namespace = caller_namespace
    end

    # Returns true if any emails were queued, false otherwise.
    sig do
      params(
        repo: Repository,
        results: T::Array[T::Hash[Symbol, T.untyped]], # results: T::Array[Hydro::Schemas::Github::V1::TokenScanNotify::TokenGroup]
        subscribed_users: T::Array[User],
        scope: String,
        scan_count: Integer,
        business: T.nilable(Business),
      ).returns(T::Boolean)
    end
    def notify_secret_authors(repo, results, subscribed_users, scope, scan_count, business)
      return false unless [SecretScanningMailer::TOKEN_SCANNING_SCOPE[:commit_scoped],
        SecretScanningMailer::TOKEN_SCANNING_SCOPE[:bypassed_as_false_positive_scoped],
        SecretScanningMailer::TOKEN_SCANNING_SCOPE[:bypassed_as_used_in_tests_scoped],
        SecretScanningMailer::TOKEN_SCANNING_SCOPE[:bypassed_as_fix_later_scoped],
        SecretScanningMailer::TOKEN_SCANNING_SCOPE[:generic_secrets_commit_scoped]].include?(scope)

      token_results_by_author_email = T.let(Hash.new { |h, key| h[key] = [] }, T::Hash[String, T::Array[T::Hash[Symbol, T.untyped]]])
      results.each do |result|
        result[:tokens].each do |token|
          content_type = token[:first_location][:content_type]
          if content_type == :REPOSITORY_BLOB
            commit = fetch_commit(repo, token)
            commit&.author_emails&.each do |email|
              user = User.find_by_email(email, business: business)
              add_email(token_results_by_author_email, repo, user, email, result, subscribed_users)
            end
            next
          end
          if content_type == :WIKI_BLOB
            commit = fetch_wiki_commit(repo, token)
            commit&.author_emails&.each do |email|
              user = User.find_by_email(email, business: business)
              add_email(token_results_by_author_email, repo, user, email, result, subscribed_users)
            end
            next
          end

          content_number = token[:first_location][:content_number]
          content_id = token[:first_location][:content_id]
          user = case content_type
          when :ISSUE_TITLE, :ISSUE_BODY, :PULL_REQUEST_TITLE, :PULL_REQUEST_BODY
            repo.issues.find_by(number: content_number)&.user # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          when :ISSUE_COMMENT, :PULL_REQUEST_COMMENT
            IssueComments::Public.by_id(content_id, repository_id: repo.id)&.user
          when :PULL_REQUEST_REVIEW, :PULL_REQUEST_TIMELINE_COMMENT
            pr = repo.issues.find_by(number: content_number)
            T.must(pr.pull_request).reviews.find_by(id: content_id)&.user if pr
          when :PULL_REQUEST_REVIEW_COMMENT
            pr = repo.issues.find_by(number: content_number)
            repo.pull_request_review_comments.find_by(id: content_id)&.user if pr
          when :DISCUSSION_TITLE, :DISCUSSION_BODY
            repo.discussions.find_by(number: content_number)&.user
          when :DISCUSSION_COMMENT
            repo.discussion_comments.find_by(id: content_id)&.user
          end
          email = user&.emails&.verified&.first&.email
          add_email(token_results_by_author_email, repo, user, email, result, subscribed_users)
        end
      end

      if token_results_by_author_email.empty?
        GitHub.logger.info(
          "No commit authors to notify",
          "code.caller": @caller_namespace,
          "gh.repo.id": repo.id
        )
        return false
      end

      token_results_by_author_email.each do |email, author_results|
        SecretScanningMailer.secret_author_token_scanning_summary(repo, author_results, email, scope, scan_count, business).deliver_later
      end

      GitHub.logger.info(
        "Commit author summary emails queued for delivery",
        "code.caller": @caller_namespace,
        "gh.repo.id": repo.id
      )
      true
    end

    # Gets a Repository by its ID.
    # Uses the :repos_by_id_lib feature flag when available.
    # Logs and returns nil if the repository is not found.
    # Note: Caller is responsible for replica routing (e.g., with_read block in jobs).
    sig { params(repo_id: Integer).returns(T.nilable(Repository)) }
    def get_repo(repo_id)
      repo = if FeatureFlag.vexi.enabled?(:repos_by_id_lib, default: false)
        T.cast(Repositories.domain.by_id(repo_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
      else
        Repository.find_by(id: repo_id)
      end

      if repo.nil?
        GitHub.logger.info(
          "Repository not found, skipping message",
          "code.caller": @caller_namespace,
          "gh.repo.id": repo_id
        )
      end

      repo
    end

    # Gets the Business associated with a repository's owner.
    # Handles multi-tenant (Proxima) environments by unscoping the tenant context.
    sig { params(repo: Repository).returns(T.nilable(Business)) }
    def get_business(repo)
      business = if GitHub.multi_tenant_enterprise?
        GitHub::CurrentTenant.unscope { repo.owner&.business }
      else
        repo.owner&.business
      end

      business
    end

    # Filters users_to_notify for org or business backfill scans by removing
    # org/enterprise admins and security managers, so that only repo-level admins
    # receive the notification.
    #
    # Returns nil when the notification should be skipped entirely (e.g. user-owned
    # repos in an org backfill scan).
    # Returns the (possibly filtered) array otherwise.
    sig do
      params(
        users_to_notify: T::Array[User],
        repo: Repository,
        scope: String,
        scan_source: Symbol,
      ).returns(T.nilable(T::Array[User]))
    end
    def filter_users_for_backfill(users_to_notify, repo, scope, scan_source)
      is_repo_scope = scope == "repo" || scope == "generic_secrets_repo"
      is_org_or_enterprise_backfill_scan = is_repo_scope &&
        (scan_source == :SCAN_SOURCE_ORGANIZATION || scan_source == :SCAN_SOURCE_BUSINESS)

      # If we're sending the new joint email, we want to email repo admins only, not org/enterprise admins and security managers.
      # Therefore, remove them.

      # See `HydroSecretScanningJobGroupEventProcessorJob` for how we notify org/enterprise admins and security managers per
      # org/enterprise enablement.
      owner = repo.owner
      if is_org_or_enterprise_backfill_scan
        owner_admins = T.let([], T::Array[User])
        if owner.nil? || !owner.organization?
          # Noop and skip the rest of this logic.
          return
        elsif owner.business != nil
          owner_admins = ::SecretScanning::Features::Business::TokenScanning.new(owner.business).get_admins_to_notify
        elsif owner.is_a?(Organization)
          owner_admins = ::SecretScanning::Features::Org::TokenScanning.new(owner).get_admins_to_notify
        end
        users_to_notify = users_to_notify - owner_admins
      end

      users_to_notify
    end

    # Delivers a mail message and records delivery metrics.
    #
    # When mail is nil, emits a notification metric with success:false and reason:mailer_returned_nil,
    # then returns without delivering.
    sig { params(mail: T.untyped, metric_name: String, tags: T::Array[String]).void }
    def deliver_and_record(mail, metric_name:, tags:)
      if mail.nil?
        GitHub.logger.info(
          "Mailer returned nil, skipping delivery",
          "code.caller": @caller_namespace,
          "notification.metric_name": metric_name
        )
        GitHub.dogstats.increment(
          METRIC_PREFIX,
          tags: tags + ["success:false", "reason:mailer_returned_nil", "notification:#{metric_name}"]
        )
        return
      end

      mail.deliver_later
      GitHub.dogstats.increment(
        METRIC_PREFIX,
        tags: tags + ["success:true", "notification:#{metric_name}"]
      )
      GitHub.logger.info(
        "Email queued for delivery",
        "code.caller": @caller_namespace,
        "notification.metric_name": metric_name
      )
    end

    private

    sig do
      params(
        repo: Repository,
        token: T::Hash[Symbol, T.untyped]) # token: Hydro::Schemas::Github::V1::TokenScanNotify::TokenGroup::Token
        .returns(T.nilable(Commit))
    end
    def fetch_commit(repo, token)
      commit_oid = token[:first_location][:commit_oid]

      begin
        repo.commits.find(commit_oid)
      rescue GitRPC::InvalidObject,
             GitRPC::ObjectMissing,
             GitRPC::NetworkError,
             ArgumentError => e

        log_commit_fetch_error(e, repo, commit_oid, token, "fetch_commit", "Error retrieving commit for repo")
        nil
      end
    end

    sig do
      params(
        repo: Repository,
        token: T::Hash[Symbol, T.untyped]) # token: Hydro::Schemas::Github::V1::TokenScanNotify::TokenGroup::Token
        .returns(T.nilable(Commit))
    end
    def fetch_wiki_commit(repo, token)
      commit_oid = token[:first_location][:commit_oid]

      begin
        repo.find_wiki_commit(commit_oid)
      rescue GitRPC::InvalidObject,
             GitRPC::ObjectMissing,
             GitRPC::NetworkError,
             ArgumentError => e

        log_commit_fetch_error(e, repo, commit_oid, token, "fetch_wiki_commit", "Error retrieving commit for wiki")
        nil
      end
    end

    sig do params(
      token_results_by_author_email: T::Hash[String, T::Array[T::Hash[Symbol, T.untyped]]], # token_results_by_author_email: T::Hash[String, T::Array[Hydro::Schemas::Github::V1::TokenScanNotify::TokenGroup]]],
      repo: Repository,
      user: T.nilable(User),
      email: T.nilable(String),
      result: T::Hash[Symbol, T.untyped], # result: Hydro::Schemas::Github::V1::TokenScanNotify::TokenGroup
      subscribed_users: T::Array[User]).void
    end
    def add_email(token_results_by_author_email, repo, user, email, result, subscribed_users)
      return if email.nil? || user.nil?

      return if do_not_notify_author?(repo, user, email, subscribed_users)

      # token_results_by_author_email creates a default empty array for each key, so token_results_by_author_email[email] will never be nil
      token_results = T.must(token_results_by_author_email[email])

      # If a result has already been added, do not add it again.
      return if token_results.include?(result)

      token_results.push(result)
    end

    # 1) If the secret author is a subscribed user for the repo, do not notify.
    #    Subscribed users are repo admins, or are subscribed to security alerts via settings,
    #    and already receive notification emails for all secrets found in the repo.
    #
    # 2) Do not notify if the secret author's email is not verified.
    # 3) Do not notify if the secret author no longer has access to the repo.
    sig { params(repo: Repository, user: T.nilable(User), email: T.nilable(String), subscribed_users: T::Array[User]).returns(T::Boolean) }
    def do_not_notify_author?(repo, user, email, subscribed_users)
      return true unless user.present?
      # commit author was already added in token_scanning_users_to_notify
      return true if subscribed_users.include?(user)

      if user.is_enterprise_managed?
        email = user.add_emu_shortcode_to_emails(user.email)
      end

      # We only send emails to verified emails
      return true unless user.emails.where(email: email).first&.verified?

      # ensure user has access to the repo
      return true unless ::SecretScanning::AccessControl::CommitAuthorView.new(repo).has_access_to_repository?(user)

      # Always notify commit authors (unless they're already getting the admin email)
      false
    end

    sig do
      params(
        exception: StandardError,
        repo: Repository,
        commit_oid: String,
        token: T::Hash[Symbol, T.untyped],
        function_name: String,
        error_message: String
      ).void
    end
    def log_commit_fetch_error(exception, repo, commit_oid, token, function_name, error_message)
      GitHub.logger.error(
        error_message,
        "code.caller": @caller_namespace,
        "code.function": function_name,
        "gh.repo.id": repo.id,
        "commit_oid": commit_oid,
        "token_scan_result_number": token[:number],
        "exception.message": exception.message,
        "exception.type": exception.class.name
      )
    end
  end
end
