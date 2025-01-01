# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateIssue < Platform::Mutations::Base
      include Platform::Helpers::ReadFromSelectedReplicas

      description "Updates an Issue."

      minimum_accepted_scopes ["public_repo"]

      argument :id, ID, "The ID of the Issue to modify.", required: true, loads: Objects::Issue, as: :issue
      argument :title, String, "The title for the issue.", required: false
      argument :body, String, "The body for the issue description.", required: false
      argument :body_version, String, "The hash of the issue body.  If supplied, the issue body will only be updated if the body_version matches the current body_version of the issue.", visibility: :internal, required: false
      argument :assignee_ids, [ID], "An array of Node IDs of users for this issue.", required: false, loads: Objects::User
      argument :milestone_id, ID, "The Node ID of the milestone for this issue.", required: false, loads: Objects::Milestone
      argument :label_ids, [ID], "An array of Node IDs of labels for this issue.", required: false, loads: Objects::Label
      argument :state, Enums::IssueState, "The desired issue state.", required: false
      argument :project_ids, [ID], "An array of Node IDs for projects associated with this issue.", required: false
      argument :tasklist_blocks_operation, String, "The description of the tasklist block operation.", required: false, visibility: :internal
      argument :issue_type_id, ID, "The ID of the Issue Type for this issue.", required: false

      read_arguments_from_replicas!

      error_fields
      field :issue, Objects::Issue, "The issue.", null: true
      field :actor, Interfaces::Actor, "Identifies the actor who performed the event.", null: true

      extras [:execution_errors]

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        issue = inputs[:issue]
        permission.async_repo_and_org_owner(issue).then do |repo, org|
          permission.access_allowed?(:triage_issue, resource: issue, repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def resolve(execution_errors:, **inputs)
        read_from_selected_replicas([ApplicationRecord::Repositories]) do
          issue_type = Helpers::IssueTypes.load_by_id(inputs[:issue_type_id], context) if inputs[:issue_type_id].present?

          issue = inputs[:issue]
          issue.skip_hydro_update_event_instrumentation = true
          repository = issue.repository

          context[:permission].authorize_content(:issue, :update, issue: issue, repo: repository)

          unless repository.has_issues?
            raise Errors::Forbidden, "Repository has issues disabled."
          end

          check_database_resource_update_rate_limit!(resource: issue, current_user: context[:viewer])

          if context[:permission].integration_user_request?
            issue.performed_via_integration = context[:integration]
            issue.modifying_integration = context[:integration]
          end

          previous_title = issue.title
          previous_body = issue.body

          issue.skip_update_issue_orchestration = true

          # This is a more general check that will include permissions check for apps & users alltogether
          # can_set_milestone and triageable_by are not implemented for apps
          can_viewer_write = repository.pushable_by?(context[:viewer]) || repository.resources.issues.writable_by?(context[:viewer])

          # If the issue is locked, only those with write access or higher can edit the issue
          if issue.locked? && !can_viewer_write
            message = "#{context[:viewer].display_login} does not have permission to update the locked issue #{issue.global_relay_id}."
            raise Errors::Forbidden.new(message)
          end

          # All props mentioned in the arguments which are not metadata props
          if inputs.key?(:title) || inputs.key?(:body) || inputs.key?(:state)
            # issue's fields can be edited by people with write OR people with triage, if they are the authors
            if !(can_viewer_write || context[:viewer] == issue.user)
              message = "#{context[:viewer].display_login} does not have permission to update the issue #{issue.global_relay_id}."
              raise Errors::Forbidden.new(message)
            end
          end

          attributes = {}
          attributes[:title] = inputs[:title] if inputs.key?(:title)

          # The viewer must have triage access to assign assignees and labels.
          if inputs.key?(:milestone)
            if can_viewer_write || (!context[:actor].can_have_granular_permissions? && issue.can_set_milestone?(context[:viewer]))
              attributes[:milestone] = inputs[:milestone]
            else
              raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to update the milestone on the issue #{issue.global_relay_id}.")
            end
          end

          # The viewer must have triage access to assign assignees and labels.
          if inputs.key?(:assignees) || inputs.key?(:labels) && !inputs[:labels].nil?
            if can_viewer_write || issue.triageable_by?(context[:viewer])
              if inputs.key?(:labels) && !inputs[:labels].nil?
                labels = inputs[:labels]
                label_in_other_repository = labels.find { |label| label.repository_id != issue.repository_id }
                if label_in_other_repository
                  GitHub.dogstats.increment "graphql.mutation.update_issue.cross_repository"
                  raise Errors::NotFound.new("The label ('#{label_in_other_repository.global_relay_id}') and issue ('#{issue.global_relay_id}') don't belong to the same repository")
                end
              end

              if inputs.key?(:assignees)
                attributes[:assignees] = inputs[:assignees] || []
              end
            else
              raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to update metadata on the issue #{issue.global_relay_id}.")
            end
          end

          has_project_cards = T.let(false, T::Boolean)
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
                issue.cards.build(creator: context[:viewer], project: project, content: issue)
                has_project_cards = true
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

          if inputs[:tasklist_blocks_operation] && inputs[:body]
            operation = TasklistBlocks::Operation.from(inputs[:tasklist_blocks_operation], current_repository: repository, current_user: context[:viewer])
            return unless operation

            if !ActiveRecord::Base.single_database_cluster? && operation.instance_of?(TasklistBlocks::Operations::ConvertToIssue)
              inputs[:body] = ActiveRecord::Base.connected_to(role: :writing) do
                operation.call(inputs[:body])
              end
            else
              inputs[:body] = operation.call(inputs[:body])
            end

            # TODO issues-graph: not implemented right now
            # instrument_tasklist_block_operation(operation: operation, actor: context[:viewer], repository: repository, issue: issue)
          end

          if inputs.key?(:issue_type_id)
            attributes[:issue_type] = issue_type
          end

          # retry 2 times due to various unique constraints in database in combination with our transaction isolation level.
          retries = 2
          begin
            saved = if inputs[:state] == "closed" && issue.open?
              issue.close(context[:viewer], attributes: attributes) # domain-isolation-query-violation:ignore:packages/issues (SELECT, UPDATE)
            elsif inputs[:state] == "open" && issue.closed?
              issue.open(context[:viewer], attributes) # domain-isolation-query-violation:ignore:packages/issues (SELECT, UPDATE)
            else
              if has_project_cards
                issue.cards.transaction do
                  issue.update(attributes) # domain-isolation-query-violation:ignore:packages/issues (SELECT, UPDATE)
                end
              else
                replica_clusters = attributes.empty? ? [ApplicationRecord::Collab] : []
                ActiveRecord::Base.connected_to_many(replica_clusters, role: :reading) do
                  issue.update(attributes) # domain-isolation-query-violation:ignore:packages/issues (SELECT, UPDATE)
                end
              end
            end
          rescue ActiveRecord::RecordNotUnique
            (retries -= 1) && retry if retries > 0

            # we can't handle this - throw
            raise Errors::ServiceUnavailable
          end

          if inputs.key?(:body)
            if inputs[:body_version] && inputs[:body_version] != issue.body_version
              raise Errors::StaleData.new(
                "The issue body for #{issue.global_relay_id} has been modified since you last fetched it."
              )
            end
            replica_clusters = [ApplicationRecord::Collab]
            ActiveRecord::Base.connected_to_many(replica_clusters, role: :reading) do
              issue.update_body(inputs[:body], context[:viewer])
            end
          end

          if saved || issue.valid?
            issue.replace_labels(labels) unless labels.nil? # domain-isolation-query-violation:ignore:packages/issues (SELECT, UPDATE)

            update_issue_orchestration = IssueOrchestration.update_issue!(actor: context[:viewer], issue: issue)
            if issue.title != previous_title
              update_issue_orchestration.data.deep_merge!({
                title_or_body_changes: {
                  old_title: previous_title,
                  current_title: issue.title,
                }
              })
            end

            update_issue_orchestration.execute!

            issue.instrument_hydro_update_event(
              previous_title: previous_title,
              previous_body: previous_body,
              actor: context[:viewer],
            )

            {
              issue: issue,
              actor: context[:viewer],
              errors: [],
            }
          else
            Platform::UserErrors.append_legacy_mutation_model_errors_to_context(issue, execution_errors)

            {
              issue: nil,
              errors: Platform::UserErrors.mutation_errors_for_model(issue, translate: { repository_id: "issueTypeId" }),
            }
          end
        end
      end
    end
  end
end
