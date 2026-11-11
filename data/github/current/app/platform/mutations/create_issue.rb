# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateIssue < Platform::Mutations::Base
      include Scientist
      include Platform::Mutations::Shared::CurrentActor
      include Platform::Helpers::Agentic

      description "Creates a new issue."

      minimum_accepted_scopes ["public_repo"]

      argument :repository_id, ID, "The Node ID of the repository.", required: true, loads: Objects::Repository
      argument :title, String, "The title for the issue.", required: true
      argument :body, String, "The body for the issue description.", required: false
      argument :assignee_ids, [ID], "The Node ID of assignees for this issue.", required: false, loads: Interfaces::Actor
      argument :milestone_id, ID, "The Node ID of the milestone for this issue.", required: false, loads: Objects::Milestone
      argument :label_ids, [ID], "An array of Node IDs of labels for this issue.", required: false, loads: Objects::Label
      argument :project_ids, [ID], "An array of Node IDs for projects associated with this issue.", required: false, loads: Objects::Project
      argument :project_v2_ids, [ID], "An array of Node IDs for Projects V2 associated with this issue.", required: false, loads: Objects::ProjectV2, prepare: ->(ids, _ctx) { ids&.uniq }
      argument :issue_template, String, "The name of an issue template in the repository, assigns labels and assignees from the template to the issue",
        required: false
      argument :issue_type_id, ID, "The Node ID of the issue type for this issue", required: false
      argument :parent_issue_id, ID, "The Node ID of the parent issue to add this new issue to", required: false, loads: Objects::Issue, visibility: :public
      argument :issue_fields, [Inputs::IssueFieldCreateOrUpdateInput], "An array of issue fields to set on the issue during creation", required: false
      argument :position, [Integer], "The position of the list item to replace in the parent issue, formatted as [list_index, item_index]. Nested lists are treated as the next list in the sequence", required: false, visibility: :internal
      argument :is_duplicated, Boolean, "Indicates if the issue is created by duplicating an existing issue.", required: false, visibility: :internal

      # Internal-only Copilot assignment input (legacy / internal callers)
      argument :copilot_assignment, Inputs::CopilotAssignmentInput, "Internal configuration for assigning Copilot to this issue.", required: false, visibility: :internal
      # Public Copilot assignment input behind feature flag
      argument :agent_assignment, Inputs::AgentAssignmentInput, "Configuration for assigning Copilot to this issue.", required: false, visibility: :public, feature_flag: :issues_copilot_assignment_api_support

      error_fields
      field :issue, Objects::Issue, "The new issue.", null: true

      extras [:execution_errors]

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, repository:, **inputs)
        permission.async_owner_if_org(repository).then do |org|
          permission.access_allowed? :open_issue, resource: repository, repo: repository, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true
        end
      end

      def resolve(execution_errors:, repository:, **inputs)
        attributes = Issues::CreateIssueAttributes.new(
          title: inputs[:title],
          body: inputs[:body],
          repository: repository,
          is_duplicated: inputs.fetch(:is_duplicated, false),
          template_name: inputs[:issue_template],
          assignees: inputs[:assignees],
          labels: inputs[:labels],
          milestone: inputs[:milestone],
          issue_type: Helpers::IssueTypes.load_by_id(inputs[:issue_type_id], context),
          issue_fields: prepare_issue_fields(inputs[:issue_fields]),
        )

        parent_issue = inputs[:parent_issue]
        if parent_issue && inputs[:position].nil?
          context[:recalculate_sub_issues_summary_issue_id] = parent_issue.id
          attributes.parent_issue = parent_issue
        end

        if @context[:permission].integration_user_request?
          integration = @context[:integration]
        end

        # Check if Copilot or third-party agents should be triggered
        copilot_context = nil
        copilot_validation_error = nil
        public_assignment = nil

        assignee_bots = inputs[:assignees]&.grep(Bot) || []
        agents_platform_enabled = repository.feature_flag_enabled?(:issues_create_3p_support, default: false)

        if assignee_bots.any?
          copilot_bot_ids = copilot_bot_ids_from(assignee_bots)
          agentic_bot_ids = agents_platform_enabled ? agentic_bot_ids_from(assignee_bots) : []
          bot_ids_requiring_context = if agents_platform_enabled
            (agentic_bot_ids + copilot_bot_ids).uniq
          else
            copilot_bot_ids
          end

          if bot_ids_requiring_context.any?

            # Prefer public variant when provided, fallback to internal
            # Only honor public assignment input if feature flag exposes it
            public_assignment = if context[:viewer]&.feature_flag_enabled?(:issues_copilot_assignment_api_support, default: false)
              inputs[:agent_assignment]
            end
            copilot_assignment = public_assignment || inputs[:copilot_assignment]
            target_repo = copilot_assignment&.target_repository

            if target_repo.present? && (!target_repo.writable_by?(context[:viewer]) || !target_repo.writable?)
              copilot_validation_error = "Could not assign agent: target repository is not writable."
            else
              begin
                # Don't set agent_id here - CreateIssueOrchestration will handle multiple agents
                copilot_attributes = get_copilot_attributes(copilot_assignment, repository, context[:ip], viewer: context[:viewer])
                request_token_value = context[:request_token]&.to_s

                encrypted_token = if request_token_value.present?
                  GitHub.encrypt_and_encode_capi_token(request_token_value)
                else
                  CopilotSessions::CopilotApiToken.get_encrypted(
                    user: context[:viewer],
                    entry_point: :create_issue_mutation,
                    user_session: context[:user_session]
                  )
                end

                copilot_context = {
                  request_token: encrypted_token.to_s,
                  attributes: copilot_attributes
                }
                # Only include user_session_id for UI requests (no request_token) for retry logic
                copilot_context[:user_session_id] = context[:user_session]&.id if request_token_value.blank?
              rescue CopilotSessions::CopilotApiToken::IntegrationUnavailableError
                # Copilot SWE Agent integration is not available (e.g., on GHES)
                # Skip agent assignment - copilot_context remains nil
              end
            end
          end
        end

        res = Issues.domain.create(
          attributes,
          current_actor(repository),
          viewer: context[:viewer],
          integration: integration,
          copilot_context: copilot_context,
        )
        case res
        when GH::Result::Ok
          issue = res.value
          errors = []

          # Emit analytics event if issue fields were set during creation
          if inputs[:issue_fields].present? && FeatureFlag.vexi.enabled?(:issue_fields_analytics, context[:viewer], default: false)
            org_name = repository.owner.display_login
            repo_name = repository.name
            GlobalInstrumenter.instrument("analytics.event",
              actor: context[:viewer],
              category: "issue_fields_usage",
              action: "set_fields_on_create",
              label: "source:api,mutation:createIssue,field_count:#{inputs[:issue_fields].size},org:#{org_name},repo:#{repo_name}"
            )
          end

          if copilot_validation_error
            assignment_path_prefix = public_assignment ? "agentAssignment" : "copilotAssignment"
            errors << {
              path: ["input", assignment_path_prefix, "targetRepositoryId"],
              message: copilot_validation_error
            }
          end

          if inputs[:position]
            if parent_issue.nil?
              errors << {
                path: %w(input parentIssueId),
                message: "The issue was successfully created but no parentIssueId was provided with the position, so we were not able to update the parent issue at this time.",
              }
            elsif !parent_issue.update_issue_body_after_convert_task(inputs[:position], issue, @context[:viewer])
              errors << {
                path: %w(input position),
                message: "The issue was successfully created but we are unable to update the parent issue at this time.",
              }
            end
          end

          if inputs[:project_v2s].present?
            errors.concat(add_issue_to_projects(issue, inputs[:project_v2s]).sync)
          end

          { issue: issue, errors: errors }
        when GH::Result::Error::LockedForRebalance
          raise Errors::Unprocessable.new("This milestone is temporarily locked for maintenance. Please try again.")
        when GH::Result::Error::Validation
          Platform::UserErrors.append_legacy_mutation_model_errors_to_context(res.model, execution_errors)
          { issue: nil, errors: Platform::UserErrors.mutation_errors_for_model(res.model, translate: { parent: "parentIssueId" }) }
        when GH::Result::Error::NotFound
          raise Errors::NotFound.new(res.message)
        when GH::Result::Error::ContentAuthorizationError
          raise Errors::Unprocessable.new(T.cast(res.authorization, ContentAuthorizer).error_messages)
        when GH::Result::Error::Forbidden
          raise Errors::Forbidden.new(res.message)
        when GH::Result::Error::Gone
          raise Errors::Forbidden.new(res.message)
        when GH::Result::Error
          { issue: nil, errors: [{ path: %w(input), message: "Failed to create the issue." }] }
        end
      end

      private

      def prepare_issue_fields(issue_field_inputs)
        return if issue_field_inputs.nil?

        issue_field_attributes = []

        issue_field_inputs.each do |issue_field_input|
          issue_field_global_id = issue_field_input.field_id
          _, issue_field_database_id = Platform::Helpers::NodeIdentification.from_global_id(issue_field_global_id)

          field_value_attributes = if issue_field_input.text_value
            Issues::IssueFieldTextValueAttributes.new(
              field_id: issue_field_database_id.to_i,
              text_value: issue_field_input.text_value
            )
          elsif issue_field_input.single_select_option_id
            _, issue_field_option_database_id = Platform::Helpers::NodeIdentification.from_global_id(issue_field_input.single_select_option_id)
            Issues::IssueFieldSingleSelectValueAttributes.new(
              field_id: issue_field_database_id.to_i,
              option_id: issue_field_option_database_id&.to_i
            )
          elsif issue_field_input.date_value
            Issues::IssueFieldDateValueAttributes.new(
              field_id: issue_field_database_id.to_i,
              date_value: issue_field_input.date_value
            )
          elsif issue_field_input.number_value
            Issues::IssueFieldNumberValueAttributes.new(
              field_id: issue_field_database_id.to_i,
              number_value: issue_field_input.number_value
            )
          else
            raise Errors::Validation.new("You must provide a valid value to match the selected type.")
          end

          issue_field_attributes << field_value_attributes
        end

        issue_field_attributes
      end

      def add_issue_to_projects(issue, projects)
        permission_checks = projects.map do |project|
          project.async_viewer_can_write?(context[:viewer])
        end

        statuses = []
        errors = []

        Promise.all(permission_checks).then do |results|
          projects.zip(results).each do |project, can_write|
            unless can_write
              errors << {
                path: %w(input projectV2Ids),
                message: "The issue was successfully created but you do not have permission to add it to one or more projects."
              } unless errors.any?

              next
            end

            statuses << T.cast(project, MemexProject).bulk_add_multiple_items(
              creator: context[:viewer],
              issues_or_pulls: [T.cast(issue, Issue)],
            )
          end

          if statuses.any? { |s| s.nil? || !s.pending? }
            errors << {
              path: %w(input projectV2Ids),
              message: "The issue was successfully created but failed to add to one or more projects."
            }
          end

          errors
        end
      end
    end
  end
end
