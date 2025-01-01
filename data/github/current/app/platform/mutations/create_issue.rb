# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateIssue < Platform::Mutations::Base
      include Scientist
      include Platform::Mutations::Shared::CurrentActor

      description "Creates a new issue."

      minimum_accepted_scopes ["public_repo"]

      argument :repository_id, ID, "The Node ID of the repository.", required: true, loads: Objects::Repository
      argument :title, String, "The title for the issue.", required: true
      argument :body, String, "The body for the issue description.", required: false
      argument :assignee_ids, [ID], "The Node ID of assignees for this issue.", required: false, loads: Interfaces::Actor
      argument :milestone_id, ID, "The Node ID of the milestone for this issue.", required: false, loads: Objects::Milestone
      argument :label_ids, [ID], "An array of Node IDs of labels for this issue.", required: false, loads: Objects::Label
      argument :project_ids, [ID], "An array of Node IDs for projects associated with this issue.", required: false, loads: Objects::Project
      argument :issue_template, String, "The name of an issue template in the repository, assigns labels and assignees from the template to the issue",
        required: false
      argument :issue_type_id, ID, "The Node ID of the issue type for this issue", required: false
      argument :parent_issue_id, ID, "The Node ID of the parent issue to add this new issue to", required: false, loads: Objects::Issue, visibility: :public
      argument :issue_fields, [Inputs::IssueFieldCreateOrUpdateInput], "An array of issue fields to set on the issue during creation", required: false
      argument :position, [Integer], "The position of the list item to replace in the parent issue, formatted as [list_index, item_index]. Nested lists are treated as the next list in the sequence", required: false, visibility: :internal
      argument :is_duplicated, Boolean, "Indicates if the issue is created by duplicating an existing issue.", required: false, visibility: :internal

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

        res = Issues.domain.create(
          attributes,
          current_actor(repository),
          viewer: context[:viewer],
          integration: integration,
        )
        case res
        when GH::Result::Ok
          issue = res.value
          errors = []

          # Check if the Copilot SWE bot is assigned to the issue
          copilot_swe_bot_assigned = issue.assignees.any? do |assignee|
            assignee.is_a?(Bot) && assignee.slug == Apps::Privileged::CopilotSWEAgent::SLUG
          end

          if copilot_swe_bot_assigned && context[:viewer]&.feature_flag_enabled?(:issues_copilot_cross_repo_assign, default: false)
            result = Issues.domain.copilot.trigger_copilot_job_for_new_issue(
              actor: context[:viewer],
              issue: T.cast(issue, Issue),
              repository: repository,
              user_session: context[:user_session]
            )

            if !result.ok?
              errors << {
                path: %w(input assigneeIds),
                message: "The issue was successfully created but failed to trigger Copilot job."
              }
            end
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

      def only_labels_on_repository(repository, labels)
        repository.labels.merge(Label.with_name(labels.map(&:name)))
      end

      def different_labels_from_template(labels, template_labels)
        return false if labels.nil? && template_labels.nil?
        return true if labels.nil? || template_labels.nil?

        # Name is the unique attribute we care about, so check this.
        labels.map(&:name).sort != template_labels.map(&:name).sort
      end

      def different_assignees_from_template(assignees, template_assignees)
        return false if assignees.nil? && template_assignees.nil?
        return true if assignees.nil? || template_assignees.nil?

        # Login is unique so we just need to check this
        assignees.map(&:display_login).sort != template_assignees.map(&:display_login).sort
      end

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
    end
  end
end
