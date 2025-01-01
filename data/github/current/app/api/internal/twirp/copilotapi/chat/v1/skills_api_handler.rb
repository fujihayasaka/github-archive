# typed: true
# frozen_string_literal: true

require "monolith-twirp-copilotapi-chat"

module Api::Internal::Twirp::Copilotapi
  module Chat
    module V1
      # Handler for the MonolithTwirp::Copilotapi::Chat::V1::SkillsAPIService
      class SkillsAPIHandler < Api::Internal::Twirp::Handler

        allow_access_for :client, allowed_clients: ["copilot_api"]
        handles_service MonolithTwirp::Copilotapi::Chat::V1::SkillsAPIService

        # This RPC is not yet going to be used with CAPI
        # See this product decision in Slack https://github.slack.com/archives/C057SFJ8QR3/p1695853624418459?thread_ts=1695840787.043969&cid=C057SFJ8QR3
        # Getting Codeowners is not set to be added until after Universe
        def get_codeowners(req, env)
          return Twirp::Error.invalid_argument("must be non-empty", argument: "repository_id") if req.repository_id.blank?

          repo = Repository.find_by(id: req.repository_id)
          return Twirp::Error.not_found("repo not found") if repo.nil?

          codeowners = Repository::Codeowners.new(repo, ref: req.ref, paths: req.paths)

          {
            users: codeowners.users,
            teams: codeowners.teams
          }
        end

        sig do
          params(
            req: MonolithTwirp::Copilotapi::Chat::V1::GetCommitRequest,
            env: Hash
          ).returns(T.any(Hash, Twirp::Error))
        end
        def get_commit(req, env)
          return Twirp::Error.new(:unauthenticated, "unauthenticated") if req.access_token.blank?
          return Twirp::Error.invalid_argument("must be non-empty", argument: "repository_nwo") if req.repository_nwo.blank?
          return Twirp::Error.invalid_argument("must be non-empty", argument: "commitish") if req.commitish.blank?

          repo = Repository.with_name_with_owner(req.repository_nwo)
          return Twirp::Error.not_found("repository does not exist", argument: "repository_nwo") if repo.nil?

          _, user_allowed = authorize(action: :get_commit, token: req.access_token, resource: repo, repo: repo, ip: req.ip_address)
          return Twirp::Error.not_found("commit not found") unless user_allowed

          commit = nil
          # commit_for_ref throws a GitRPC::ObjectMissing error if the commit is not found in the repo
          begin
            commit = repo.commit_for_ref(req.commitish)
          rescue GitRPC::ObjectMissing
            return Twirp::Error.not_found("commit not found") if commit.nil?
          end

          {
            commit: {
              commit_oid: commit.oid,
              commit_msg: commit.message,
              author_name: commit.author_name,
              author_email: commit.author_email,
              author_login: commit.author&.display_login,
              permalink: commit.url,
              created_at: commit.created_at,
              repo_name: repo.name,
              repo_id: repo.id,
              repo_owner: repo.owner_display_login
            }
          }
        end

        def get_commits_and_pull_requests(req, env)
          user_id = id_argument(req.user_id, env[:user_id])
          user = User.find_by(id: user_id)
          return Twirp::Error.not_found("user does not exist", argument: "user_id") if user.nil?

          repo = Repository.find_by(id: req.repository_id)
          return Twirp::Error.not_found("repo not found") if repo.nil?

          line_numbers = req.line_numbers.to_a
          blame = Blame.new(repo, req.commitish, req.path, line_numbers: line_numbers)

          commits_by_created_at = blame.commits.sort_by { |_, v| v.created_at }
          recent_commits = commits_by_created_at.map(&:last).last(3)

          associated_prs = recent_commits.map do |commit|
            commit.async_associated_pull_requests(order_by: { field: "created_at" }, viewer: user)
          end

          results = Promise.all(associated_prs).sync
          pull_requests = results.map do |prs|
            prs.map do |pr|
              {
                title: pr.title,
                url: pr.url,
                author_login: pr&.user&.display_login,
              }
            end
          end
          pulls_by_commit = recent_commits.zip(pull_requests).to_h

          caps = recent_commits.map do |commit|
            next {} unless commit
            {
              commit_oid: commit.oid,
              commit_msg: commit.message,
              author_name: commit.author_name,
              author_email: commit.author_email,
              author_login: commit&.author&.display_login,
              permalink: commit.url,
              repo_owner: repo.owner_display_login,
              repo_name: repo.name,
              pull_requests: pulls_by_commit[commit]
            }
          end

          {
            commits_and_prs: caps
          }
        end

        sig do
          params(
            req: MonolithTwirp::Copilotapi::Chat::V1::GetPullRequestCommitsRequest,
            env: Hash
          ).returns(T.any(Hash, Twirp::Error))
        end
        def get_pull_request_commits(req, env)
          return Twirp::Error.new(:unauthenticated, "unauthenticated") if req.access_token.blank?
          return Twirp::Error.invalid_argument("must be non-empty", argument: "pull_number") if req.pull_number.blank? || req.pull_number.zero?
          return Twirp::Error.invalid_argument("must be non-empty", argument: "repository_nwo") if req.repository_nwo.blank?

          repo = Repository.with_name_with_owner(req.repository_nwo)
          return Twirp::Error.not_found("repo not found") if repo.nil?

          _, can_view_repo = authorize(action: :get_repo, token: req.access_token, resource: repo, repo: repo, ip: req.ip_address)
          return Twirp::Error.not_found("repo not found") unless can_view_repo

          issue = Issue.includes(:pull_request).find_by(repository: repo, number: req.pull_number)
          pull_request = issue.pull_request if issue
          return Twirp::Error.not_found("pull request not found") if pull_request.nil?

          _, can_view_pull_request = authorize(action: :get_pull_request, token: req.access_token, resource: pull_request, repo: repo, ip: req.ip_address)
          return Twirp::Error.not_found("pull request not found") unless can_view_pull_request

          Copilot::GetPullRequestCommitsResponse.new(pull_request: pull_request, repository: repo).payload
        end

        def get_discussion(req, env)
          return Twirp::Error.invalid_argument("must be non-empty", argument: "discussion_number") if req.discussion_number.blank?

          user_id = id_argument(req.user_id, env[:user_id])
          user = User.find_by(id: user_id)
          return Twirp::Error.not_found("user does not exist", argument: "user_id") if user.nil?

          repo = if req.repository_nwo.present?
            Repository.with_name_with_owner(req.repository_nwo)
          elsif req.owner.present?
            Organization.find_by(login: req.owner)&.discussion_repository&.repository
          end
          return Twirp::Error.not_found("repository does not exist", argument: "repository_nwo") if repo.nil?

          discussion = Discussion.find_by(repository: repo, number: req.discussion_number)
          return Twirp::Error.not_found("discussion not found") if discussion.nil? || !discussion.readable_by?(user)

          Copilot::GetDiscussionSkillResponse.new(discussion: discussion, current_user: user).payload
        end

        BLOB_LIMIT_REACT = 2.megabytes

        def get_file(req, env)
          return Twirp::Error.new(:unauthenticated, "unauthenticated") if req.access_token.blank?
          return Twirp::Error.invalid_argument("must be non-empty", argument: "repository_nwo") if req.repository_nwo.blank?
          return Twirp::Error.invalid_argument("must be non-empty", argument: "path") if req.path.blank?

          auth_options = {
            token: req.access_token,
            ip: req.ip_address
          }

          current_user = T.let(nil, T.nilable(User))
          if GitHub::Authentication::SignedAuthToken.valid_format?(req.access_token)
            parsed_token = GitHub::Authentication::SignedAuthToken.verify(
              token: req.access_token,
              scope: Copilot::User::CopilotApi::SSAT_SCOPE_GITHUB_CHAT,
            )

            current_user = parsed_token.user

            auth_options[:authenticated_actor_using_web_session] = true
            auth_options[:viewer] = parsed_token.user
            auth_options[:user_session] = parsed_token.session
          end

          repo = Repository.with_name_with_owner(req.repository_nwo)
          return Twirp::Error.not_found("repository does not exist", argument: "repository_nwo") if repo.nil?

          commit_oid = req.ref.empty? ? repo.default_oid : repo.ref_to_sha(req.ref)
          paths = repo.tree_file_list(commit_oid)
          paths = filter_paths(paths, req.path)

          return Twirp::Error.not_found("path not found") if paths.empty?

          files = []

          paths.each do |path|
            ac = CopilotAPI::AccessControl.new(auth_options)
            user_allowed = ac.access_allowed?(:get_contents,
              resource: repo,
              path: path,
              user: current_user,
              current_repo: repo,
              current_org: repo.owner&.organization? ? repo.owner : nil,
              allow_integrations: true,
              allow_user_via_granular_actor: true,
              raise_on_error: false,
            )
            return Twirp::Error.not_found("repo not found") unless user_allowed

            blob = repo.blob(commit_oid, path, { truncate: false, limit: BLOB_LIMIT_REACT })

            file = {
              repo_id: repo.id,
              repo_name: repo.name,
              url: "#{GitHub.url}/#{repo.name_with_owner}/blob/#{commit_oid}/#{path}",
              path: path,
              commit_oid: commit_oid,
              language_name: blob&.language&.name,
              language_id: blob&.language&.language_id.to_s,
              default_oid: repo.default_oid,
              contents: blob&.data,
            }

            files << file
          end

          {
            files: files
          }

        end

        # Get commits and blame_lines for a file
        MAX_LIMIT = 3
        TEXT_TOKENS_LINE_MAX = 10
        TEXT_TOKENS_TOTAL_MAX = 200

        sig do
          params(
            req: MonolithTwirp::Copilotapi::Chat::V1::GetFileChangesRequest,
            env: Hash
          ).returns(T.any(Hash, Twirp::Error))
        end
        def get_file_changes(req, env)
          # Validate required fields
          return Twirp::Error.new(:unauthenticated, "unauthenticated") if req.access_token.blank?
          return Twirp::Error.invalid_argument("must be non-empty", argument: "repository_nwo") if req.repository_nwo.blank?
          return Twirp::Error.invalid_argument(" must be non-empty", argument: "path") if req.path.blank?

          # Set optional field defaults
          max = req.max == 0 ? MAX_LIMIT : [req.max, MAX_LIMIT].min

          # Get repo
          repo = Repository.with_name_with_owner(req.repository_nwo)
          return Twirp::Error.not_found("repository does not exist", argument: "repository_nwo") if repo.nil?
          _, can_view_repo = authorize(action: :get_repo, token: req.access_token, resource: repo, repo: repo, ip: req.ip_address)
          return Twirp::Error.not_found("repo not found") unless can_view_repo

          # Get commit OID
          ref_sha = repo.ref_to_sha(req.ref)
          commit_oid = ref_sha.nil? ? repo.default_oid : ref_sha

          # Check if path exists
          path_not_found = !repo.tree_file_list(commit_oid).include?(req.path)
          return Twirp::Error.not_found("path not found") if path_not_found

          # Create list of all commits for this file
          commits_history = repo.commits.history(commit_oid, max, 0, req.path)
          return Twirp::Error.not_found("commits history doesn't exist") if commits_history.nil?

          # Get blame, filtered by oldest commit in commits_history
          blame = Blame.new(repo, commit_oid, req.path, since: commits_history.last&.created_at)
          return Twirp::Error.not_found("blame not found") if blame.nil?

          # Serialize commits list for response, and populate set for blame filtering
          commits_oids = Set.new
          commits = commits_history.map do |c|
            next {} unless c
            commits_oids.add(c.oid)
            {
              commit_oid: c.oid,
              commit_msg: c.message.gsub(/\s+/, " "), # filter whitespace
              author_name: c.author_name,
              author_email: c.author_email,
              author_login: c.author&.display_login,
              permalink: c.url,
              created_at: c.created_at,
              repo_id: repo.id,
              repo_name: repo.name,
              repo_owner: repo.owner_display_login
            }
          end

          # Truncates the blame_lines for text tokens, and serialize for response
          text_tokens_total = TEXT_TOKENS_TOTAL_MAX
          blame_lines = blame.lines.each_with_object([]) do |bl, arr|
            # Filter blame lines for token count, commit oid, and message
            # bl[2] is the commit, and bl[3] is the line text
            next unless bl[3] && bl[3].strip != "" && commits_oids.include?(bl[2].oid) && text_tokens_total > 0

            # Get text tokens, limited by total tokens remaining, and line max
            text_tokens = bl[3].split.take([text_tokens_total, TEXT_TOKENS_LINE_MAX].min)

            # Decrement total tokens remaining
            text_tokens_total -= text_tokens.length

            arr << {
                line_no: bl[0],
                old_line_no: bl[1],
                commit_oid: bl[2].oid,
                text: text_tokens.join(" "),
                reblame_path: bl[4],
                repo_id: repo.id,
                repo_name: repo.name,
                repo_owner: repo.owner_display_login
              }
          end

          # Return response data
          {
            file_changes: {
              commits: commits,
              blame_lines: blame_lines,
              repo_id: repo.id,
              repo_name: repo.name,
              repo_owner: repo.owner_display_login
            }
          }
        end

        sig do
          params(
            req: MonolithTwirp::Copilotapi::Chat::V1::GetIssueRequest,
            env: Hash
          ).returns(T.any(Hash, Twirp::Error))
        end
        def get_issue(req, env)
          return Twirp::Error.new(:unauthenticated, "unauthenticated") if req.access_token.blank?
          return Twirp::Error.invalid_argument("must be non-empty", argument: "issue_number") if req.issue_number.blank? || req.issue_number.zero?
          return Twirp::Error.invalid_argument("must be non-empty", argument: "repository_nwo") if req.repository_nwo.blank?

          repo = Repository.with_name_with_owner(req.repository_nwo)
          return Twirp::Error.not_found("repository does not exist", argument: "repository_nwo") if repo.nil?

          issue = Issue.includes(:user, :assignees).find_by(repository: repo, number: req.issue_number)
          return Twirp::Error.not_found("issue not found") if issue.nil?

          current_user, user_allowed = authorize(action: :show_issue, token: req.access_token, resource: issue, repo: repo, ip: req.ip_address)
          return Twirp::Error.not_found("issue not found") unless user_allowed

          Copilot::GetIssueSkillResponse.new(issue: issue, current_user: current_user).payload
        end

        sig do
          params(
            req: MonolithTwirp::Copilotapi::Chat::V1::GetPullRequestAlertsRequest,
            env: Hash
          ).returns(T.any(MonolithTwirp::Copilotapi::Chat::V1::GetPullRequestAlertsResponse, Twirp::Error))
        end
        def get_pull_request_alerts(req, env)
          return Twirp::Error.new(:unauthenticated, "unauthenticated") if req.access_token.blank?
          return Twirp::Error.invalid_argument("must be non-empty", argument: "pull_number") if req.pull_number.blank?
          return Twirp::Error.invalid_argument("must be non-empty", argument: "repository_nwo") if req.repository_nwo.blank?

          repo = Repository.with_name_with_owner(req.repository_nwo)
          return Twirp::Error.not_found("repository does not exist", argument: "repository_nwo") if repo.nil?

          _, can_view_repo = authorize(action: :get_repo, token: req.access_token, resource: repo, repo: repo, ip: req.ip_address)
          return Twirp::Error.not_found("repo not found") unless can_view_repo

          return Twirp::Error.not_found("advanced security not purchased") unless repo.owner&.advanced_security_purchased?

          pull_request = Issue.includes(:pull_request).find_by(repository: repo, number: req.pull_number)&.pull_request
          return Twirp::Error.not_found("pull request not found") if pull_request.nil?

          _, can_view_pull_request = authorize(action: :get_pull_request, token: req.access_token, resource: pull_request, repo: repo, ip: req.ip_address)
          return Twirp::Error.not_found("pull request not found") unless can_view_pull_request

          merge_commit_oid = CodeScanningCheckSuite.merge_commit_for(pull_request:)

          response = GitHub::Turboscan.pull_request_alerts(
            repository_id: pull_request.repository_id,
            tool: "CodeQL",
            head_commit_oid: pull_request.head_sha,
            merge_commit_oid: merge_commit_oid,
            base_ref_bytes: pull_request.qualified_base_ref_name.b,
            file_changes: ::CodeScanning::PullRequestAlertSummaryGenerator.changed_lines(pull_request.diffs)
          )

          return Twirp::Error.internal("failed to fetch pull request alerts") if response&.error.present?

          MonolithTwirp::Copilotapi::Chat::V1::GetPullRequestAlertsResponse.new(
            base_repo_id: repo.id,
            code_scanning_alert_summaries: response&.data&.new_alerts&.to_a&.map do |diffed_alert|
              location = MonolithTwirp::Copilotapi::Chat::V1::AlertLocation.new(
                path: diffed_alert.location&.file_path,
                start_column: diffed_alert.location&.start_column,
                end_column: diffed_alert.location&.end_column,
                start_line: diffed_alert.location&.start_line,
                end_line: diffed_alert.location&.end_line,
              ) if diffed_alert.location.present?

              severity = if diffed_alert.security_severity != :NO_SECURITY_SEVERITY
                diffed_alert.security_severity.to_s.downcase
              else
                diffed_alert.rule_severity.to_s.downcase
              end

              MonolithTwirp::Copilotapi::Chat::V1::GetPullRequestAlertsResponse::CodeScanningAlertSummary.new(
                number: diffed_alert.number,
                message: diffed_alert.message_markdown,
                title: diffed_alert.rule_short_description,
                severity:,
                location:,
              )
            end,
          )
        end

        sig do
          params(
            req: MonolithTwirp::Copilotapi::Chat::V1::GetCodeScanningAlertRequest,
            env: Hash
          ).returns(T.any(MonolithTwirp::Copilotapi::Chat::V1::GetCodeScanningAlertResponse, Twirp::Error))
        end
        def get_code_scanning_alert(req, env)
          return Twirp::Error.new(:unauthenticated, "unauthenticated") if req.access_token.blank?
          return Twirp::Error.invalid_argument("must be non-empty", argument: "alert_number") if req.alert_number.blank? || req.alert_number.zero?
          return Twirp::Error.invalid_argument("must be non-empty", argument: "repository_nwo") if req.repository_nwo.blank?

          repo_not_found_error = Twirp::Error.not_found("repository not found", argument: "repository_nwo")

          repo = Repository.with_name_with_owner(req.repository_nwo)
          return repo_not_found_error if repo.nil?

          _, can_view_repo = authorize(action: :get_repo, token: req.access_token, resource: repo, repo: repo, ip: req.ip_address)
          return repo_not_found_error unless can_view_repo

          return Twirp::Error.not_found("advanced security not purchased") unless repo.owner&.advanced_security_purchased?

          ref_names_bytes = [req.ref] if req.ref.present?

          response = GitHub::Turboscan.alert(
            repository_id: repo.id,
            number: req.alert_number,
            ref_names_bytes:,
          )

          data = response&.data

          return Twirp::Error.not_found("alert does not exist", argument: "alert_number") if response&.error&.code == :not_found
          return Twirp::Error.internal("failed to fetch alert") if response&.error.present?
          return Twirp::Error.not_found("turboscan returned no data", argument: "alert_number") if data.nil?

          Copilot::GetCodeScanningAlertSkillResponse.new(alert: data, current_repository: repo).payload
        end

        sig do
          params(
            req: MonolithTwirp::Copilotapi::Chat::V1::GetDependabotAlertRequest,
            env: Hash
          ).returns(T.any(MonolithTwirp::Copilotapi::Chat::V1::GetDependabotAlertResponse, Twirp::Error))
        end
        def get_dependabot_alert(req, env)
          return Twirp::Error.new(:unauthenticated, "unauthenticated") if req.access_token.blank?
          return Twirp::Error.invalid_argument("must be non-empty", argument: "alert_number") if req.alert_number.blank? || req.alert_number.zero?
          return Twirp::Error.invalid_argument("must be non-empty", argument: "repository_nwo") if req.repository_nwo.blank?

          repo_not_found_error = Twirp::Error.not_found("repository not found", argument: "repository_nwo")

          repo = Repository.with_name_with_owner(req.repository_nwo)
          return repo_not_found_error if repo.nil?

          _, can_view_repo = authorize(action: :get_repo, token: req.access_token, resource: repo, repo: repo, ip: req.ip_address)
          return repo_not_found_error unless can_view_repo

          return Twirp::Error.not_found("advanced security not purchased") unless repo.owner&.advanced_security_purchased?

          alert = RepositoryVulnerabilityAlert
            .includes(
              :create_pull_request,
              :repository_vulnerable_function_references,
              :vulnerable_version_range,
              :vulnerability,
              vulnerability: :vulnerability_references
            )
            .find_by(number: req.alert_number, repository_id: repo.id)

          return Twirp::Error.not_found("alert does not exist", argument: "alert_number") if alert.nil?

          Copilot::GetDependabotAlertSkillResponse.new(alert:, current_repository: repo).payload
        end

        sig do
          params(
            req: MonolithTwirp::Copilotapi::Chat::V1::GetSecretScanningAlertRequest,
            env: Hash
          ).returns(T.any(MonolithTwirp::Copilotapi::Chat::V1::GetSecretScanningAlertResponse, Twirp::Error))
        end
        def get_secret_scanning_alert(req, env)
          return Twirp::Error.new(:unauthenticated, "unauthenticated") if req.access_token.blank?
          return Twirp::Error.invalid_argument("must be non-empty", argument: "alert_number") if req.alert_number.blank? || req.alert_number.zero?
          return Twirp::Error.invalid_argument("must be non-empty", argument: "repository_nwo") if req.repository_nwo.blank?

          repo = Repository.with_name_with_owner(req.repository_nwo)
          return Twirp::Error.not_found("repository does not exist", argument: "repository_nwo") if repo.nil?

          return Twirp::Error.not_found("advanced security not purchased") unless repo.owner&.advanced_security_purchased?

          current_user, can_read_alerts = authorize(action: :read_secret_scanning_alerts, token: req.access_token, resource: repo, repo: repo, ip: req.ip_address)
          return Twirp::Error.not_found("secret scanning alert not found") unless can_read_alerts

          alerts_service = SecretScanning::Services::AlertsService.new
          token, error = alerts_service.get_alert(repo, current_user, req.alert_number, nil)

          return Twirp::Error.not_found("alert does not exist", argument: "alert_number") if error&.include?("not found")
          return Twirp::Error.internal("failed to fetch alert") if error.present?
          return Twirp::Error.not_found("alerts service returned no data", argument: "alert_number") if token.nil?

          Copilot::GetSecretScanningAlertSkillResponse.new(alert: token, current_repository: repo).payload
        end

        sig do
          params(
            req: MonolithTwirp::Copilotapi::Chat::V1::GetRepoSecurityAlertCountsRequest,
            env: Hash
          ).returns(T.any(MonolithTwirp::Copilotapi::Chat::V1::GetRepoSecurityAlertCountsResponse, Twirp::Error))
        end
        def get_repo_security_alert_counts(req, env)
          twirp_error_user_unauthenticated = Twirp::Error.new(:unauthenticated, "unauthenticated")
          twirp_error_repo_not_found = Twirp::Error.not_found("repo not found")

          # Validate required parameters.
          return twirp_error_user_unauthenticated if req.access_token.blank?
          return Twirp::Error.invalid_argument("must be non-empty", argument: "repository_nwo") if req.repository_nwo.blank?

          # Get and validate the repository.
          repo = Repository.with_name_with_owner(req.repository_nwo)
          return twirp_error_repo_not_found if repo.nil?

          # Authorize the user can view the repository.
          # TODO https://github.com/github/copilot-core-productivity/issues/1998: Update protobuf to include ip_address
          user, can_view_repo = authorize(action: :get_repo, token: req.access_token, resource: repo, repo: repo, ip: req.ip_address)
          return twirp_error_user_unauthenticated unless user
          return twirp_error_repo_not_found unless can_view_repo

          Copilot::GetRepoSecurityAlertCountsSkillResponse.new(user:, repo:).payload
        end

        sig do
          params(
            req: MonolithTwirp::Copilotapi::Chat::V1::GetRepositoryRequest,
            env: Hash
          ).returns(T.any(Hash, Twirp::Error))
        end
        def get_repository(req, env)
          return Twirp::Error.new(:unauthenticated, "unauthenticated") if req.access_token.blank?
          return Twirp::Error.invalid_argument("must be non-empty", argument: "repository_nwo") if req.repository_nwo.blank?

          repo = Repository.with_name_with_owner(req.repository_nwo)
          return Twirp::Error.not_found("repository does not exist", argument: "repository_nwo") if repo.nil?

          _, user_allowed = authorize(action: :get_repo, token: req.access_token, resource: repo, repo: repo, ip: req.ip_address)
          return Twirp::Error.not_found("repo not found") unless user_allowed

          # Protobuf lint requires a specific name for enums to be valid
          visibility = if repo.private?
            "VISIBILITY_PRIVATE"
          elsif repo.internal?
            "VISIBILITY_INTERNAL"
          elsif repo.public?
            "VISIBILITY_PUBLIC"
          else
            "VISIBILITY_INVALID"
          end

          owner_type = if repo.owner&.organization?
            "OWNER_TYPE_ORG"
          elsif repo.owner&.user?
            "OWNER_TYPE_USER"
          else
            "OWNER_TYPE_INVALID"
          end

          {
            repository: {
              id: repo.id,
              global_relay_id: repo.global_relay_id,
              name: repo.name,
              description: repo.description,
              visibility: visibility,
              parent_id: repo.parent_id,
              stargazer_count: repo.stargazer_count,
              public_fork_count: repo.public_fork_count,
              pushed_at: repo.pushed_at.nil? ? nil : Google::Protobuf::Timestamp.new(seconds: repo.pushed_at.to_i),
              created_at: Google::Protobuf::Timestamp.new(seconds: repo.created_at.to_i),
              updated_at: Google::Protobuf::Timestamp.new(seconds: repo.updated_at.to_i),
              default_branch: repo.default_branch,
              owner_id: repo.owner_id,
              is_archived: repo.archived?,
              parent_owner_id: repo.parent&.owner_id,
              owner_type: owner_type,
              readme_path: repo.preferred_readme&.path,
              languages: repo.top_languages_summarized.map { |name, percent| { name: name, percent: percent } },
            }
          }
        end

        sig { params(req: MonolithTwirp::Copilotapi::Chat::V1::GetProfileRequest, env: T::Hash[Symbol, T.untyped]).returns(T.any(Twirp::Error, T::Hash[Symbol, T::Hash[T.untyped, T.untyped]])) }
        def get_profile(req, env)
          return Twirp::Error.invalid_argument("must be non-empty", argument: "login") if req.login.blank?

          current_user_id = id_argument(req.user_id, env[:user_id])
          current_user = User.find_by(id: current_user_id)
          return Twirp::Error.not_found("current user does not exist", argument: "user_id") if current_user.nil?

          user = User.find_by_login(req.login.strip.delete_prefix("@"))
          profile = user&.profile

          if user.nil? || user.hide_from_user?(current_user) || user.blocking?(current_user)
            return Twirp::Error.not_found("profile does not exist", argument: "login")
          end

          profile_attributes = if profile && !user.private_profile?
            profile.slice(:name, :bio, :pronouns, :location, :company, :twitter_username)
          else
            {}
          end

          {
            profile: {
              login: user.display_login,
              url: user.permalink,
            }.merge(profile_attributes)
          }
        end

        sig do
          params(
            req: MonolithTwirp::Copilotapi::Chat::V1::CompareTreesRequest,
            env: Hash
          ).returns(T.any(Hash, Twirp::Error))
        end
        def compare_trees(req, env)
          return Twirp::Error.new(:unauthenticated, "unauthenticated") if req.access_token.blank?
          return Twirp::Error.invalid_argument("must be non-empty", argument: "base_repo_id") if req.base_repo_id.blank?
          return Twirp::Error.invalid_argument("must be non-empty", argument: "head_repo_id") if req.head_repo_id.blank?

          user_id = id_argument(req.user_id, env[:user_id])
          user = User.find_by(id: user_id)
          return Twirp::Error.not_found("user does not exist", argument: "user_id") if user.nil?

          base_repo_id = id_argument(req.base_repo_id, env[:base_repo_id])
          head_repo_id = id_argument(req.head_repo_id, env[:head_repo_id])

          base_repo = Repository.find_by(id: base_repo_id)
          return Twirp::Error.not_found("base repo not found", argument: "base_repo_id") if base_repo.nil?

          _, user_allowed = authorize(action: :get_contents, token: req.access_token, resource: base_repo, repo: base_repo, ip: req.ip_address)
          return Twirp::Error.not_found("base repo not found") unless user_allowed

          head_repo = Repository.find_by(id: head_repo_id)
          return Twirp::Error.not_found("head repo not found", argument: "head_repo_id") if head_repo.nil?

          _, user_allowed = authorize(action: :get_contents, token: req.access_token, resource: head_repo, repo: head_repo, ip: req.ip_address)
          return Twirp::Error.not_found("head repo not found") unless user_allowed

          return Twirp::Error.invalid_argument("base_revision and head_revision must be specified") if req.base_revision.blank? || req.head_revision.blank?
          PullRequests::Copilot::CompareTreesDiffCreator.call(base_repo: base_repo, head_repo: head_repo, base_revision: req.base_revision, head_revision: req.head_revision, paths: req.paths, context_lines: req.context_lines)
        end

        sig do
          params(
            req: MonolithTwirp::Copilotapi::Chat::V1::CompareTreesByRangeRequest,
            env: Hash
          ).returns(T.any(Hash, Twirp::Error))
        end
        def compare_trees_by_range(req, env)
          return Twirp::Error.new(:unauthenticated, "unauthenticated") if req.access_token.blank?
          user_id = id_argument(req.user_id, env[:user_id])
          user = User.find_by(id: user_id)
          return Twirp::Error.not_found("user does not exist", argument: "user_id") if user.nil?

          return Twirp::Error.not_found("range is not present", argument: "range") if !req.range.present?
          return Twirp::Error.not_found("repository name and owner not present", argument: "repository_nwo") if !req.repository_nwo.present?

          base_repo = Repository.nwo(req.repository_nwo)
          return Twirp::Error.not_found("base repo not found", argument: "repository_nwo") if base_repo.nil?

          _, user_allowed = authorize(action: :get_contents, token: req.access_token, resource: base_repo, repo: base_repo, ip: req.ip_address)
          return Twirp::Error.not_found("base repo not found") unless user_allowed

          comparison = GitHub::Comparison.from_range_or_ref(
            base_repo,
            req.range,
            limit: 1,
            user: user,
          )

          return Twirp::Error.not_found("could not extract comparison for a given range", argument: "range") if !comparison.valid?

          _, user_allowed = authorize(
            action: :get_contents,
            token: req.access_token,
            resource: comparison.head_repo,
            repo: comparison.head_repo,
            ip: req.ip_address)

          return Twirp::Error.not_found("head repo not found") unless user_allowed

          PullRequests::Copilot::CompareTreesDiffCreator.call(base_repo: base_repo, head_repo: comparison.head_repo, base_revision: comparison.base_sha, head_revision: comparison.head_sha)
        end

        def get_raw_job_log(req, env)
          user_id = id_argument(req.user_id, env[:user_id])
          user = User.find_by(id: user_id)

          return Twirp::Error.not_found("user does not exist", argument: "user_id") if user.nil?

          repo = Repository.with_name_with_owner(req.repository_nwo)

          return Twirp::Error.not_found("repository does not exist") if !repo&.readable_by?(user)

          job = CheckRun.includes(:check_suite).find_by(id: req.job_id)

          # Checks are a bit redundant but required for Sorbet to properly infer the types
          return Twirp::Error.not_found("job does not exist", argument: "job_id") if job.nil? || job.check_suite.nil?

          return Twirp::Error.not_found("job did not run on actions") if job.check_suite&.workflow_run.blank?

          return Twirp::Error.not_found("job does not exist in this repo", argument: "job_id") unless repo.id == job.check_suite&.repository_id

          return Twirp::Error.not_found("job logs are expired", argument: "job_id") if job.expired_logs?

          if ActionsResults::Utils.is_results_url?(job.completed_log_url) && job.check_suite&.workflow_run&.logs_via_results_service?
            return Twirp::Error.not_found("job logs not available", argument: "job_id") unless job.external_id.present? && job.check_suite&.external_id.present?
            matches = ActionsResults::Utils.get_ids_from_results_url(job.completed_log_url)
            return Twirp::Error.not_found("could not get job logs") unless matches

            result = ActionsResults::Twirp.log_client.get_completed_job_log_url(
              workflow_job_run_backend_id: T.must(matches[:workflow_job_run_backend_id]),
              workflow_run_backend_id: T.must(matches[:workflow_run_backend_id]),
            )
            return Twirp::Error.not_found("could not get job logs", argument: "job_id") unless result.call_succeeded?

            results_log_url = result.value.log_url
          else
            completed_log_url = job.completed_log_url
            return Twirp::Error.not_found("could not get job logs url", argument: "job_id") if completed_log_url.nil? || completed_log_url.blank?

            if ActionsResults::Utils.is_results_url?(job.completed_log_url)
              completed_log_url = ActionsResults::Utils.actions_url(job.completed_log_url)
            end

            return Twirp::Error.not_found("could not get job logs url", argument: "job_id") unless completed_log_url

            use_next_gid = !GitHub.enterprise?
            global_id = use_next_gid ? repo.next_global_id : repo.global_relay_id

            request = GitHub::Launch::Services::Artifactsexchange::ExchangeURLRequest.new({
              unauthenticated_url: completed_log_url,
              repository_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: global_id),
              resource_type: GitHub::Launch::Services::Artifactsexchange::ResourceType::TYPE_COMPLETED_JOB_LOG,
            })

            result = Launch::Twirp.artifacts_exchange_client_for_check_suite(T.must(job.check_suite)).exchange_url(request)

            if result.call_succeeded?
              results_log_url = result.value.authenticated_url
            else
              return Twirp::Error.not_found("could not get job logs", argument: "job_id")
            end
          end

          workflow_run = job.check_suite&.workflow_run

          {
            job_log: {
              repo_id: repo.id,
              job_log_url: results_log_url,
              head_sha: job.head_sha,
              runner: {
                runner_name: job.runner_name,
                runner_name_id: job.runner_id,
                runner_group: job.runner_group_name,
                runner_group_id: job.runner_group_id,
              },
              workflow: {
                workflow_name: workflow_run&.workflow_name,
                workflow_id: workflow_run&.workflow_id,
              }
            }
          }
        end

        sig do
          params(
            req: MonolithTwirp::Copilotapi::Chat::V1::GetPullRequestRequest,
            env: Hash
          ).returns(T.any(Hash, Twirp::Error))
        end
        def get_pull_request(req, env)
          return Twirp::Error.new(:unauthenticated, "unauthenticated") if req.access_token.blank?
          return Twirp::Error.invalid_argument("must be non-empty", argument: "pull_number") if req.pull_number.blank?

          user_id = id_argument(req.user_id, env[:user_id])
          user = User.find_by(id: user_id)
          return Twirp::Error.not_found("user does not exist", argument: "user_id") if user.nil?

          repo = Repository.with_name_with_owner(req.repository_nwo)
          return Twirp::Error.not_found("repository does not exist", argument: "repository_nwo") if repo.nil?

          pr = repo.issues.find_by_number(req.pull_number)&.pull_request
          return Twirp::Error.not_found("pull request not found") if pr.nil? || !pr.readable_by?(user)

          _, user_allowed = authorize(action: :get_pull_request, token: req.access_token, resource: pr, repo: repo, ip: req.ip_address)
          return Twirp::Error.not_found("pull request not found") unless user_allowed

          {
            pull_request: {
              number: pr.number,
              title: pr.title,
              body: pr.body,
              author_login: pr.user.login,
              state: pr.state,
              url: pr.url,
              id: pr.id,
              base_repo_id: pr.repository_id,
              head_repo_id: pr.head_repository_id,
              base_revision: pr.base_sha,
              head_revision: pr.head_sha,
            }
          }
        end

        sig do
          params(
            req: MonolithTwirp::Copilotapi::Chat::V1::GetReleaseRequest,
            env: Hash
          ).returns(T.any(Hash, Twirp::Error))
        end
        def get_release(req, env)
          return Twirp::Error.new(:unauthenticated, "unauthenticated") if req.access_token.blank?
          return Twirp::Error.invalid_argument("must be non-empty", argument: "repository_nwo") if req.repository_nwo.blank?

          repo = Repository.with_name_with_owner(req.repository_nwo)
          return Twirp::Error.not_found("repository does not exist", argument: "repository_nwo") if repo.nil?

          if req.tag_name.blank?
            release = Releases::Public.latest_for_repository(repo, current_user)
          else
            release = repo.releases.find_by(tag_name: req.tag_name)
          end
          return Twirp::Error.not_found("release not found") if release.nil?

          _, user_allowed = authorize(action: :get_release, token: req.access_token, resource: release, repo: repo, ip: req.ip_address)
          return Twirp::Error.not_found("release not found") unless user_allowed

          {
            release: {
              name: release.name,
              body: release.body,
              url: release.permalink,
              tag_name: release.tag_name,
              target_commitish: release.target_commitish,
              is_draft: release.draft?,
              is_prerelease: release.prerelease?,
              published_at: release.published_at ? Google::Protobuf::Timestamp.new(seconds: release.published_at.to_i) : nil,
              author_login: User.find_by(id: release.author_id)&.login,
              repo_id: repo.id,
              release_id: release.id
            }
          }
        end

        private

        def authorize(action:, token:, resource:, repo:, ip:)
          auth_options = {
            token:,
            ip:
          }

          current_user = T.let(nil, T.nilable(User))
          if GitHub::Authentication::SignedAuthToken.valid_format?(token)
            parsed_token = GitHub::Authentication::SignedAuthToken.verify(
              token:,
              scope: Copilot::User::CopilotApi::SSAT_SCOPE_GITHUB_CHAT,
            )

            current_user = parsed_token.user
            auth_options[:authenticated_actor_using_web_session] = true
            auth_options[:viewer] = parsed_token.user
            auth_options[:user_session] = parsed_token.session
          end

          ac = CopilotAPI::AccessControl.new(auth_options)
          allowed = ac.access_allowed?(action,
            resource:,
            repo:,
            current_repo: repo,
            current_org: repo.owner&.organization? ? repo.owner : nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
            raise_on_error: false,
          )

          [current_user || ac.user, allowed]
        end

        MAX_PATHS = 3
        def filter_paths(paths, filename)
          matches = []

          paths.each do |p|
            matches << p if p == filename || p.end_with?("/#{filename}")
            break if matches.size == MAX_PATHS
          end

          matches
        end
      end
    end
  end
end
