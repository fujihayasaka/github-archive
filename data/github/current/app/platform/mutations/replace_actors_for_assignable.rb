# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ReplaceActorsForAssignable < Platform::Mutations::Base
      docs_category :issues
      include Helpers::Agentic

      description "Replaces all actors for assignable object."

      minimum_accepted_scopes ["public_repo"]

      argument :assignable_id, ID, "The id of the assignable object to replace the assignees for.", required: true, loads: Interfaces::Assignable
      argument :actor_ids, [ID], "The ids of the actors to replace the existing assignees. May be used as an alternative to or in conjunction with actorLogins.", required: false, loads: Interfaces::Actor, as: :actors_from_ids
      argument :actor_logins, [String], "The usernames of the actors to replace the existing assignees. May be used as an alternative to or in conjunction with actorIds. For bots, use the login format with [bot] suffix (e.g., 'my-app[bot]').", required: false
      argument :agent_assignment, Inputs::AgentAssignmentInput, "Configuration for assigning an AI agent to this issue.", required: false

      error_fields
      field :assignable, Interfaces::Assignable, "The item that was assigned.", null: true

      extras [:execution_errors]

      def self.async_api_can_modify?(permission, assignable:, **inputs)
        object = assignable.is_a?(PullRequest) ? assignable.issue : assignable
        permission.async_repo_and_org_owner(object).then do |repo, org|
          permission.access_allowed?(
            :replace_assignees,
            resource: object,
            repo: repo,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          )
        end
      end

      def resolve(execution_errors:, assignable:, actors_from_ids: nil, actor_logins: nil, agent_assignment: nil, **inputs)
        # At least one of actor_ids or actor_logins must be provided (can be empty arrays to clear assignees)
        if actors_from_ids.nil? && actor_logins.nil?
          raise Errors::Unprocessable.new("At least one of actorIds or actorLogins must be provided.")
        end

        # Load actors from logins manually
        actors_from_logins_promise = if actor_logins.present?
          Promise.all(actor_logins.map { |login| Interfaces::Actor.load_by_login(login, context) }).then do |loaded_actors|
            # Validate all logins resolved successfully
            actor_logins.each_with_index do |login, index|
              if loaded_actors[index].nil?
                raise Errors::NotFound.new("Could not resolve to a user or bot with the login '#{login}'.")
              end
            end
            loaded_actors
          end
        else
          Promise.resolve([])
        end

        actors_from_logins_promise.then do |actors_from_logins|
          # Merge actors from both sources and de-duplicate
          actors = ((actors_from_ids || []) + actors_from_logins).uniq

          is_pr = assignable.is_a?(PullRequest)
          # PullRequest#issue association is typed as T.nilable(Issue), but in practice
          # every PullRequest has an Issue (they're created together). Using T.must here
          # since the loads: argument ensures assignable exists.
          object = is_pr ? T.must(assignable.issue) : assignable

          unless object.assignable_by?(actor: context[:viewer])
            raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to manage assignees in this repository.")
          end

          object.async_repository.then do |repository|
            if assignable.is_a?(Issue) && !repository.has_issues?
              raise Errors::Unprocessable::IssuesDisabled.new
            end

            if repository.locked_on_migration?
              raise Errors::Unprocessable::RepositoryMigration.new
            end

            if repository.archived?
              raise Errors::Unprocessable::RepositoryArchived.new
            end

            # Validate actors regardless of whether Copilot support is enabled
            actors.each do |actor|
              if actor.is_a?(Organization) || actor.is_a?(Mannequin) || actor.is_a?(Admin::IBusinessUserAccount)
                raise Errors::Forbidden.new("Only users and bots can be assigned.")
              end
            end

            check_database_resource_update_rate_limit!(resource: object, current_user: context[:viewer])

            bots = actors.select { |assignee| assignee.is_a?(Bot) }
            if bots.any?
              GitHub::PrefillAssociations.prefill_associations(bots, :integration)
              validate_agent_bot_assignments!(bots, repository, actor: context[:viewer])
            end

            # After validations pass, trigger Copilot job for Issues
            if !is_pr
              current_agent_bot_ids = agentic_bot_ids_from(actors)
              previous_agent_bot_ids = agentic_bot_ids_from(object.assignees)
              bot_ids_requiring_context = current_agent_bot_ids - previous_agent_bot_ids

              copilot_context = if bot_ids_requiring_context.any?
                # Validate target repository access before constructing copilot_context
                assignment_input = agent_assignment

                target_repo = assignment_input&.target_repository || repository
                if target_repo.present? && (!target_repo.writable_by?(context[:viewer]) || !target_repo.writable?)
                  execution_errors.add(Errors::Forbidden.new("Could not assign agent: target repository is not writable."))
                  # Still assign non-agent assignees by removing the offending bots
                  actors.reject! { |a| a.is_a?(Bot) && bot_ids_requiring_context.include?(a.id) }
                  nil
                else
                  get_copilot_context(assignment_input, repository)
                end
              else
                nil
              end

              update_attributes = Issues::UpdateIssueAttributes.new(
                assignees: Issues::UpdateIssueAttribute::Set.new(actors),
              )

              Issues.domain.update(object, update_attributes, context[:viewer], copilot_context: copilot_context)

              {
                assignable: assignable,
                errors: [],
              }
            else
              # Used to respect blocks
              GitHub.context.push(actor_id: @context[:viewer].id) do
                object.modifying_user = @context[:viewer]

                begin
                  object.assignees = actors # domain-isolation-query-violation:ignore:packages/issues (SELECT)
                rescue ActiveRecord::RecordInvalid => e
                  if e.message =~ /has already been taken/
                    error_message = e.message
                  else
                    error_message = "Something went wrong"
                  end
                  raise_unprocessable(error_message)
                end
              end

              if object.save # domain-isolation-query-violation:ignore:packages/issues (UPDATE)
                {
                  assignable: assignable,
                  errors: [],
                }
              else
                {
                  assignable: nil,
                  errors: Platform::UserErrors.mutation_errors_for_model(object),
                }
              end
            end
          end
        end
      end

      def raise_unprocessable(errors)
        raise Errors::Unprocessable.new("Could not add assignees: #{errors}")
      end

      private

      def get_copilot_context(agent_assignment, repository)
        copilot_attributes = get_copilot_attributes(agent_assignment, repository, context[:ip], viewer: context[:viewer])

        token = resolve_copilot_token(
          viewer: context[:viewer],
          entry_point: :replace_actors_for_assignable_mutation,
          user_session: context[:user_session],
          request_token_value: context[:request_token]&.to_s,
          repository: repository,
        )

        {
          request_token: token.to_s,
          attributes: copilot_attributes
        }
      rescue CopilotSessions::CopilotApiToken::IntegrationUnavailableError
        # Copilot SWE Agent integration is not available (e.g., on GHES)
        # Return nil to skip agent assignment
        nil
      end
    end
  end
end
