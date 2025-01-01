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
      argument :assignee_ids, [ID], "The Node ID for the user assignee for this issue.", required: false, loads: Objects::User
      argument :milestone_id, ID, "The Node ID of the milestone for this issue.", required: false, loads: Objects::Milestone
      argument :label_ids, [ID], "An array of Node IDs of labels for this issue.", required: false, loads: Objects::Label
      argument :project_ids, [ID], "An array of Node IDs for projects associated with this issue.", required: false, loads: Objects::Project
      argument :issue_template, String, "The name of an issue template in the repository, assigns labels and assignees from the template to the issue",
        required: false
      argument :issue_type_id, ID, "The Node ID of the issue type for this issue", required: false, loads: Objects::IssueType, visibility: :under_development
      argument :parent_issue_id, ID, "The Node ID of the parent issue to add this new issue to", required: false, loads: Objects::Issue, visibility: :public, feature_flag: :sub_issues
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
        attributes = { title: inputs[:title], body: inputs[:body] }

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
            attributes[:assignees] = issue_template.assignees
            attributes[:labels] = only_labels_on_repository(repository, issue_template.labels)
            attributes[:body_template_name] = issue_template.filename
          else
            raise Errors::NotFound.new("Could not find an issue template with name #{inputs[:issue_template]}")
          end
        end

        if inputs[:assignees]
          if can_add_metadata
            attributes[:assignees] = inputs[:assignees]
          # They deferred from the default template data, so we need to check if they have permission to do so
          elsif different_assignees_from_template(attributes[:assignees], inputs[:assignees])
            raise Errors::Forbidden.new("You don't have permission to assign issues in this repository.")
          end
        end

        if inputs[:labels]
          if can_add_metadata
            attributes[:labels] = only_labels_on_repository(repository, inputs[:labels])
          # They deferred from the default template data, so we need to check if they have permission to do so
          elsif different_labels_from_template(attributes[:labels], inputs[:labels])
            raise Errors::Forbidden.new("You don't have permission to add labels in this repository.")
          end
        end

        if inputs[:milestone]
          if can_add_metadata
            attributes[:milestone] = inputs[:milestone]
          else
            raise Errors::Forbidden.new("You don't have permission to add to milestones in this repository.")
          end
        end

        if inputs[:issue_type]
          using_template = issue_template&.type.present?

          unless can_add_metadata
            unless using_template
              raise Errors::Forbidden.new("You don't have permission to set the issue type in this repository")
            end

            # It is possible inside the template to declare the type in all lowercase, and therefore we need to make this check case-insensitive.
            if inputs[:issue_type].name.downcase != issue_template.type.downcase
              raise Errors::Forbidden.new("You cannot override the issue type assigned to the template")
            end
          end

          attributes[:issue_type] = inputs[:issue_type]
        end
        issue = repository.issues.build(attributes.reverse_merge(repository_id: repository.id))
        issue.user = context[:viewer]
        if inputs[:projects]
          inputs[:projects].each do |project|
            if project.writable_by?(context[:viewer])
              add_project_card_helper = Platform::Helpers::AddProjectCard.new(project, context)
              add_project_card_helper.check_permissions
              add_project_card_helper.check_issue_project_owner(issue)
              issue.cards.build(creator: context[:viewer], project: project, content: issue)
            else
              raise Errors::Forbidden.new("You don't have permission to add to project with id '#{project.global_relay_id}'.")
            end
          end
        end

        if inputs[:parent_issue] && inputs[:position].nil?
          parent_issue = inputs[:parent_issue]
          unless SubIssuesFeature.enabled?(repository, actor: context[:viewer])
            raise Errors::Forbidden.new("You may not create sub-issues")
          end
          unless parent_issue.viewer_can_create_sub_issues?(context[:viewer])
            raise Errors::Forbidden.new("You may not create a sub-issue for a parent issue with id '#{parent_issue.global_relay_id}'.")
          end
          context[:recalculate_sub_issues_summary_issue_id] = parent_issue.id

          begin
            relationship = parent_issue.add_sub_issue!(issue, context[:viewer].id)

            if !relationship&.persisted?
              raise Platform::Errors::Validation.new("An error occured while adding the sub-issue to the parent issue. #{relationship.errors.full_messages.to_sentence}")
            end
          # Unlike most sub-issues validations, max-height errors are raised in the `after_create` callback.
          rescue SubIssue::MaximumHeightError => e
            raise Platform::Errors::Validation.new("An error occured while adding the sub-issue to the parent issue. #{e.message}")
          rescue GitHub::Prioritizable::Context::LockedForRebalance
            raise Errors::ServiceUnavailable.new("Parent sub-issue list is temporarily locked for maintenance. Please try again.")
          end
        end

        if @context[:permission].integration_user_request?
          issue.modifying_integration = @context[:integration]
        end

        begin
          if issue.save
            errors = []

            if inputs[:position]
              if inputs[:parent_issue].nil?
                raise Errors::ArgumentError.new("Updating a parent issue requires the parentIssueId.")
              end

              unless inputs[:parent_issue].update_issue_body_after_convert_task(inputs[:position], issue, @context[:viewer])
                errors << {
                  path: %w(input position),
                  message: "The issue was successfully created but we are unable to update the parent issue at this time.",
                }
              end
            end
            { issue: issue, errors: errors }
          else
            Platform::UserErrors.append_legacy_mutation_model_errors_to_context(issue, execution_errors)

            { issue: nil, errors: Platform::UserErrors.mutation_errors_for_model(issue) }
          end
        rescue GitHub::Prioritizable::Context::LockedForRebalance
          raise Errors::Unprocessable.new("This milestone is temporarily locked for maintenace. Please try again.")
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
    end
  end
end
