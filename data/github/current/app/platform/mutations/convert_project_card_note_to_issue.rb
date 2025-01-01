# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ConvertProjectCardNoteToIssue < Platform::Mutations::Base
      description "Convert a project note card to one associated with a newly created issue."

      # A user must have access to the repository to be able to create an issue.
      minimum_accepted_scopes ["public_repo"]

      argument :project_card_id, ID, "The ProjectCard ID to convert.", required: true, loads: Objects::ProjectCard
      argument :repository_id, ID, "The ID of the repository to create the issue in.", required: true, loads: Objects::Repository
      argument :title, String, "The title of the newly created issue. Defaults to the card's note text.", required: false
      argument :body, String, "The body of the newly created issue.", required: false

      error_fields
      field :project_card, Objects::ProjectCard, "The updated ProjectCard.", null: true

      extras [:execution_errors]

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, project_card:, repository:, **inputs)
        Platform::Helpers::ProjectDeprecation.ensure_api_availability(permission.viewer)

        project_permission = project_card.async_project.then do |project|
          permission.typed_can_modify?("UpdateProject", project: project)
        end

        repository_permission = permission.typed_can_modify?("CreateIssue", repository: repository)

        Promise.all([project_permission, repository_permission]).then do |project, repository|
          project && repository
        end
      end

      def resolve(project_card:, repository:, execution_errors:, **inputs)
        card = project_card

        context[:permission].authorize_content(:project, :update, project: card.project)
        context[:permission].authorize_content(:issue, :create, repo: repository)

        unless card.project.writable_by?(context[:viewer])
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to update project cards on this project.")
        end

        unless card.is_note?
          raise Errors::Validation.new("Project card id must refer to a note project card")
        end

        unless repository.has_issues?
          raise Errors::Unprocessable::IssuesDisabled.new
        end

        if card.project.owner_type == "Repository"
          if card.project.owner != repository
            raise Errors::Validation.new("Repository id must refer to the repository the project is in")
          end
        else
          if card.project.owner != repository.owner
            raise Errors::Validation.new("Repository id must refer to a repository owned by the project owner")
          end
        end

        title = inputs.key?(:title) ? inputs[:title] : card.note
        body = inputs.key?(:body) ? inputs[:body] : ""

        card.transaction do
          issue = repository.issues.build(title: title, body: body, user: context[:viewer])
          if context[:permission].integration_user_request?
            issue.modifying_integration = context[:integration]
          end
          if issue.save
            card.content = issue
            card.note = nil
            if card.save
              issue.events.create(
                event: "converted_note_to_issue",
                subject: card.project,
                column_name: card.column.name,
                actor: context[:viewer],
                card_id: card.id,
              )
              { project_card: card, errors: [] }
            else
              Platform::UserErrors.append_legacy_mutation_model_errors_to_context(card, execution_errors)
              { project_card: nil, errors: Platform::UserErrors.mutation_errors_for_model(card) }
            end
          else
            Platform::UserErrors.append_legacy_mutation_model_errors_to_context(issue, execution_errors)
            { project_card: nil, errors: Platform::UserErrors.mutation_errors_for_model(issue) }
          end
        end
      end
    end
  end
end
