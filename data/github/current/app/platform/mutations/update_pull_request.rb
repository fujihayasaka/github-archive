# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdatePullRequest < Platform::Mutations::Base
      include Scientist
      description "Update a pull request"

      minimum_accepted_scopes ["public_repo"]

      argument :pull_request_id, ID, description: "The Node ID of the pull request.", required: true, loads: Objects::PullRequest
      argument :base_ref_name, String, description: <<~DESCRIPTION, required: false
        The name of the branch you want your changes pulled into. This should be an existing branch
        on the current repository.
      DESCRIPTION
      argument :title, String, description: "The title of the pull request.", required: false
      argument :body, String, description: "The contents of the pull request.", required: false
      argument :state, Enums::PullRequestUpdateState, description: "The target state of the pull request.", required: false
      argument :maintainer_can_modify, Boolean, description: "Indicates whether maintainers can modify the pull request.", required: false
      argument :assignee_ids, [ID], "An array of Node IDs of users for this pull request.", required: false, loads: Objects::User
      argument :milestone_id, ID, "The Node ID of the milestone for this pull request.", required: false, loads: Objects::Milestone
      argument :label_ids, [ID], "An array of Node IDs of labels for this pull request.", required: false, loads: Objects::Label
      argument :project_ids, [ID], "An array of Node IDs for projects associated with this pull request.", required: false

      error_fields
      field :pull_request, Objects::PullRequest, "The updated pull request.", null: true
      field :actor, Interfaces::Actor, "Identifies the actor who performed the event.", null: true

      extras [:execution_errors]

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, pull_request:, **inputs)
        permission.async_repo_and_org_owner(pull_request).then do |repo, org|
          permission.access_allowed? :update_pull_request, repo: repo, current_org: org, resource: pull_request, allow_integrations: true, allow_user_via_granular_actor: true
        end
      end

      def resolve(execution_errors:, pull_request:, **inputs)
        context[:permission].authorize_content(:pull_request, :update, repo: pull_request.repository)

        if !context[:actor].can_have_granular_permissions? && !pull_request.async_viewer_can_update?(context[:viewer]).sync
          message = "#{context[:viewer].display_login} does not have permission to update the pull request #{pull_request.global_relay_id}."
          raise Errors::Forbidden.new(message)
        end

        changing_title = false

        issue = pull_request.issue
        issue.skip_hydro_update_event_instrumentation = true
        issue_previous_title = issue.title
        issue_previous_body = issue.body
        issue_attributes = Hash.new
        if inputs[:title]
          issue_attributes[:title] = inputs[:title]
          changing_title = true
        end

        # this can be obtained in any of these three ways.
        # Technically these things are stored on the issue but that's an
        # implementation detail and having pull request write should also
        # suffice.
        can_write_issue_stored_items = Promise.all([
          pull_request.repository.async_pushable_by?(context[:viewer]),
          pull_request.repository.resources.issues.async_writable_by?(context[:viewer]),
          pull_request.repository.resources.pull_requests.async_writable_by?(context[:viewer])
        ]).sync.include?(true)

        if can_write_issue_stored_items
          if inputs.key?(:milestone)
            issue_attributes[:milestone] = inputs[:milestone]
          end

          if inputs.key?(:labels)
            labels = inputs[:labels]
          end

          if inputs.key?(:assignees)
            issue_attributes[:assignees] = inputs[:assignees] || []
          end

          if inputs.key?(:project_ids)

            visible_cards = issue.visible_cards_for(context[:viewer])
            visible_project_ids = visible_cards.map(&:project).map(&:global_relay_id)
            project_ids_to_add = inputs[:project_ids] - visible_project_ids
            projects_to_add = project_ids_to_add.map do |id|
              Platform::Helpers::NodeIdentification.typed_object_from_id([Platform::Objects::Project], id, context)
            end

            projects_to_add.each do |project|
              if project.writable_by?(context[:viewer])
                add_card_helper = Platform::Helpers::AddProjectCard.new(project, context)
                add_card_helper.check_permissions
                add_card_helper.check_issue_project_owner(issue)
                issue.cards.build(creator: context[:viewer], project: project, content: pull_request)
              else
                raise Errors::Forbidden.new("You don't have permission to add to project with id '#{project.global_relay_id}'.")
              end
            end

            cards_to_delete = visible_cards.select do |card|
              inputs[:project_ids].none?(card.project.global_relay_id)
            end

            cards_to_delete.each do |card|
              if card.writable_by?(context[:viewer])
                delete_card_helper = Platform::Helpers::DeleteProjectCard.new(card, context)
                delete_card_helper.delete_card
              end
            end
          end
        else # ie. can_write_issue_stored_items == false
          if inputs.key?(:milestone) || inputs.key?(:assignees) || inputs.key?(:project_ids) || inputs.key?(:labels)
            message = "#{context[:viewer].display_login} does not have permission to update the pull request #{pull_request.global_relay_id}."
            raise Errors::Forbidden.new(message)
          end
        end

        if inputs[:maintainer_can_modify] && disallow_fork_collab_access?(pull: pull_request, actor: context[:viewer])
          inputs[:maintainer_can_modify] = false
        end

        ::PullRequest.transaction do
          if inputs[:state] == "open"
            issue.open(context[:viewer], issue_attributes)
          elsif inputs[:state] == "closed"
            issue.close(context[:viewer], attributes: issue_attributes)
          end

          if !issue.saved_change_to_state? && issue_attributes.present?
            issue.update(issue_attributes)
          end

          if issue.errors.empty? && inputs[:body]
            issue.update_body(inputs[:body], context[:viewer])
          end

          if issue.errors.empty? || issue.valid?
            issue.replace_labels(labels) unless labels.nil?
          end

          raise ActiveRecord::Rollback if issue.errors.any? # rubocop:disable GitHub/UsePlatformErrors

          unless inputs[:maintainer_can_modify].nil?
            if context[:viewer] != pull_request.user
              pull_request.errors.add(:fork_collab_state, message: "Only the pull request author may change the maintainer_can_modify value")
            else
              fork_collab_state = inputs[:maintainer_can_modify] ? :allowed : :denied
              pull_request.update fork_collab_state: fork_collab_state
            end
          end

          if pull_request.errors.empty? && inputs[:base_ref_name]
            pull_request.change_base_branch(context[:viewer], inputs[:base_ref_name])
          end
        end

        if issue.errors.any?
          model_error_response(issue, execution_errors)
        elsif pull_request.errors.any?
          model_error_response(pull_request, execution_errors)
        else
          issue.instrument_hydro_update_event(
            previous_title: issue_previous_title,
            previous_body: issue_previous_body,
            actor: context[:viewer],
          )

          issue.save
          pull_request.enqueue_mergeable_update

          {
            pull_request: pull_request,
            actor: context[:viewer],
            errors: [],
          }
        end
      rescue ActiveRecord::RecordInvalid => e
        model_error_response(e.record, execution_errors)
      rescue PullRequest::BaseNotChangeableError => e
        base_ref_error_response(
          base_ref_name: inputs[:base_ref_name],
          message: e.ui_message,
          execution_errors: execution_errors,
        )
      end

      private

      def disallow_fork_collab_access?(pull:, actor:)
        PullRequest::ForkCollabAccessViaIntegrationAuthorizer.new(actor: context[:viewer],
          head_repository: pull.head_repository,
          base_repository: pull.base_repository).disallow?
      end

      def base_ref_error_response(base_ref_name:, message:, execution_errors:)
        Platform::UserErrors.append_legacy_mutation_error_messages_to_context([message], execution_errors)

        client_error = {
          path: %w(input baseRefName),
          message: message,
          short_message: "Invalid baseRefName",
          attribute: "base_ref_name",
        }

        {
          pull_request: nil,
          errors: [client_error],
        }
      end

      def model_error_response(pull_request, execution_errors)
        Platform::UserErrors.append_legacy_mutation_model_errors_to_context(pull_request, execution_errors)
        errors = Platform::UserErrors.mutation_errors_for_model(pull_request,
          translate: { fork_collab: :maintainer_can_modify, fork_collab_state: :maintainer_can_modify }
        )

        { pull_request: nil, errors: errors }
      end
    end
  end
end
