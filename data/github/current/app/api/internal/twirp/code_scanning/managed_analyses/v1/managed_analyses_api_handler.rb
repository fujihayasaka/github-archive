# typed: true
# frozen_string_literal: true

require "monolith-twirp-code_scanning-managed_analyses"

module Api::Internal::Twirp::CodeScanning
  module ManagedAnalyses
    module V1
      # Handler for the MonolithTwirp::CodeScanning::ManagedAnalyses::V1::ManagedAnalysesAPIService
      class ManagedAnalysesAPIHandler < Api::Internal::Twirp::Handler
        include GitHub::Memoizer

        allow_access_for :client, allowed_clients: ["turboscan"]
        handles_service MonolithTwirp::CodeScanning::ManagedAnalyses::V1::ManagedAnalysesAPIService
        connected_to_writing_for :cancel_queued_runs, :create_check_for_p_r
        exempt_from_tenant_context_requirement(
          only: %i[
            get_code_scanning_bot_info
          ]
        )

        resolve_tenant_context only: %i[
          are_required_services_enabled
          cancel_queued_runs
          create_check_for_p_r
          is_code_q_l_required
        ] do |req, _env|
          repository = ::Repositories::Public.find_active(req.repository_id)
          repository&.owner&.business
        end

        # Public: Implementation of the AreRequiredServicesEnabled Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::CodeScanning::ManagedAnalyses::V1::AreRequiredServicesEnabledRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::CodeScanning::ManagedAnalyses::V1::AreRequiredServicesEnabledResponse, or a Twirp::Error.
        def are_required_services_enabled(req, env)
          repository_id = id_argument(req.repository_id)
          return Twirp::Error.invalid_argument("must be non-empty", argument: "repository_id") unless repository_id

          repo = T.cast(::Repositories.domain.by_id(repository_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
          return Twirp::Error.not_found("repository not found") unless repo
          return { enabled: false } if repo.deleted? || repo.archived?

          # Are required services enabled?
          # This checks for things like GHAS and Actions that we need to revalidate
          # before we can run an analysis.
          resp = { enabled: CodeScanning::AutoCodeql.required_services_enabled?(repo) }

          # Try to get the tenant slug for the repository
          if GitHub.multi_tenant_enterprise?
            tenant = Business.find_by(id: repo.tenant_id)
            resp[:tenant_slug] = tenant&.slug
            resp[:tenant_id] = tenant&.id
          end

          resp[:codeql_packs] = CodeScanningOrgConfigurations.codeql_packs(repo)

          resp
        end

        # Public: Implementation of the CancelQueuedRuns Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::CodeScanning::ManagedAnalyses::V1::CancelQueuedRunsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::CodeScanning::ManagedAnalyses::V1::CancelQueuedRunsResponse, or a Twirp::Error.
        def cancel_queued_runs(req, env)
          repository_id = id_argument(req.repository_id)
          return Twirp::Error.invalid_argument("must be non-empty", argument: "repository_id") unless repository_id

          return Twirp::Error.invalid_argument("must be non-empty", argument: "workflow_run_id") if req.workflow_run_id.empty?
          workflow_run_ids = req.workflow_run_id.map { |id| id_argument(id) }.compact
          return Twirp::Error.invalid_argument("must contain valid ids", argument: "workflow_run_id") if workflow_run_ids.empty?
          results = []

          workflow_runs = Actions::WorkflowRun.where(repository_id: repository_id).where(id: workflow_run_ids).all
          if workflow_runs.length != workflow_run_ids.length
            # Some workflows could not be found, so we return them as failed and stat the event
            missing_workflow_run_ids = workflow_run_ids - workflow_runs.map(&:id)
            missing_workflow_run_ids.each do |id|
              results << { workflow_run_id: id,  status: "completed", conclusion: "failure" }
              GitHub.dogstats.increment("code_scanning.managed_analyses.cancel_queued_runs.run", tags: ["action:missing"])
            end
          end

          workflow_runs.each do |run|
            if !run.workflow.dynamic_code_scanning_workflow?
              results << { workflow_run_id: run.id, error: "Run is not a code scanning workflow run" }
              GitHub.dogstats.increment("code_scanning.managed_analyses.cancel_queued_runs.run", tags: ["action:invalid"])
            elsif run.check_suite.nil?
              results << { workflow_run_id: run.id, error: "Check suite for the run is missing" }
              GitHub.dogstats.increment("code_scanning.managed_analyses.cancel_queued_runs.run", tags: ["action:invalid"])
              GitHub.logger.error(
                "Check suite for the run is missing",
                "code.namespace": "CodeScanning",
                "code.function": "cancel_queued_runs",
                "gh.repo.id": repository_id,
                "gh.workflow_run.id": run.id,
              )
            elsif run.queued?
              # Try to cancel the run if it is queued
              result = run.check_suite.cancel(actor: code_scanning_app.bot)
              if result.call_succeeded?
                # We return the status/conclusion as is even though it is going to change very soon
                # now that we've cancelled. At this moment this is still the state in the db
                results << { workflow_run_id: run.id, status: run.status, conclusion: run.conclusion }
                GitHub.dogstats.increment("code_scanning.managed_analyses.cancel_queued_runs.run", tags: ["action:cancelled"])
              else
                # If we couldn't cancel the run, we return a failure to prevent the repository from being stuck in a bad state
                results << { workflow_run_id: run.id, status: "completed", conclusion: "failure" }
                GitHub.dogstats.increment("code_scanning.managed_analyses.cancel_queued_runs.run", tags: ["action:failed"])
              end
            else
              results << { workflow_run_id: run.id, status: run.status, conclusion: run.conclusion }
              GitHub.dogstats.increment("code_scanning.managed_analyses.cancel_queued_runs.run", tags: ["action:ignored"])
            end
          end

          { workflow_run_status: results }
        end

        # req - The Twirp request as a MonolithTwirp::CodeScanning::ManagedAnalyses::V1::CreateCheckForPRRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::CodeScanning::ManagedAnalyses::V1::CreateCheckForPRResponse, or a Twirp::Error.
        def create_check_for_p_r(req, env)
          repository_id = id_argument(req.repository_id)
          return Twirp::Error.invalid_argument("must be non-empty", argument: "repository_id") unless repository_id

          pull_request_id = id_argument(req.pull_request_id)
          return Twirp::Error.invalid_argument("must be non-empty", argument: "pull_request_id") unless pull_request_id

          pr = PullRequest.find(req.pull_request_id)
          GitHub.logger.info(
            "Creating artificial checkrun for PR",
            "code.namespace": "CodeScanning",
            "code.function": "create_check_for_p_r",
            "gh.repo.id": repository_id,
            "gh.pull_request.id": pull_request_id,
            "gh.pull_request.number": pr.number,
          )

          return Twirp::Error.aborted("repo is not enabled for code-scanning") unless pr.repository&.code_scanning_enabled?

          cs_suite = CheckRun.create_code_scanning_check_suite(
            repository: pr.repository,
            annotated_commit_oid: pr.head_sha,
            analyzed_commit_oid: pr.head_sha,
            ref: "refs/pull/#{pr.number}/head",
            base_ref: "refs/heads/#{pr.base_ref_name}",
            base_sha: pr.base_sha
          )
          check_runs = CheckRun.create_code_scanning_check_runs(
            check_suite: cs_suite.check_suite,
            tool_names: ["CodeQL"]
          )

          CreateCodeScanningAnnotationsJob.perform_later(check_run_id: check_runs[0].id, reason: :forced_by_turboscan)

          { check_suite_id: cs_suite.check_suite.id }
        end

        # Public: Implementation of the GetCodeScanningBotInfo Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::CodeScanning::ManagedAnalyses::V1::GetCodeScanningBotInfoRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::CodeScanning::ManagedAnalyses::V1::GetCodeScanningBotInfoResponse, or a Twirp::Error.
        def get_code_scanning_bot_info(req, env)
          bot = code_scanning_app.bot
          bot_grid = GitHub.enterprise? ? bot.global_relay_id : bot.next_global_id
          { grid: bot_grid, login: bot.login }
        end

        # Public: Implementation of the IsCodeQLRequired Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::CodeScanning::ManagedAnalyses::V1::IsCodeQLRequiredRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::CodeScanning::ManagedAnalyses::V1::IsCodeQLRequiredResponse, or a Twirp::Error.
        def is_codeql_required?(req, env)
          repository_id = id_argument(req.repository_id)
          return Twirp::Error.invalid_argument("must be non-empty", argument: "repository_id") unless repository_id

          return Twirp::Error.invalid_argument("must be non-empty", argument: "ref") unless req.ref.present?

          repository = ::Repositories::Public.get_active_or_deleted(repository_id)
          return Twirp::Error.not_found("repository not found") unless repository.present?

          return { required: false } if repository.deleted? || repository.archived?
          return { required: true } if "refs/heads/#{repository.default_branch}" == req.ref

          ref = repository.heads.find(req.ref.b)

          return { required: false } unless ref&.exists?
          return { required: true } if ref.protected_branch.present?

          policy_evaluator = BranchRuleEvaluator.for_repository_with_branch_name(repository, ref.name)

          return { required: true } if policy_evaluator.present? && policy_evaluator.codeql_required?

          { required: false }
        end

        # I checked the Ruby Protobuf docs and couldn't find an obvious way to override the ugly generated method name
        alias :is_code_q_l_required :is_codeql_required?

        private

        memoize def code_scanning_app
          Apps::Privileged.integration(:code_scanning)
        end
      end
    end
  end
end
