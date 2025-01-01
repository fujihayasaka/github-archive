# typed: true
# frozen_string_literal: true

require "monolith-twirp-dependabot-pullrequests"

module Api::Internal::Twirp::Dependabot
  module PullRequests
    module V1
      # Handler for MonolithTwirp::Dependabot::PullRequests::V1::PullRequestAPIService.
      class PullRequestApiHandler < Api::Internal::Twirp::Handler
        FILE_MODE = 0o100644
        SUBMODULE_MODE = 0o160000
        EXECUTABLE_MODE = 0o100755

        MAX_REVIEW_REQUEST_ATTEMPTS = 3
        REVIEWS_ALREADY_PENDING_REGEX = /can only have one pending request per pull request/.freeze
        MAX_LABEL_CREATION_ATTEMPTS = 3
        DUPLICATE_LABEL_ERROR_REGEX = /Name has already been taken/.freeze

        class Error < StandardError
          attr_reader :error_type
          def initialize(error_type, message = "")
            super(message)
            @error_type = error_type
          end
        end

        allow_access_for :client, allowed_clients: ["dependabot_api"]
        handles_service MonolithTwirp::Dependabot::PullRequests::V1::PullRequestAPIService
        connected_to_writing_for :publish_changes, :create_pull_request

        resolve_tenant_context do |req, _env|
          Repositories::Public.resolve_tenant(id: req.repository_id)
        rescue ActiveRecord::RecordNotFound => err
          Twirp::Error.not_found(err.message)
        end

        def before_rpc(rack_env, env)
          # proxy the remote ip from the rack environment hash to the request environment hash
          # so we can use it in reflog data
          env["api.remote_ip"] = rack_env["api.remote_ip"]
        end

        ErrorType = MonolithTwirp::Dependabot::PullRequests::V1::ErrorType
        EligibilityResult = MonolithTwirp::Dependabot::PullRequests::V1::CheckPullRequestEligibilityResponse::Result
        def check_pull_request_eligibility(req, env)
          return Twirp::Error.invalid_argument("must be provided", argument: "repository_id") unless req.repository_id.present? && req.repository_id.nonzero?
          return Twirp::Error.invalid_argument("must be provided", argument: "dependabot_branch_name") unless req.dependabot_branch_name.present?
          return Twirp::Error.invalid_argument("must be provided", argument: "base_commit_sha") unless req.base_commit_sha.present?
          return Twirp::Error.failed_precondition("Dependabot is not available") if GitHub.dependabot_github_app_bot.blank?

          repository = ensure_repository!(req:)
          dependabot_bot = ensure_dependabot!(repository:)

          GitHub.logger.info(
            "Checking pull request eligibility",
            "base_commit_sha": req.base_commit_sha,
            **log_telemetry_data(env, req.repository_id)
          )

          # If the job requires that the base commit from the job be up to date with the base branch and it is not,
          # then the job has created changes that are out of date
          # so we should abandon the updates
          base_branch = req.base_branch_name.present? ? req.base_branch_name : repository.default_branch
          head_commit_for_base_branch = repository.heads.find(base_branch).sha
          if req.require_up_to_date_base && head_commit_for_base_branch != req.base_commit_sha
            return { result: EligibilityResult::RESULT_BASE_NOT_UP_TO_DATE }
          end

          # If the branch does not yet exist, then we can create the branch and PR without any issues
          existing_branch = repository.extended_refs.find("refs/heads/#{req.dependabot_branch_name}")
          if existing_branch.blank?
            return { result: EligibilityResult::RESULT_OK }
          end

          # If there is an open PR for the branch, then we should not try to recreate it
          open_prs = repository.pull_requests.
            filter_spam_for(dependabot_bot, skip_user_filter_if_not_spammy: true).
            for_head_repo_and_head_ref(repository, req.dependabot_branch_name).
            open_pulls
          if open_prs.any?
            return { result: EligibilityResult::RESULT_UNMERGED_PR_EXISTS }
          end

          # If the HEAD of the existing branch is the same as the base commit of the job,
          # then there is no new or novel commit on the branch
          # and we should be ok to write to it.
          head_commit = existing_branch.commit
          if head_commit.sha == req.base_commit_sha
            return { result: EligibilityResult::RESULT_OK }
          end

          # If the head commit is not authored by dependabot,
          # then it has user authored changes
          # so we should abandon the updates
          if head_commit.author_name != dependabot_bot.git_author_name ||
            head_commit.author_email != dependabot_bot.git_author_email
            return { result: EligibilityResult::RESULT_USER_EDITED_BRANCH_EXISTS }
          end

          # If the existing branch's HEAD does not include the base commit sha as a parent commit
          # then the changes on the existing branch are different from what a new Dependabot PR would contain
          # so we should abandon the updates
          if !head_commit.parent_oids.include?(req.base_commit_sha)
            return { result: EligibilityResult::RESULT_EXISTING_BRANCH_HAS_MULTIPLE_COMMITS }
          end

          # All checks passed, we can overwrite the branch and create the PR
          { result: EligibilityResult::RESULT_OK }
        rescue Error => err
          log_error(err, env, req.repository_id)
          { error: { type: err.error_type, message: err.message } }
        rescue StandardError => err
          log_error(err, env, req.repository_id)
          {
            error: {
              type: ErrorType::ERROR_TYPE_UNEXPECTED_ERROR,
              message: err.message
            }
          }
        end

        def publish_changes(req, env)
          return Twirp::Error.invalid_argument("must be provided", argument: "repository_id") unless req.repository_id.present? && req.repository_id.nonzero?
          return Twirp::Error.invalid_argument("must be provided", argument: "dependabot_branch_name") unless req.dependabot_branch_name.present?
          return Twirp::Error.invalid_argument("must be provided", argument: "base_commit_sha") unless req.base_commit_sha.present?
          return Twirp::Error.invalid_argument("must be provided", argument: "commit_message") unless req.commit_message.present?
          return Twirp::Error.invalid_argument("must be provided", argument: "dependency_files") unless req.dependency_files.present?
          return Twirp::Error.failed_precondition("Dependabot is not available") if GitHub.dependabot_github_app_bot.blank?

          repository = ensure_repository!(req:)
          @dependabot_bot = ensure_dependabot!(repository:)

          GitHub.logger.info(
            "Publishing changes",
            "base_commit_sha": req.base_commit_sha,
            **log_telemetry_data(env, req.repository_id)
          )

          commit = create_commit(req:, repository:)

          branch_name = req.dependabot_branch_name
          ref_name = "refs/heads/#{branch_name}"
          reflog_data = request_reflog_data(repository, "Dependabot create refs api", env)
          begin
            create_or_update_branch(repository:, ref_name:, commit:, reflog_data:)
          rescue Git::Ref::UpdateFailedSensitive => err
            # Branch creation will fail if a branch called `dependabot` already
            # exists, since git won't be able to create a dir with the same name
            raise unless err.message.include?("cannot lock ref")

            branch_name = "#{SecureRandom.hex[0..3]}#{branch_name}"
            ref_name = "refs/heads/#{branch_name}"
            create_or_update_branch(repository:, ref_name:, commit:, reflog_data:)
          end

          # return a hash representation of MonolithTwirp::Dependabot::PullRequests::V1::PublishChangesResponse
          { repository_id: req.repository_id, commit_sha: commit.sha, branch_name: }
        rescue Git::Ref::ProtectedBranchUpdateError => err
          {
            error: {
              type: ErrorType::ERROR_TYPE_PROTECTED_BRANCH_UPDATE,
              message: err.ui_message
            }
          }
        rescue Git::Ref::RepositoryRuleViolationError => err
          {
            error: {
              type: ErrorType::ERROR_TYPE_REPO_RULE_VIOLATION,
              message: err.rule_suite.failure_messages(prefix: nil, exclude_violations: true).join("\n")
            }
          }
        rescue GitRPC::RequestTooLarge => err
          log_error(err, env, req.repository_id)
          {
            error: {
              type: ErrorType::ERROR_TYPE_REQUEST_TOO_LARGE,
              message: "Request too large"
            }
          }
        rescue GitRPC::Error => err
          log_error(err, env, req.repository_id)
          original_error = err.original || err.cause || err
          {
            error: {
              type: ErrorType::ERROR_TYPE_GIT,
              message: original_error.class.name.demodulize
            }
          }
        rescue Error => err
          log_error(err, env, req.repository_id)
          { error: { type: err.error_type, message: err.message } }
        rescue StandardError => err
          log_error(err, env, req.repository_id)
          {
            error: {
              type: ErrorType::ERROR_TYPE_UNEXPECTED_ERROR,
              message: err.message
            }
          }
        end

        def create_pull_request(req, env)
          return Twirp::Error.invalid_argument("must be provided", argument: "repository_id") unless req.repository_id.present? && req.repository_id.nonzero?
          return Twirp::Error.invalid_argument("must be provided", argument: "head_branch_name") unless req.head_branch_name.present?
          return Twirp::Error.invalid_argument("must be provided", argument: "pr_name") unless req.pr_name.present?
          return Twirp::Error.invalid_argument("must be provided", argument: "pr_description") unless req.pr_description.present?
          return Twirp::Error.failed_precondition("Dependabot is not available") if GitHub.dependabot_github_app_bot.blank?

          repository = ensure_repository!(req:)
          @dependabot_bot = ensure_dependabot!(repository:)

          base_branch = req.base_branch_name.present? ? req.base_branch_name : repository.default_branch

          GitHub.logger.info(
            "Creating pull request",
            "head_sha": repository&.heads.find(req.head_branch_name)&.sha || "not found",
            "base_sha": repository&.heads.find(base_branch)&.sha || "not found",
            **log_telemetry_data(env, req.repository_id)
          )
          pull_request = PullRequest.create_for!(repository, {
            title: req.pr_name,
            head: req.head_branch_name,
            base: base_branch,
            body: req.pr_description,
            user: @dependabot_bot,
          })

          link_pr_to_rdu(repository, pull_request, req, env)

          comment = Dependabot::CommentService.new(pull_request:, dependabot_user: @dependabot_bot)
          add_reviewers_to_pr(repository:, pull_request:, comment:, reviewers: req.reviewers)
          add_assignees_to_pr(repository:, pull_request:, comment:, assignees: req.assignees)
          add_milestone_to_pr(repository:, pull_request:, comment:, milestone_number: req.milestone_number)
          add_labels(repository:, pull_request:, comment:, labels: req.labels)

          comment.post_comment_on_missing_data

          # return a hash representation of MonolithTwirp::Dependabot::PullRequests::V1::CreatePullRequestResponse
          {
            pull_request: {
              github_number: pull_request.number,
              repository_id: pull_request.repository_id,
            }
          }
        rescue ActiveRecord::RecordInvalid => err
          log_error(err, env, req.repository_id)

          error_type = if err.message =~ /#{GitHub::RateLimitedCreation::ERROR_MESSAGE}$/
            ErrorType::ERROR_TYPE_RATE_LIMITED
          else
            ErrorType::ERROR_TYPE_RECORD_INVALID
          end

          pull_request_response = nil
          if pull_request.present?
            pull_request_response = {
              github_number: pull_request.number,
              repository_id: pull_request.repository_id,
            }
          end
          {
            pull_request: pull_request_response,
            error: {
              type: error_type,
              message: "#{err.record.class} #{err.message}"
            }
          }
        rescue Error => err
          log_error(err, env, req.repository_id)
          pull_request_response = nil
          if pull_request.present?
            pull_request_response = {
              github_number: pull_request.number,
              repository_id: pull_request.repository_id,
            }
          end
          {
            pull_request: pull_request_response,
            error: {
              type: err.error_type,
              message: err.message
            }
          }
        rescue StandardError => err
          log_error(err, env, req.repository_id)
          pull_request_response = nil
          if pull_request.present?
            pull_request_response = {
              github_number: pull_request.number,
              repository_id: pull_request.repository_id,
            }
          end
          {
            pull_request: pull_request_response,
            error: {
              type: ErrorType::ERROR_TYPE_UNEXPECTED_ERROR,
              message: err.message
            }
          }
        end

        def get_pull_requests(req, env)
          return Twirp::Error.invalid_argument("must be provided", argument: "repository_id") unless req.repository_id.present? && req.repository_id.nonzero?
          return Twirp::Error.failed_precondition("Dependabot is not available") if GitHub.dependabot_github_app_bot.blank?

          repository = ensure_repository!(req:)
          service = Dependabot::PullRequestsService.new(
            repository:,
            dependabot_user: ensure_dependabot!(repository:)
          )

          prs = service.find_pull_requests(pr_numbers: req.github_pr_numbers.to_a, state: req.state, with_commits: true)
          pr_data = prs.map do |pr|
            has_user_commits = service.pr_has_user_commits?(pr:, include_skipped_commits: req.include_skipped_commits)
            {
              github_number: pr.number,
              repository_id: pr.repository_id,
              state: pr.state.to_s,
              has_user_commits: has_user_commits,
              head_sha: pr.head_sha,
              head_ref: pr.head_ref_name,
              base_sha: pr.base_sha,
              base_ref: pr.base_ref_name,
            }
          end

          # return a hash representation of MonolithTwirp::Dependabot::PullRequests::V1::GetPullRequestsResponse
          { pull_requests: pr_data }
        rescue Error => err
          log_error(err, env, req.repository_id)
          { error: { type: err.error_type, message: err.message } }
        rescue StandardError => err
          log_error(err, env, req.repository_id)
          {
            error: {
              type: ErrorType::ERROR_TYPE_UNEXPECTED_ERROR,
              message: err.message
            }
          }
        end

        private

        def ensure_repository!(req:)
          repository = ::Repositories::Public.find_active(req.repository_id)

          raise Error.new(ErrorType::ERROR_TYPE_REPO_NOT_FOUND) if repository.blank?
          raise Error.new(ErrorType::ERROR_TYPE_REPO_ARCHIVED) if repository.archived?
          raise Error.new(ErrorType::ERROR_TYPE_REPO_EMPTY) if repository.empty?
          raise Error.new(ErrorType::ERROR_TYPE_REPO_LOCKED) if repository.locked?
          if repository.access.disabled? || repository.network_broken? || repository.disabled?
            raise Error.new(ErrorType::ERROR_TYPE_REPO_DISABLED)
          end

          if GitHub.repository_quotas_enabled? && repository.above_lock_quota?
            raise Error.new(ErrorType::ERROR_TYPE_REPO_OVER_SIZE_QUOTA)
          end

          repository
        end

        def ensure_dependabot!(repository:)
          bot = IntegrationInstallations::Public.on_repository(GitHub.dependabot_github_app, repository)&.bot
          raise Error.new(ErrorType::ERROR_TYPE_DEPENDABOT_NOT_INSTALLED) if bot.blank?

          if !repository.resources.contents.writable_by?(bot)
            raise Error.new(ErrorType::ERROR_TYPE_DEPENDABOT_CANNOT_WRITE)
          end

          bot
        end

        def log_error(err, env, repository_id, **extra_data)
          GitHub.logger.error(
            {
              message: "Error in Dependabot Pull Request API",
              exception: err,
              stacktrace: readable_stacktrace(err.backtrace || caller),
              **log_telemetry_data(env, repository_id),
            }.merge(extra_data),
          )
        end

        def readable_stacktrace(stacktrace)
          return "" if stacktrace.blank?

          stacktrace.
            reject { |line| line.include?("/gems/") }. # remove lines that are in gems
            map { |line| line.gsub(Rails.root.to_s, "") }. # remove the Rails root path
            first(10).
            join("\n")
        end

        def log_telemetry_data(env, repository_id)
          {
            "code.namespace": self.class.name,
            "code.function": env[:rpc_method],
            "gh.repo.id": repository_id,
            "gh.current_tenant.id": GitHub::CurrentTenant.get&.id || 0,
            "gh.current_tenant.slug": GitHub::CurrentTenant.get&.slug || "",
          }
        end

        def add_labels(repository:, pull_request:, comment:, labels:)
          return unless labels.present?

          attempt_count = 0
          begin
            # Load all labels in a single query, case insensitive
            existing_labels = repository.labels.with_name(labels.map(&:name)).to_a
            existing_label_names = existing_labels.map(&:name)
            custom_labels, default_labels = labels.partition { |label| label.is_custom }

            # Comment about missing custom labels
            missing_custom_labels = custom_labels.reject do |label|
              existing_label_names.any? { |existing_label| existing_label.casecmp?(label.name) }
            end
            comment.missing_labels = missing_custom_labels.map(&:name)

            # Create missing "default" labels, if they have details
            labels_with_details = default_labels.select { |label| label.color.present? && label.description.present? }
            labels_to_create = labels_with_details.reject do |label|
              existing_label_names.any? { |existing_label| existing_label.casecmp?(label.name) }
            end
            created_labels = labels_to_create.map do |label|
              repository.labels.create(
                name: label.name,
                color: label.color,
                description: label.description,
              )
            end

            existing_labels.concat(created_labels)

            pull_request.issue&.add_labels(existing_labels)

            pull_request.save!
            pull_request.labels
          rescue ActiveRecord::RecordInvalid => err
            raise err unless err.message =~ DUPLICATE_LABEL_ERROR_REGEX
            raise err if attempt_count >= MAX_LABEL_CREATION_ATTEMPTS

            # We sometimes encounter race conditions in new-to-us repositories.
            # Let's make sure we have the most current state and try again.
            log_add_labels_retry(repository.id, attempt_count)
            attempt_count += 1
            repository.reload
            pull_request.reload

            retry
          end
        end

        def log_add_labels_retry(repository_id, attempt_count)
          GitHub.logger.info(
            "Retrying add labels",
            "attempt_count": attempt_count,
            "code.namespace": self.class.name,
            "code.function": "add_labels",
            "gh.repo.id": repository_id,
            "gh.current_tenant.id": GitHub::CurrentTenant.get&.id || 0,
            "gh.current_tenant.slug": GitHub::CurrentTenant.get&.slug || "",
          )
        end

        # Create a commit, checking for pre-commit rules.
        def create_commit(req:, repository:)
          # 1. Map files from request to a hash of path => data pairs to pass into create_tree_changes
          files = files_from_request(req:, repository:)

          author = dependabot_git_actor
          committer = GitHub.web_commit_signing_enabled? ? web_committer_git_actor : author

          # 2. Evaluate pre-blob and pre-commit rules
          rule_suite = RuleEngine::Evaluator.evaluate_pre_commit_rules(
            repository,
            req.base_commit_sha,
            @dependabot_bot,
            {
              message: req.commit_message,
              author_email: author.email,
              committer_email: committer.email,
              blobs: files.filter_map do |path, entry|
                next unless entry&.fetch("data", nil).present?
                [path, entry&.fetch("data", nil)]
              end.to_h,
            }
          )
          raise Git::Ref::RepositoryRuleViolationError.new(rule_suite) unless rule_suite.action_permitted?

          # 3. Create the commit
          sha = Repositories.domain.commits.create_tree_changes(
            repository:,
            parent_oids: [req.base_commit_sha],
            info: {
              "message" => req.commit_message,
              "author" => author.to_gitrpc_hash,
              "committer" => committer.to_gitrpc_hash,
            },
            files:,
            sign_commit: GitHub.web_commit_signing_enabled?,
            signature: nil
          )

          commit = Repositories.domain.commits.by_oid(repository: repository, commit_oid: sha)

          # 4. Update the rule suite with the new commit's oid
          if commit.present? && rule_suite.persisted?
            rule_suite.after_oid = commit.oid
            rule_suite.save!
          end

          commit
        end

        # Maps files from the request to a hash of path => data pairs accepted by create_tree_changes.
        def files_from_request(req:, repository:)
          req.dependency_files.each_with_object({}) do |f, hsh|
            path = Pathname.new(File.join(f.directory, f.name)).cleanpath.to_path
            path = path.delete_prefix("/") # Remove any leading slash

            hsh[path] = file_to_tree_entry(repository:, file: f)
          end
        end

        def file_to_tree_entry(repository:, file:)
          if invalid_file_type?(file)
            raise Error.new(ErrorType::ERROR_TYPE_UNEXPECTED_ERROR, "Unexpected file type: #{file.type}")
          elsif submodule?(file)
            # If the file is a submodule, set the oid for the tree entry to the submodule commit oid
            { "oid" => file.content, "mode" => SUBMODULE_MODE }
          elsif file.deleted
            # if mode is delete set the contents for the path to nil
            nil
          elsif binary_contents?(file)
            # if file is binary, create a blob (implementation in create_blob)
            mode = file.mode.present? ? file.mode.to_i(8) : FILE_MODE
            { "oid" => create_blob(repository, file.content), "mode" => mode }
          else
            mode = file.mode.present? ? file.mode.to_i(8) : FILE_MODE
            { "data" => file.content, "mode" => mode }
          end
        end

        def invalid_file_type?(dependency_file)
          [
            MonolithTwirp::Dependabot::PullRequests::V1::DependencyFile::Type::TYPE_INVALID,
            MonolithTwirp::Dependabot::PullRequests::V1::DependencyFile::Type.lookup(
              MonolithTwirp::Dependabot::PullRequests::V1::DependencyFile::Type::TYPE_INVALID,
            )
          ].include?(dependency_file.type)
        end

        def submodule?(dependency_file)
          [
            MonolithTwirp::Dependabot::PullRequests::V1::DependencyFile::Type::TYPE_SUBMODULE,
            MonolithTwirp::Dependabot::PullRequests::V1::DependencyFile::Type.lookup(
              MonolithTwirp::Dependabot::PullRequests::V1::DependencyFile::Type::TYPE_SUBMODULE,
            )
          ].include?(dependency_file.type)
        end

        def binary_contents?(dependency_file)
          [
            MonolithTwirp::Dependabot::PullRequests::V1::DependencyFile::ContentEncoding::CONTENT_ENCODING_BASE64,
            MonolithTwirp::Dependabot::PullRequests::V1::DependencyFile::ContentEncoding.lookup(
              MonolithTwirp::Dependabot::PullRequests::V1::DependencyFile::ContentEncoding::CONTENT_ENCODING_BASE64,
            )
          ].include?(dependency_file.content_encoding)
        end

        def create_blob(repository, content)
          content = Base64.decode64(content)
          event = RuleEngine::Events::PreBlobEvent.new(
            repository, @dependabot_bot, metadata: { blobs: { "" => content } }
          )
          rule_suite = T.must(RuleEngine::GenericEvaluator.evaluate_rules(event).first)

          raise Git::Ref::RepositoryRuleViolationError.new(rule_suite) unless rule_suite.action_permitted?

          repository.rpc.write_blob(content)
        end

        def create_or_update_branch(repository:, ref_name:, commit:, reflog_data:)
          ref = repository.extended_refs.find(ref_name)
          if ref
            ref.update(commit, @dependabot_bot, reflog_data:, force: true)
          else
            ref = repository.extended_refs.create(ref_name, commit, @dependabot_bot, reflog_data:)
          end

          ref
        end

        def link_pr_to_rdu(repository, pull_request, req, env)
          return unless req.has_dependabot_update_id?

          dependency_update = repository.dependency_updates.find_by(id: req.dependabot_update_id)
          if dependency_update.blank?
            GitHub.logger.error(
              {
                message: "Error in Dependabot Pull Request API",
                error: "Dependency update not found",
                **log_telemetry_data(env, repository.id),
              }
            )
            return
          end

          dependency_update.update(state: "complete")
          pull_request.update(dependency_updates: [dependency_update])
        end

        def add_reviewers_to_pr(repository:, pull_request:, comment:, reviewers:)
          return if reviewers.blank?

          attempt_count = 0
          begin
            users_to_add = []
            if reviewers.users.present?
              business = Repositories::Public.resolve_tenant(id: repository.id)
              users_to_add = User.where(display_login: reviewers.users.to_a, business_id: business&.id || 0)
            end
            allowed_user_ids = pull_request.available_review_user_ids(filter: users_to_add)
            allowed_users = users_to_add.select { |user| allowed_user_ids.include?(user.id) }
            comment.disallowed_users = Array(reviewers.users) - allowed_users.map(&:display_login)

            teams_to_add = []
            if reviewers.teams.present?
              teams_to_add = repository.teams(
                immediate_only: false,
                include_all_repo_roles: repository.owner&.feature_enabled?(:reviewer_teams_all_repo_role)
              ).where(slug: reviewers.teams.to_a)
            end
            allowed_teams = pull_request.available_review_teams(filter: teams_to_add)
            disallowed_teams = Array(reviewers.teams) - allowed_teams.map(&:slug)
            comment.disallowed_teams = disallowed_teams

            allowed_reviewers = allowed_users + allowed_teams
            return if allowed_reviewers.empty?

            return if pull_request.request_review_from(
              reviewers: allowed_reviewers, actor: @dependabot_bot, re_request: false, append: true
            )

            # Raise a record invalid failure if requesting reviews was not successful
            raise ActiveRecord::RecordInvalid.new(pull_request)
          rescue ActiveRecord::RecordInvalid => err

            # CODEOWNER reviews are requested via a background job, introducing a race condition
            # to retry if we get a unique constraint violation error
            raise err unless err.message =~ REVIEWS_ALREADY_PENDING_REGEX
            raise err if attempt_count >= MAX_REVIEW_REQUEST_ATTEMPTS

            log_review_request_retry(repository.id, attempt_count)
            attempt_count += 1

            pull_request.reload
            retry
          end
        end

        def log_review_request_retry(repository_id, attempt_count)
          GitHub.logger.info(
            "Retrying review request",
            "attempt_count": attempt_count,
            "code.namespace": self.class.name,
            "code.function": "add_reviewers_to_pr",
            "gh.repo.id": repository_id,
            "gh.current_tenant.id": GitHub::CurrentTenant.get&.id || 0,
            "gh.current_tenant.slug": GitHub::CurrentTenant.get&.slug || "",
          )
        end

        def add_assignees_to_pr(repository:, pull_request:, comment:, assignees:)
          return if assignees.blank?

          business = Repositories::Public.resolve_tenant(id: repository.id)
          users = User.where(display_login: assignees.to_a, business_id: business&.id || 0)
          # Follows the logic inside `available_assignee_ids` except is performant as we only look at the users we care about
          valid_ids = repository.user_ids_with_privileged_access(actor_ids_filter: users.map(&:id))
          valid_users, invalid_users = users.partition { |user| valid_ids.include?(user.id) }
          invalid_user_logins = invalid_users.map(&:display_login) + (assignees - users.map(&:display_login))
          comment.disallowed_assignees = invalid_user_logins

          issue = pull_request.issue

          # Used to respect blocks
          GitHub.context.push(actor_id: @dependabot_bot.id) do
            issue.modifying_user = @dependabot_bot
            issue.add_assignees(valid_users)
            issue.save!
          end
        end

        def add_milestone_to_pr(repository:, pull_request:, comment:, milestone_number:)
          return if milestone_number == 0

          milestone = repository.milestones.find_by_number(milestone_number)
          if milestone.present?
            pull_request.issue.milestone = milestone
            pull_request.issue.save!
          else
            comment.missing_milestone = true
          end
        end

        def request_reflog_data(repository, via, env)
          # name_with_owner and login are not used in the response therefore safe to use here.
          {
            real_ip: env["api.remote_ip"],
            repo_name: repository.name_with_owner, # rubocop:disable GitHub/DoNotAllowNameWithOwner
            repo_public: repository.public?,
            user_login: @dependabot_bot.login, # rubocop:disable GitHub/DoNotAllowLogin
            user_agent: "dependabot",
            from: GitHub.context[:from],
            via: via,
          }
        end

        def dependabot_git_actor
          GitActor.new(
            name: @dependabot_bot.git_author_name,
            email: @dependabot_bot.git_author_email,
            time: Time.zone.now.iso8601
          )
        end

        def web_committer_git_actor
          GitActor.new(
            name: GitHub.web_committer_name,
            email: GitHub.web_committer_email,
            time: Time.zone.now.iso8601
          )
        end
      end
    end
  end
end
