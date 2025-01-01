# typed: true
# frozen_string_literal: true

require "monolith-twirp-classroom-repositories"

module Api::Internal::Twirp::Classroom
  module Repositories
    module V1
      # Handler for the MonolithTwirp::Classroom::Repositories::V1::RepositoriesAPIService
      class RepositoriesAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["classroom"]
        handles_service MonolithTwirp::Classroom::Repositories::V1::RepositoriesAPIService
        connected_to_writing_for :enable_template_repo, :fork_repository, :sync_forks, :create_repo_from_template

        MAX_NAME_GENERATION_ATTEMPTS = 100

        def before_rpc(rack_env, env)
          env[:real_ip] = rack_env["HTTP_X_CLIENT_IP"]
        end

        def clone_repository(req, env)
          starter_code_repo_id = id_argument(req.starter_code_repo_id)
          unless starter_code_repo_id
            return Twirp::Error.invalid_argument("must be non-empty", argument: "starter_code_repo_id")
          end

          assignment_repo_id = id_argument(req.assignment_repo_id)
          unless assignment_repo_id
            return Twirp::Error.invalid_argument("must be non-empty", argument: "assignment_repo_id")
          end

          teacher_id = id_argument(req.teacher_id)
          unless teacher_id
            return Twirp::Error.invalid_argument("must be non-empty", argument: "teacher_id")
          end

          starter_code_repo = Repository.find_by(id: starter_code_repo_id)
          return Twirp::Error.not_found("starter code repository not found", argument: "starter_code_repo_id") unless starter_code_repo

          assignment_repo = Repository.find_by(id: assignment_repo_id)
          return Twirp::Error.not_found("assignment repository not found", argument: "assignment_repo_id") unless assignment_repo

          teacher = User.find_by(id: teacher_id)
          return Twirp::Error.not_found("teacher not found", argument: "teacher_id") unless teacher

          repository_import = RepositorySourceImport.new(
            repository: assignment_repo,
            user: teacher,
          )

          begin
            repository_import.start_import(vcs_url: starter_code_repo.permalink)
          rescue Porter::ApiClient::Error => e
            Failbot.report(e, app: "github-classroom")
            return Twirp::Error.not_found("We can't import from #{starter_code_repo.permalink}. Please check the URL and try again.")
          end

          {
            repo_url: assignment_repo.permalink,
            status: repository_import.status
          }
        end

        # Public: Implementation of the ForkRepository Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Classroom::Repositories::V1::ForkRepositoryRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Classroom::Repositories::V1::ForkRepositoryResponse, or a Twirp::Error.
        def fork_repository(req, env)
          log_fields = {
            "code.namespace" => "Api::Internal::Twirp::Classroom::Repositories",
            "code.function" => "fork_repository",
            "gh.request_id" => GitHub.context[:request_id],
          }
          GitHub.logger.info("Request received", log_fields)

          # argument validations
          unless repo_id = id_argument(req.repo_id)
            return Twirp::Error.invalid_argument("must be non-empty", argument: "repo_id")
          end
          unless installation_id = id_argument(req.installation_id)
            return Twirp::Error.invalid_argument("must be non-empty", argument: "installation_id")
          end
          student_id = id_argument(req.student_id)
          team_id = id_argument(req.team_id)
          if !student_id && !team_id
            return Twirp::Error.invalid_argument("must provide either student_id or team_id", argument: "student_id")
          elsif student_id && team_id
            return Twirp::Error.invalid_argument("must provide either student_id or team_id, not both", argument: "student_id")
          end
          fork_name = req.fork_name
          return Twirp::Error.invalid_argument("must be non-empty", argument: "fork_name") if fork_name.empty?

          # existence validations
          repo_to_fork = Repository.find_by(id: repo_id)
          return Twirp::Error.not_found("Could not find repository using repo_id") unless repo_to_fork
          installation = IntegrationInstallation.find_by(id: installation_id)
          return Twirp::Error.not_found("Installation not found") unless installation

          # access check validations
          unless installation.bot.can_fork?(repo_to_fork, installation.target)
            return Twirp::Error.permission_denied("repo cannot be forked due to a policy")
          end
          access_check = ClassroomGitHubApp::RepositoryWriteAccessCheck.new(starter_code_repository_id: repo_id, installation_id: installation_id)
          return Twirp::Error.permission_denied(access_check.renderable_error) unless access_check.valid?

          ## TODO: remove this code block after the feature flag has been tested.
          unless GitHub.flipper[:classroom_iforks_private_repo_syncing].enabled?
            # give student/group read access to the parent repo if private and owned by org
            if repo_to_fork.private? && repo_to_fork.owner&.id == installation.target.id
              if student_id
                student = User.find_by(id: student_id)
                return Twirp::Error.not_found("Student not found") unless student
                repo_to_fork.add_member(student, installation.bot, action: :read)
              elsif team_id
                team = Team.find_by(id: team_id)
                return Twirp::Error.not_found("Team not found") unless team
                repo_to_fork.add_team(team, action: :read)
              end
            end
          end

          one_branch = req.one_branch.nil? ? true : req.one_branch
          options = {
            forker: installation.bot,
            org: installation.target,
            new_name: fork_name,
            one_branch: one_branch,
          }
          forked_repo, reason, errors = repo_to_fork.fork(options)
          return Twirp::Error.internal(Repository::ForkerMethods.message_from_reason(reason, errors)) if !forked_repo

          # Convert template into non-template
          # See https://github.com/github/classroom/blob/1cf1d7e715d33362791dd1f553afd7e6f17b3ae0/docs/architecture/RFCs/2023-26-12-internal-forks.md#implementation
          begin
            # ensure the forked repo is not a template and has issues enabled
            forked_repo.update!(template: false, has_issues: true)
          rescue ActiveRecord::RecordInvalid => e
            return Twirp::Error.internal("Failed converting repo to non template: #{e}")
          end

          # this will create or update workflow records based on the files in .github/workflows
          # disable_scheduled_workflows_on_fork: false ensures that the workflows are enabled
          forked_repo.persist_existing_workflows(disable_scheduled_workflows_on_fork: false)
          # enable actions on the forked repo
          result = forked_repo.enable_actions_app(actor: installation.bot, entry_point: :twirp_api_classroom_repositories_fork_api_handler)
          unless result.success?
            return Twirp::Error.internal("Failed enabling actions on forked repo: #{result.reason}")
          end

          GitHub.logger.info("Request complete", log_fields)
          {
            repo_url: forked_repo.permalink,
            repo_id: forked_repo.id
          }
        end

        # Public: Implementation of the EnableTemplateRepo Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Classroom::Repositories::V1::EnableTemplateRepoRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Classroom::Repositories::V1::EnableTemplateRepoResponse, or a Twirp::Error.
        def enable_template_repo(req, env)
          repo_id = id_argument(req.repo_id)
          unless repo_id
            return Twirp::Error.invalid_argument("must be non-empty", argument: "repo_id")
          end

          repo = Repository.find_by(id: repo_id)
          return Twirp::Error.not_found("Repository not found.") unless repo

          repo.update!(template: true)
          return Twirp::Error.not_found("Not able to enable template repo.") unless repo.template
          { success: true }
        end

        # Public: Implementation of the GetTotalCommits Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Classroom::Repositories::V1::GetTotalCommitsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Classroom::Repositories::V1::GetTotalCommitsResponse, or a Twirp::Error.
        def get_total_commits(req, env)
          repo_id = id_argument(req.repo_id)
          unless repo_id
            return Twirp::Error.invalid_argument("must be non-empty", argument: "repo_id")
          end

          repo = Repository.find_by(id: repo_id)
          return Twirp::Error.not_found("Repository not found.") unless repo

          default_branch = repo.default_branch
          ref = repo.commit_for_ref(default_branch)
          return { commits: 0 } unless ref

          oid = ref.oid

          begin
            commits_count = repo.rpc.fast_commit_count(oid, nil, timeout: 2)
            bot_commits_count = repo.commits.search("author", Shellwords.escape("github-classroom[bot]"), default_branch).count
          rescue GitRPC::Timeout
            return Twirp::Error.not_found("Unable to get commits count for repo.")
          end

          { commits: commits_count - bot_commits_count }
        end

        # Public: Implementation of the CreateRepoFromTemplate Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Classroom::Repositories::V1::CreateRepoFromTemplateRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Classroom::Repositories::V1::CreateRepoFromTemplateResponse, or a Twirp::Error.
        def create_repo_from_template(req, env)
          unless template_repo_id = id_argument(req.template_repo_id)
            return Twirp::Error.invalid_argument("must be non-empty", argument: "template_repo_id")
          end
          unless organization_id = id_argument(req.organization_id)
            return Twirp::Error.invalid_argument("must be non-empty", argument: "organization_id")
          end
          unless repo_name = req.repo_name == "" ? nil : req.repo_name
            return Twirp::Error.invalid_argument("must be non-empty", argument: "repo_name")
          end
          unless installation_id = id_argument(req.installation_id)
            return Twirp::Error.invalid_argument("must be non-empty", argument: "installation_id")
          end

          template_repo = Repository.find_by(id: template_repo_id)
          return Twirp::Error.not_found("Repository not found.") unless template_repo
          organization = Organization.find_by(id: organization_id)
          return Twirp::Error.not_found("Organization not found.") unless organization
          installation = IntegrationInstallation.find_by(id: installation_id)
          return Twirp::Error.not_found("Installation not found.") unless installation

          check_name = organization.find_repo_by_name(repo_name)
          if check_name
            repo_name = generate_name(repo_name, organization)
          end

          new_repo, reason, message = template_repo.clone_template_to(
            organization,
            actor: installation.bot,
            name: repo_name,
            copy_branches: true,
            description: "#{repo_name} created by GitHub Classroom",
            visibility: req.should_be_public ? Repository::PUBLIC_VISIBILITY : Repository::PRIVATE_VISIBILITY,
            reflog_data: {
              real_ip: env[:real_ip],
              user_login: installation.bot.login,
              user_agent: env[:user_agent],
              from: "GitHub Classroom",
              via: "template repository clone",
            },
            current_integration_context: {
              integration: installation,
              entry_point: :twirp_api_classroom_repositories_create_repo_from_template_api_handler
            }
          )
          if reason == :forbidden || reason == :unprocessable_entity
            return Twirp::Error.internal("Failed to copy template repository: #{message}")
          end

          { repo_id: new_repo.id }
        end

        # Public: Implementation of the CheckForUpstreamChanges Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Classroom::Repositories::V1::CheckForUpstreamChangesRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Classroom::Repositories::V1::CheckForUpstreamChangesResponse, or a Twirp::Error.
        def check_for_upstream_changes(req, env)
          # argument validations
          upstream_repo_id = id_argument(req.upstream_repo_id)
          return Twirp::Error.invalid_argument("must be non-empty", argument: "upstream_repo_id") unless upstream_repo_id
          child_repo_ids = req.child_repo_ids
          return Twirp::Error.invalid_argument("must be non-empty", argument: "child_repo_ids") if child_repo_ids.empty?

          upstream_repo = Repository.find_by(id: upstream_repo_id)
          return Twirp::Error.not_found("Upstream repository not found.") unless upstream_repo

          up_to_date_repo_ids = []
          sync_required_repo_ids = []
          child_repo_ids.each do |child_repo_id|

            child_repo = Repository.find_by(id: child_repo_id)
            return Twirp::Error.not_found("Child repository for id #{child_repo_id} not found.") unless child_repo

            # compare the upstream repo's default branch with the child repo's default branch
            comparison = GitHub::Comparison.build(
              base_repo: child_repo,
              head_repo: upstream_repo,
              base_revision: child_repo.default_branch,
              head_revision: upstream_repo.default_branch
            )

            # Were commits introduced on upstream repo after the common ancestor with child repo?
            if comparison.ahead?
              sync_required_repo_ids << child_repo_id
            else
              up_to_date_repo_ids << child_repo_id
            end
          end
          { sync_required_repo_ids: sync_required_repo_ids, up_to_date_repo_ids: up_to_date_repo_ids }
        end

        # Public: Implementation of the SyncForks Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Classroom::Repositories::V1::SyncForksRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Classroom::Repositories::V1::SyncForksResponse, or a Twirp::Error.
        def sync_forks(req, env)
          # argument validations
          upstream_repo_id = id_argument(req.upstream_repo_id)
          return Twirp::Error.invalid_argument("must be non-empty", argument: "upstream_repo_id") unless upstream_repo_id
          child_repo_ids = req.child_repo_ids
          return Twirp::Error.invalid_argument("must be non-empty", argument: "child_repo_ids") if child_repo_ids.empty?

          installation_id = id_argument(req.installation_id)
          return Twirp::Error.invalid_argument("must be non-empty", argument: "installation_id") unless installation_id

          # existence validations
          upstream_repo = Repository.find_by(id: upstream_repo_id)
          return Twirp::Error.not_found("Upstream repository not found") unless upstream_repo
          installation = IntegrationInstallation.find_by(id: installation_id)
          return Twirp::Error.not_found("Installation not found") unless installation

          repo_sync_statuses = []
          child_repo_ids.each do |child_repo_id|
            child_repo = Repository.find_by(id: child_repo_id)
            return Twirp::Error.not_found("Child repository for id #{child_repo_id} not found.") unless child_repo

            comparison = GitHub::Comparison.build(
              base_repo: child_repo,
              head_repo: upstream_repo,
              base_revision: child_repo.default_branch,
              head_revision: upstream_repo.default_branch
            )

            unless comparison.pull_requestable?
              repo_sync_statuses << {
                repo_id: child_repo.id,
                success: false,
                error_message: "Comparison not pull requestable."
              }
              next
            end

            pr = comparison.build_pull_request(user: installation.bot)
            pr.issue = child_repo.issues.build(
              user_id: installation.bot,
              title: "GitHub Classroom: Sync Assignment",
              body: "This pull request was automatically generated by GitHub Classroom to sync with the upstream assignment repository.\n\n"\
              "Merge this pull request to sync your assignment repository with your intstructors latest changes.\n\n"\
              "If you have any questions or concerns, please contact your instructor."
            )

            if pr.save
              repo_sync_statuses << {
                repo_id: child_repo.id,
                pull_request_id: pr.id,
                success: true
              }
            else
              repo_sync_statuses << {
                repo_id: child_repo.id,
                success: false,
                error_message: pr.errors.full_messages.join(", ")
              }
            end
          end
          { repo_sync_statuses: repo_sync_statuses }
        end

        # Public: Implementation of the CheckCollaborator Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Classroom::Repositories::V1::CheckCollaboratorRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Classroom::Repositories::V1::CheckCollaboratorResponse, or a Twirp::Error.
        def check_collaborator(req, env)
          github_repo_id = id_argument(req.github_repo_id)
          return Twirp::Error.invalid_argument("must be non-empty", argument: "github_repo_id") unless github_repo_id

          github_user_id = id_argument(req.github_user_id)
          return Twirp::Error.invalid_argument("must be non-empty", argument: "github_user_id") unless github_user_id

          repo = Repository.find_by(id: github_repo_id)
          return Twirp::Error.not_found("Repository not found.") unless repo

          user = User.find_by(id: github_user_id)
          return Twirp::Error.not_found("User not found.") unless user

          user_is_collaborator = repo.direct_or_team_member_ids(
            viewer: user,
            immediate_only: false,
          ).include?(user.id)

          { user_is_collaborator: user_is_collaborator }
        end


        private

        # Private: Returns Repositories for each of the given repo IDs.
        #
        # ids - Repositoriry IDs in a Google::Protobuf::RepeatedField
        #
        # Returns an ActiveRecord::Relation of Repository, or a Twirp::Error.
        def get_repos_by_id(ids, argument_name:, limit:)
          if ids.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: argument_name)
          end

          if ids.size > limit
            return Twirp::Error.invalid_argument("must have a length <= #{limit}",
              argument: argument_name)
          end

          # ids is a Google::Protobuf::RepeatedField, and we need to call #to_a to get a value
          # usable by ActiveRecord:
          Repository.where(id: ids.to_a)
        end

        def generate_name(repo_name, owner, attempt: 1)
          raise ArgumentError, "Failed to copy template repository: Unable to generate a unique name for the copied repository" if attempt > MAX_NAME_GENERATION_ATTEMPTS

          digit_count = attempt.to_s.length

          if repo_name.length > (99 - digit_count)
            repo_name = repo_name[0..(98 - digit_count)]
          end

          new_name = "#{repo_name}-#{attempt}"
          if owner.find_repo_by_name(new_name)
            generate_name(repo_name, owner, attempt: attempt + 1)
          else
            new_name
          end
        end
      end
    end
  end
end
