# frozen_string_literal: true

require "labelizer"
require_relative "lib/pull_request_query"
require_relative "default/error_handling"
require_relative "default/metrics"

module PrioritizedJobs
  module CreatePullRequestOnGitHub
    RETRY_LIMIT = 8
    BRANCH_NAME_MAX_LENGTH = 244
    BRANCH_NAME_PREFIX = "dependabot"
    COMMIT_SIGN_OFF = "\n\nSigned-off-by: dependabot[bot] <support@github.com>"
    MAX_PR_DESCRIPTION_LENGTH = 65_535
    MAX_PR_COMMIT_MESSAGE_LENGTH = 65_535 - COMMIT_SIGN_OFF.length

    # CreatePullRequestOnGitHub runs against a PendingPullRequest in :pending state.
    # Creates/updates a PullRequest on GitHub.
    # Transitions PendingPullRequest to :created or :abandoned
    #
    # This job is retried in the case of GitHub errors. As such, it needs to be
    # idempotent.
    #
    class Default < ApplicationJob # rubocop:disable Metrics/ClassLength
      include PrioritizedJobs::CreatePullRequestOnGitHub::Lib
      include ErrorHandling
      include Metrics

      queue_as :create_pull_request_p2

      # Rescue after all retries have failed, or when hitting
      # an unexpected/unhandled error scenario
      rescue_from(StandardError) do |error|
        next trace_missing_pending_pr(error) if pending_pr.nil?

        Dependabot::Logger.log_context(pending_pr.telemetry_attributes) do
          # Always run failure hooks when a PR has failed.
          run_failure_hooks(error)

          # Only push unexpected/unhandled errors to Sentry for review
          raise error unless RETRYABLE_EXCEPTIONS.include?(error.class)

          # Log handled errors to splunk and datadog
          Dependabot::Logger.log_exception(error, msg: "PR retries exhausted")
        end
      end

      default_retries_for_idempotent_jobs

      RETRYABLE_EXCEPTIONS = [
        RetryJobError,
        # The following errors should be removable once all Octokit calls are
        # removed from this job
        Excon::Error::Timeout, # Sometimes http requests time out
        Excon::Error::Socket,  # Sometimes http requests have network errors
        Net::ReadTimeout,      # Sometimes reading http chunks times out
        *GitHubHelpers::RETRYABLE_ERRORS,
        Octokit::Unauthorized, # Sometimes GitHub serves without explanation
        Octokit::Forbidden,    # Same as for Octokit::Unauthorized
      ].freeze

      # Retry over the next 2.5 hours, with exponential backoff
      T.unsafe(self).include ActiveJob::Retry.new(
        strategy: RateLimitBackoffStrategy.new(
          limit: RETRY_LIMIT,
          retryable_exceptions: RETRYABLE_EXCEPTIONS
        ),
        callback: proc do |e, _|
          if executions > 3
            self.queue_name = "create_pull_request_p3" # change queue on retry number 4
          end
          increment_metric(
            "create_pull_request.retry",
            tags: {
              retryable_error: e.class.name,
              queue: queue_name,
              attempts: executions,
            }
          )
          # logging as info since retry might be successful
          Dependabot::Logger.info(
            {
              msg: "Retrying PR creation",
              "exception.message": e.message,
              "exception.type": e.class.name,
              "code.namespace": self.class.name,
              **pending_pr.telemetry_attributes,
            }
          )
          next unless e.is_a?(Octokit::Unauthorized) || e.is_a?(Octokit::Forbidden)

          uncache_installation_client
        end,
      )

      def perform(pending_pr:)
        Dependabot::Exceptions.push(pending_pr.telemetry_attributes)

        @pending_pr = pending_pr
        @update_config = pending_pr.update_config
        @update_job = pending_pr.update_job
        @updated_dependencies = pending_pr.updated_dependencies

        # Ensure that updates that would be creating clashing changes on a branch
        # are not being processed concurrently.
        Restraints.for_branch_changes(repo: update_config.repo, branch_name: branch_namer.new_branch_name) do
          Dependabot::Logger.log_context(telemetry_attributes) do
            if pull_request_query.existing_pull_request.present?
              Dependabot::Logger.info("PR already exists: ##{pull_request_query.existing_pull_request.github_number}")
              increment_metric("create_pull_request.existing")
              return
            end

            Throttlers.pull_request.throttle do
              create_pull_request_on_github
            end
          end
        end
      end

      private

      attr_reader :pending_pr, :update_job, :update_config, :updated_dependencies

      def telemetry_attributes
        method_name = caller_locations(1, 1)&.first&.label || "unknown"
        pending_pr.telemetry_attributes.merge(
          "code.namespace" => "CreatePullRequestOnGitHub::Default",
          "code.function" => method_name,
        )
      end

      def create_pull_request_on_github # rubocop:disable Metrics/MethodLength
        increment_metric("create_pull_request.attempt")
        return if pr_being_updated && handle_update_to_existing_pr

        unless pending_pr.can_create_pull_request?
          raise HaltJobError.new(
            "Cannot create PR", reason: "cannot_create_pull_request"
          )
        end

        if open_pr_limit_exceeded?
          Dependabot::Logger.info("#{PendingPullRequest::LOG_PREFIX} open PR limit exceeded")
          increment_metric("create_pull_request.open_pr_limit_exceeded")
          raise FailJobError.new(
            "Open PR limit exceeded",
            reason: "open_pull_request_limit_exceeded",
            error_type: "open_pull_request_limit_exceeded"
          )
        end

        check_for_previous_dependency_updates_edited_by_user!
        check_pull_request_eligibility!

        pending_pr.updated_dependencies.each { |dep| remove_outdated_ignore_conditions(dep) }

        publish_response = publish_content
        create_pr(publish_response)
      rescue SynchronizeRepoStateError, *SynchronizeRepoState::HANDLED_ERRORS => e
        synchronize_repo_state(error: e)
      rescue FailJobError, HaltJobError => e
        run_failure_hooks(e)
      end

      def check_for_previous_dependency_updates_edited_by_user!
        # NOTE: This means there are existing open pull requests for the same
        # dependency which has been edited by someone other than dependabot. In
        # this case we comment on the old PR saying there's a newer version of
        # the dependency (we don't want to close and supersede the previous pr
        # like we would usually do if it wasn't edited)
        return unless open_dependabot_prs_for_previous_version_edited_by_user.any?

        comment_on_edited_prs(open_dependabot_prs_for_previous_version_edited_by_user)

        # NOTE: There should only be one edited PR, but even if we end up with
        # multiple only link to one, the subsequent retry should link to the remaining one
        edited_pull_request_id = open_dependabot_prs_for_previous_version_edited_by_user.first.id

        if open_dependabot_prs_for_previous_version_edited_by_user.count > 1
          Dependabot::Logger.info(
            msg: "multiple edited pull request detected for previous version",
            edited_pull_request_ids: open_dependabot_prs_for_previous_version_edited_by_user.map(&:id)
          )
        end

        increment_metric("create_pull_request.halt_previous_prs_edited_no_update")
        raise FailJobError.new(
          "Previous PRs that have edits would be closed by this PR",
          reason: "edited_pull_request_exists",
          error_type: "edited_pull_request_exists",
          error_details: {
            "edited-pull-request-id" => edited_pull_request_id,
            "updated-dependencies": pending_pr.updated_dependencies.map { |dep| { "dependency-name" => dep.name } },
          }
        )
      end

      def comment_on_edited_prs(edited_pull_requests)
        edited_pull_requests.each do |pr|
          old_comments = installation_github_client.issue_comments(
            pr.repo.github_id,
            pr.github_number,
          )

          next if old_comments.any? { |c| c.body.start_with?("A newer version of") }

          # The outdated PR is for the same version as this PR. This can happen
          # when there is a race to create this PR - correct behaviour is *not*
          # to comment on the PR.
          version = pr.updated_dependencies.first.version
          next if pending_pr.updated_dependencies.first.version == version

          create_edited_pr_comment(pr)
        end
      end

      def create_edited_pr_comment(pull_request)
        dependency_names =
          if pull_request.updated_dependencies.count > 1 then "these dependencies"
          else
            # zero-width space to ensure we don't @ mention a user in a comment
            pull_request.updated_dependencies.first.name.gsub("@", "@\u200B").encode("utf-8")
          end

        msg =
          "A newer version of #{dependency_names} exists, but since " \
          "this PR has been edited by someone other than Dependabot I haven't " \
          "updated it. You'll get a PR for the updated version as normal once " \
          "this PR is merged."
        CreateComment.new(pull_request: pull_request, comment_body: msg).run
      end

      def open_dependabot_prs_for_previous_version_edited_by_user
        # FIXME: Grouped- and single-updates should have separate strategies
        #
        # Much of the early-return logic that blocks creation will diverge for
        # groups. Rather than add complexity to this code, we should try to
        # create separate strategies for the 'pre-flight' checks for each.
        #
        # For now, we will ignore this issue.
        #
        # See: https://github.com/github/dependabot-updates/issues/3734
        return [] if pending_pr.grouped_update?

        @open_dependabot_prs_for_previous_version_edited_by_user ||=
          dependabot_prs_for_previous_version.select do |pr|
            pr_detail = open_dependabot_prs_for_previous_version.
                        find { |detail| detail.github_number == pr.github_number }

            # The outdated PR was somehow fetched from GitHub despite being closed.
            next if pr_detail.nil?
            next if pr_detail.state != "open"

            # The outdated PR has user edits / commits.
            pr_detail.has_user_commits
          end
      end

      def check_pull_request_eligibility!
        result = pull_requests_client.check_pull_request_eligibility(
          repo: update_config.repo,
          dependabot_branch_name: branch_namer.new_branch_name,
          base_commit_sha: update_job.base_commit_sha,
          base_branch_name: update_job.target_branch,
          require_up_to_date_base: require_up_to_date_base?,
        )

        handle_can_create_pull_request_result(result)
      rescue GitHub::Twirp::DependabotPullRequests::TwirpError => e
        handle_twirp_error(e)
      rescue GitHub::Twirp::DependabotPullRequests::ServiceError => e
        handle_api_error(e)
      end

      # rubocop:disable Metrics/MethodLength
      def handle_update_to_existing_pr
        previous_pr_dep_names =
          pr_being_updated.
          updated_dependencies.
          map(&:name)

        updated_pr_dep_names =
          updated_dependencies.
          map(&:name)

        existing_deps_set = Set.new(
          pr_being_updated.updated_dependencies.map do |dep|
            {
              "dependency-name" => dep.name,
              "dependency_version" => dep.version,
            }
          end,
        )

        updated_deps_set = Set.new(
          updated_dependencies.map do |dep|
            {
              "dependency-name" => dep.name,
              "dependency_version" => dep.version,
            }
          end,
        )

        unless existing_deps_set == updated_deps_set
          increment_metric(
            "create_pull_request.existing_pr_updated_deps_mismatch",
          )
        end

        unless previous_pr_dep_names.sort == updated_pr_dep_names.sort
          increment_metric(
            "create_pull_request.existing_pr_updated_deps_name_mismatch",
          )
          return false
        end

        increment_metric(
          "create_pull_request.update_existing_pr",
        )

        enqueue_update_to_existing_pr
        true
      end
      # rubocop:enable Metrics/MethodLength

      def enqueue_update_to_existing_pr
        pending_pull_request_update = PendingPullRequestUpdate.create!(
          pull_request: pr_being_updated,
          updated_base_commit_sha: update_job.base_commit_sha,
        )

        pending_pull_request_update.encrypted_dependency_files_blob.attach(
          io: StringIO.new(encrypted_dependency_files_blob),
          filename: pending_pull_request_update.id,
          content_type: "application/octet-stream",
          identify: false,
        )

        UpdatePullRequestJob.perform_later(
          update_job_id: update_job.id,
          pending_pull_request_update: pending_pull_request_update,
        )
      end

      def encrypted_dependency_files_blob
        token =
          Base64.strict_decode64(Prius.get(:temporary_file_encryption_key))
        encrypted_box = RbNaCl::SimpleBox.from_secret_key(token)

        serialized_files = pending_pr.updated_dependency_files.map(&:to_h).to_json
        Base64.strict_encode64(encrypted_box.encrypt(serialized_files))
      end

      def open_pr_limit_exceeded?
        return false if security_fix_or_update? # security fixes bypass limit

        # In a multi-ecosystem update, don't block the job based on the number of pending pull request objects.
        # A single PR on GitHub is opened for all pending PR objects on the related update jobs.
        return false if update_job.multi_ecosystem_update?

        limit = update_job.update_config.open_pull_requests_limit
        return false unless limit # unlimited

        # Are there too many PRs already?
        open_pr_count = update_job.update_config.pull_requests.open.count
        remaining_slots = limit - open_pr_count
        return true if remaining_slots <= 0

        # How many pending PRs could proceed? Backoff if this isn't one of them
        return false if update_job.pending_pull_requests.in_state(:pending).
                        order("id ASC").
                        limit(remaining_slots).
                        pluck(:id).
                        include?(pending_pr.id)

        raise RetryJobError.new("May exceed open PR limit", reason: "open_pull_request_limit_exceeded")
      end

      def security_fix_or_update?
        return true if update_job.security_updates_only?
        return true if pr_being_updated

        open_dependabot_prs_for_previous_version.any?
      end

      def pr_being_updated
        return unless update_job.pull_request_transition_id

        @pr_being_updated ||= update_job.pull_request_transition.pull_request
      end

      def open_dependabot_prs_for_previous_version
        return [] if dependabot_prs_for_previous_version.blank?

        @open_dependabot_prs_for_previous_version ||=
          begin
            pull_requests_client.get_pull_requests(
              repo: update_config.repo,
              github_pr_numbers: dependabot_prs_for_previous_version.map(&:github_number),
              state: "open",
              include_skipped_commits: false,
            )
          rescue GitHub::Twirp::DependabotPullRequests::TwirpError => e
            handle_twirp_error(e)
          rescue GitHub::Twirp::DependabotPullRequests::ServiceError => e
            handle_api_error(e)
          end
      end

      def dependabot_prs_for_previous_version
        @dependabot_prs_for_previous_version ||=
          pending_pr.updated_dependencies.flat_map do |dep|
            update_job.update_config.pull_requests.open.
              where(multiple_dependencies: false).
              joins(:updated_dependencies).
              where(updated_dependencies: { name: dep.name })
          end
      end

      def require_up_to_date_base?
        pull_request_query.existing_pull_requests.any? { |pr| pr.in_state?(:merged) }
      end

      def pull_request_query
        @pull_request_query ||= PullRequestQuery.new(
          update_job: @update_job,
          updated_dependencies: pending_pr.updated_dependencies
        )
      end

      def publish_content
        pull_requests_client.publish_changes(
          repo: update_config.repo,
          dependabot_branch_name: branch_namer.new_branch_name,
          base_commit_sha: update_job.base_commit_sha,
          commit_message:,
          dependency_files: pending_pr.updated_dependency_files,
        )
      rescue GitHub::Twirp::DependabotPullRequests::TwirpError => e
        handle_twirp_error(e)
      rescue GitHub::Twirp::DependabotPullRequests::ServiceError => e
        handle_api_error(e)
      end

      def commit_message
        commit_message = "#{pending_pr.message_data['commit_message']}#{commit_metadata}"
        commit_message.truncate(MAX_PR_COMMIT_MESSAGE_LENGTH) + COMMIT_SIGN_OFF
      end

      def create_pr(publish_response)
        github_pull_request = pull_requests_client.create_pull_request(
          repo: update_config.repo,
          base_branch_name: update_config.target_branch,
          head_branch_name: publish_response.branch_name,
          pr_name:,
          pr_description:,
          labels: labels,
          reviewers: reviewers,
          assignees: assignees,
          milestone_number: update_job.default_milestone,
          dependabot_update_id: update_job.github_request_id,
        )
        enqueue_create_pr_on_dependabot(github_pull_request)
      rescue GitHub::Twirp::DependabotPullRequests::TwirpError => e
        handle_twirp_error(e)
      rescue GitHub::Twirp::DependabotPullRequests::ServiceError => e
        # Dependabot may have hit an error annotating the PR after
        # it was created.  If that happens the created PR will be returned
        # from the API and attached to the error.  We should still create
        # the PR record in Dependabot's database if this happens.
        enqueue_create_pr_on_dependabot(e.pull_request) if e.pull_request_was_created?
        handle_api_error(e)
      end

      def reviewers
        # Reviewers functionality disabled - return empty reviewers
        {
          "reviewers" => [],
          "team_reviewers" => [],
        }
      end

      def assignees
        assignees = Array(update_job.default_assignees)
        update_job_multi_ecosystem_siblings_enqueued_together.each do |uj|
          assignees.concat(Array(uj.default_assignees))
        end
        assignees.uniq
      end

      def enqueue_create_pr_on_dependabot(github_pull_request)
        return if github_pull_request.nil?

        CreatePullRequestOnDependabot.perform_later(
          pending_pr: pending_pr,
          github_pull_request: github_pull_request.to_h,
        )
        increment_metric("create_pull_request.success")
      end

      def pr_name
        pending_pr.message_data["pr_title"]
      end

      def pr_description
        truncate("#{pending_pr.message_data['pr_body']}\n\n#{pr_message_footer}")
      end

      def truncate(message)
        # Limit PR description to MAX_PR_DESCRIPTION_LENGTH (65,536) characters
        # and truncate with message if over. The API limit is 262,144 bytes
        # (https://github.community/t/maximum-length-for-the-comment-body-in-issues-and-pr/148867/2).
        # As Ruby strings are UTF-8 encoded, this is a pessimistic limit: it
        # presumes the case where all characters are 4 bytes.
        pr_description = message.dup
        if pr_description && pr_description.length > MAX_PR_DESCRIPTION_LENGTH
          truncated_msg = "...\n\n_Description has been truncated_"
          truncate_length = MAX_PR_DESCRIPTION_LENGTH - truncated_msg.length
          pr_description = (pr_description[0, truncate_length] + truncated_msg)
        end
        pr_description
      end

      def commit_metadata
        metadata = YAML.dump(UpdatedDependenciesMetadataPresenter.new(
          updated_dependencies: pending_pr.updated_dependencies,
          security_updates_only: update_job.security_updates_only?,
          dependency_group: pending_pr.dependency_group,
        ).metadata)
        "\n\n#{metadata}..."
      end

      def pr_message_footer
        PullRequestFooter.new(
          update_job: update_job,
          updated_dependencies: pending_pr.updated_dependencies,
          outdated_ignore_conditions_removed: @outdated_ignore_conditions_removed,
          grouped_update: pending_pr.dependency_group.present?,
        ).footer_text
      end

      def branch_namer
        @branch_namer ||= T.let(
          Dependabot::PullRequestCreator::BranchNamer.new(
            dependencies: pending_pr.updated_dependencies,
            files: pending_pr.updated_dependency_files,
            target_branch: update_config.target_branch,
            dependency_group: pending_pr.dependency_group&.to_core,
            separator: update_config.pull_request_branch_name_separator,
            prefix: BRANCH_NAME_PREFIX,
            max_length: BRANCH_NAME_MAX_LENGTH,
            includes_security_fixes: false,
            multi_ecosystem_name: update_job.update_config.multi_ecosystem_config&.normalised_name,
          ),
          T.nilable(Dependabot::PullRequestCreator::BranchNamer)
        )
      end

      def remove_outdated_ignore_conditions(dependency)
        outdated_ignore_conditions =
          update_config.ignore_conditions.
          reject(&:from_config_file?).
          select { |ic| ic.dependency_name == dependency.name }.
          select { |ic| ic.includes?(dependency.previous_version) }

        @outdated_ignore_conditions_removed = outdated_ignore_conditions.any?
        # TODO: We should probably use a state machine for ignored updates
        outdated_ignore_conditions.each(&:destroy!)
      end

      def labels
        labels = Labelizer.new(
          update_config: update_config,
          dependencies: pending_pr.updated_dependencies,
        ).labels

        labels += multi_ecosystem_labels if update_job.multi_ecosystem_update?

        labels.uniq
      end

      def multi_ecosystem_labels
        update_job_multi_ecosystem_siblings_enqueued_together.flat_map do |uj|
          next [] if uj.pending_pull_requests.empty?

          Labelizer.new(
            update_config: uj.update_config,
            dependencies: uj.pending_pull_requests.first.updated_dependencies # only need label info
          ).labels
        end
      end

      def account
        @account ||= update_job.update_config.repo.account
      end

      def pull_requests_client
        @pull_requests_client ||=
          GitHub::Twirp::DependabotPullRequests.new(
            client: Dependabot::Application.github_twirp_client,
            tenant: update_config.account.tenant,
          )
      end

      def installation_github_client
        @installation_github_client ||=
          GitHubHelpers::ClientWithRetries.new(account: account)
      end

      def uncache_installation_client
        GitHubHelpers.delete_cached_access_token_for(account: account)
        @installation_github_client = nil
      end

      def update_job_multi_ecosystem_siblings_enqueued_together
        @update_job_multi_ecosystem_siblings_enqueued_together ||= update_job.multi_ecosystem_siblings_enqueued_together
      end
    end
  end
end
