# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    class AddProjectCard
      attr_reader :project, :context

      def initialize(project, context)
        @project = project
        @context = context
      end

      def check_permissions
        context[:permission].typed_can_modify?("UpdateProject", project: project).sync
        context[:permission].authorize_content(:project, :update, project: project)

        if !project.writable_by?(context[:viewer])
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to add project cards to this project.")
        end
      end

      def invalid_repository_owner?(content)
        project.owner_type == "Repository" && project.owner != content.repository
      end

      def invalid_user_or_organization_owner?(content)
        project.owner_type != "Repository" && project.owner != content.repository.owner
      end

      def check_issue_project_owner(issue)
        if invalid_repository_owner?(issue)
          raise Errors::Validation.new("Project '#{project.global_relay_id}' is not in the same repository as the issue")
        end

        if invalid_user_or_organization_owner?(issue)
          raise Errors::Validation.new("Project '#{project.global_relay_id}' is not owned by the same owner as the issue's repository")
        end
      end

      def content_from_inputs(inputs)
        content = inputs[:content]
        content = content.issue if content.is_a?(::PullRequest)

        unless content.is_a?(::Issue) && content.repository
          raise Errors::Validation.new("contentId must refer to a member of the ProjectCardItem union")
        end

        if invalid_repository_owner?(content)
          raise Errors::Validation.new("contentID must refer to an issue or pull request in the same repository as the project")
        end

        if invalid_user_or_organization_owner?(content)
          raise Errors::Validation.new("contentID must refer to an issue or pull request in a repository owned by the project owner")
        end

        content
      end

      def card_edge(card, cards_items)
        cards_items = ArrayWrapper.new(cards_items)
        cards_connection = Platform::ConnectionWrappers::ArrayWrapper.new(cards_items, context: @context)
        GraphQL::Pagination::Connection::Edge.new(card, cards_connection)
      end
    end
  end
end
