# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateIssue < Platform::Mutations::Base
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
      argument :issue_fields, [Inputs::IssueFieldSetOnIssueCreateInput], "An array of issue fields to set on the issue during creation", required: false, visibility: :under_development
      argument :position, [Integer], "The position of the list item to replace in the parent issue, formatted as [list_index, item_index]. Nested lists are treated as the next list in the sequence", required: false, visibility: :internal

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
        )

        parent_issue = inputs[:parent_issue]

        issue_type = Helpers::IssueTypes.load_by_id(inputs[:issue_type_id], context) if inputs[:issue_type_id].present?

        context[:permission].authorize_content(:issue, :create, repo: repository)

        # Don't let non collabs set these attributes on new issues
        unless context[:permission].access_allowed?(:set_collab_only_attributes_on_new_issue, repo: repository, current_org: nil, allow_integrations: true, allow_user_via_granular_actor: true, raise_on_error: false)
          inputs.delete_if { |key, _value| [:assignee, :assignees, :milestone, :labels].include?(key) }
        end

        can_add_metadata = repository.writable_by?(context[:viewer]) ||
          context[:actor].can_have_granular_permissions? ||
          repository.role_based_access_level(context[:viewer]) == :triage

        if !repository.has_issues?
          raise Errors::Forbidden.new("Issues has been disabled in this repository.")
        end

        if inputs[:issue_template]
          if issue_template = repository.preferred_issue_templates(context[:viewer]).find_by_name(inputs[:issue_template])
            # If we have a valid template, we want to set it's values as default assignees/labels unless we explicitly state them below.
            attributes.assignees = issue_template.assignees
            attributes.labels = only_labels_on_repository(repository, issue_template.labels).to_a
            attributes.body_template_name = issue_template.filename
          else
            raise Errors::NotFound.new("Could not find an issue template with name #{inputs[:issue_template]}")
          end
        end

        if inputs[:assignees]
          if can_add_metadata
            attributes.assignees = inputs[:assignees]
          # They deferred from the default template data, so we need to check if they have permission to do so
          elsif different_assignees_from_template(attributes.assignees, inputs[:assignees])
            raise Errors::Forbidden.new("You don't have permission to assign issues in this repository.")
          end
        end

        if inputs[:labels]
          if can_add_metadata
            attributes.labels = only_labels_on_repository(repository, inputs[:labels]).to_a
          # They deferred from the default template data, so we need to check if they have permission to do so
          elsif different_labels_from_template(attributes.labels, inputs[:labels])
            raise Errors::Forbidden.new("You don't have permission to add labels in this repository.")
          end
        end

        if inputs[:milestone]
          if can_add_metadata
            attributes.milestone = inputs[:milestone]
          else
            raise Errors::Forbidden.new("You don't have permission to add to milestones in this repository.")
          end
        end

        if issue_type
          using_template = issue_template&.type.present?

          unless can_add_metadata
            unless using_template
              raise Errors::Forbidden.new("You don't have permission to set the issue type in this repository")
            end

            # It is possible inside the template to declare the type in all lowercase, and therefore we need to make this check case-insensitive.
            if issue_type.name.downcase != issue_template.type.downcase
              raise Errors::Forbidden.new("You cannot override the issue type assigned to the template")
            end
          end

          attributes.issue_type = issue_type
        end

        if parent_issue && inputs[:position].nil?
          unless SubIssuesFeature.enabled?(repository, actor: context[:viewer])
            raise Errors::Forbidden.new("You may not create sub-issues")
          end
          unless parent_issue.viewer_can_create_sub_issues?(context[:viewer])
            raise Errors::Forbidden.new("You may not create a sub-issue for a parent issue with id '#{parent_issue.global_relay_id}'.")
          end
          context[:recalculate_sub_issues_summary_issue_id] = parent_issue.id
          attributes.parent_issue = parent_issue
        end

        if inputs[:issue_fields]
          unless IssueFieldsFeature.enabled?(repository.owner, actor: context[:viewer])
            raise Errors::Forbidden.new("Issue fields are not enabled for you in this organization.")
          end

          inputs[:issue_fields].each do |issue_field_input|
            issue_field_global_id = issue_field_input.field_id
            _, issue_field_database_id = Platform::Helpers::NodeIdentification.from_global_id(issue_field_global_id)
            _, issue_field_option_database_id = Platform::Helpers::NodeIdentification.from_global_id(issue_field_input.single_select_option_id) if issue_field_input.single_select_option_id

            if !issue_field_input.text_value && !issue_field_input.single_select_option_id
              raise Errors::Validation.new("You must provide either text value (to set a text field) or a single select option ID (to set a single select field).")
            end

            T.must(attributes.issue_fields) << Issues::CreateIssueFieldValueAttributes.new(
              field_id: issue_field_database_id.to_i,
              text_value: issue_field_input.text_value,
              single_select_option_id: issue_field_option_database_id ? issue_field_option_database_id.to_i : nil
            )
          end
        end

        if @context[:permission].integration_user_request?
          integration = @context[:integration]
        end

        res = Issues.domain.create(attributes, context[:viewer], integration: integration, skip_permission_checks: true)
        case res
        when GH::Result::Ok
          issue = res.value
          errors = []
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

      sig { params(parent_issue: ::Issue, sub_issue_relationship: SubIssue).returns(T.nilable(StandardError)) }
      def persist_sub_issue_relationship(parent_issue, sub_issue_relationship)
        begin
          parent_issue.prioritize_dependent!(sub_issue_relationship, position: :bottom)
        rescue GitHub::Prioritizable::Context::LockedForRebalance
          return Errors::Unprocessable.new("The parent sub-issue list is temporarily locked for maintenance. Please try again.")
        rescue SubIssue::MaximumHeightError => e
          return Platform::Errors::Validation.new(e.message)
        end
        if !sub_issue_relationship.persisted?
          sub_issue_relationship.errors.delete(:priority)
          return Platform::Errors::Validation.new(sub_issue_relationship.errors.full_messages.to_sentence)
        end
        nil
      end
    end
  end
end
