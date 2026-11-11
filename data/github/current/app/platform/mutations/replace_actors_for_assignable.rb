# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ReplaceActorsForAssignable < Platform::Mutations::Base
      include Helpers::Agentic

      description "Replaces all actors for assignable object."

      minimum_accepted_scopes ["public_repo"]

      argument :assignable_id, ID, "The id of the assignable object to replace the assignees for.", required: true, loads: Interfaces::Assignable
      argument :actor_ids, [ID], "The ids of the actors to replace the existing assignees.", required: true, loads: Interfaces::Actor
      argument :agent_assignment, Inputs::AgentAssignmentInput, "Configuration for assigning an AI agent to this issue.", required: false, feature_flag: :issues_copilot_assignment_api_support

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

      def resolve(execution_errors:, assignable:, actors:, agent_assignment: nil, **inputs)
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

          check_database_resource_update_rate_limit!(resource: object, current_user: context[:viewer])

          # Validate actors regardless of whether Copilot support is enabled
          actors.each do |actor|
            if actor.is_a?(Organization) || actor.is_a?(Mannequin)
              raise Errors::Forbidden.new("Only users and bots can be assigned.")
            end
          end

          bots = actors.select { |assignee| assignee.is_a?(Bot) }
          if bots.any?
            GitHub::PrefillAssociations.prefill_associations(bots, :integration)
            if repository.feature_flag_enabled?(:agents_platform_id, default: false)
              validate_agent_bot_assignments!(bots, repository, actor: context[:viewer])
            else
              validate_bot_assignments!(bots, repository, actor: context[:viewer])
            end
          end

          # After validations pass, trigger Copilot job for Issues
          if !is_pr
            use_orchestration = FeatureFlag.vexi.enabled?(:issues_use_orchestration_for_copilot, context[:viewer], default: false)
            if use_orchestration
              agents_platform_enabled = repository.feature_flag_enabled?(:agents_platform_id, default: false)

              bot_ids_requiring_context = if agents_platform_enabled
                current_agent_bot_ids = agentic_bot_ids_from(actors)
                previous_agent_bot_ids = agentic_bot_ids_from(object.assignees)
                current_agent_bot_ids - previous_agent_bot_ids
              else
                current_copilot_bot_ids = copilot_bot_ids_from(actors)
                copilot_previously_assigned = copilot_bot_ids_from(object.assignees).any?
                copilot_previously_assigned ? [] : current_copilot_bot_ids
              end

              copilot_context = if bot_ids_requiring_context.any?
                # Validate target repository access before constructing copilot_context
                assignment_input = if FeatureFlag.vexi.enabled?(:issues_copilot_assignment_api_support, context[:viewer], default: false)
                  agent_assignment
                end

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
              # Existing behaviour
              request_token_value = context[:request_token]&.to_s
              token = begin
                if request_token_value.present?
                  GitHub.encrypt_and_encode_capi_token(request_token_value)
                else
                  CopilotSessions::CopilotApiToken.get_encrypted(
                    user: context[:viewer],
                    entry_point: :replace_actors_for_assignable_mutation,
                    user_session: context[:user_session]
                  )
                end
              rescue CopilotSessions::CopilotApiToken::IntegrationUnavailableError
                # Copilot SWE Agent integration is not available (e.g., on GHES)
                # Fall through with nil token — assignees will be set without Copilot support
                nil
              end

              # If token is nil (integration unavailable), skip Copilot and just assign directly
              if token.nil?
                update_attributes = Issues::UpdateIssueAttributes.new(
                  assignees: Issues::UpdateIssueAttribute::Set.new(actors),
                )

                Issues.domain.update(object, update_attributes, context[:viewer])

                next {
                  assignable: assignable,
                  errors: [],
                }
              end

              begin
                Issues.domain.copilot.update_assignees_with_copilot_support(
                  actor: context[:viewer],
                  issue: object,
                  assignees: actors,
                  token: token,
                  remote_ip: context[:ip]
                )
                # Ensure the issue is saved after the Copilot domain update
                if object.save
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

              rescue CopilotAPI::UnauthorizedError,
                     CopilotAPI::RAIError,
                     CopilotAPI::EntityTooLargeError,
                     CopilotAPI::RateLimitError,
                     CopilotAPI::NetworkError,
                     CopilotAPI::RequestError,
                     CopilotAPI::Error => err
                # Partial success: non-Copilot assignees were assigned
                handle_copilot_assignment_error(err, execution_errors)
                {
                  assignable: assignable,
                  errors: [],
                }
              end
            end
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

      def raise_unprocessable(errors)
        raise Errors::Unprocessable.new("Could not add assignees: #{errors}")
      end

      private

      def handle_copilot_assignment_error(exception, execution_errors)
        case exception
        when CopilotAPI::UnauthorizedError
          error_message = "Insufficient permissions to assign Copilot. Your token requires read and write access to actions, contents, issues, and pull requests, and permission to assign issues to the target repository. " \
            "Learn more: https://docs.github.com/en/copilot/how-tos/use-copilot-agents/coding-agent/create-a-pr"
          execution_errors.add(Errors::Forbidden.new(error_message))
        when CopilotAPI::RAIError
          execution_errors.add(Errors::Unprocessable.new("The request was filtered due to content policy. Please review the issue description and try again."))
        when CopilotAPI::EntityTooLargeError
          execution_errors.add(Errors::Unprocessable.new("The request was too large. Please try reducing the size of the issue description and try again."))
        when CopilotAPI::RateLimitError
          execution_errors.add(Errors::RateLimited.new("Rate limit exceeded. Please try again in a few minutes."))
        when CopilotAPI::NetworkError
          Failbot.report(exception, context: {
            app: "github",
            feature: "issues_copilot_assign",
            context: "ReplaceActorsForAssignableMutation",
          })
          execution_errors.add(Errors::ServiceUnavailable.new("Copilot coding agent is unavailable at the moment. Please try again later."))
        when CopilotAPI::RequestError
          Failbot.report(exception, context: {
            app: "github",
            feature: "issues_copilot_assign",
            context: "ReplaceActorsForAssignableMutation",
          })
          parsed_message = CopilotSweAgentJobHelper.parse_jobs_api_error(exception.message)
          execution_errors.add(Errors::Unprocessable.new(parsed_message.capitalize))
        else
          Failbot.report(exception, context: {
            app: "github",
            feature: "issues_copilot_assign",
            context: "ReplaceActorsForAssignableMutation",
          })
          execution_errors.add(Errors::InternalExecution.new("An error occurred while assigning Copilot. Please try again later, or contact support if the problem persists."))
        end
      end

      def get_copilot_context(agent_assignment, repository)
        copilot_attributes = get_copilot_attributes(agent_assignment, repository, context[:ip], viewer: context[:viewer])

        request_token_value = context[:request_token]&.to_s

        token = if request_token_value.present?
          GitHub.encrypt_and_encode_capi_token(request_token_value)
        else
          CopilotSessions::CopilotApiToken.get_encrypted(
            user: context[:viewer],
            entry_point: :replace_actors_for_assignable_mutation,
            user_session: context[:user_session]
          )
        end

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
