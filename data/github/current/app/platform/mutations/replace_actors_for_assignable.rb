# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ReplaceActorsForAssignable < Platform::Mutations::Base
      description "Replaces all actors for assignable object."

      minimum_accepted_scopes ["public_repo"]

      argument :assignable_id, ID, "The id of the assignable object to replace the assignees for.", required: true, loads: Interfaces::Assignable
      argument :actor_ids, [ID], "The ids of the actors to replace the existing assignees.", required: true, loads: Interfaces::Actor

      error_fields
      field :assignable, Interfaces::Assignable, "The item that was assigned.", null: true

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

      def resolve(assignable:, actors:, **inputs)
        is_pr = assignable.is_a?(PullRequest)
        object = is_pr ? assignable.issue : assignable

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

            installations = IntegrationInstallation.with_repository(repository).includes(integration: :bot).select { |installation| installation.bot.present? }.index_by { |installation| installation.bot.id }
            bots.each do |bot|
              installation = installations[bot.id]

              unless Apps::Privileged.capable?(:installed_globally, app: bot.integration)
                if installation.nil? || installation.repository_ids(repository_ids: [repository.id]).none?
                  raise Errors::Forbidden.new("Bot does not have access to the repository.")
                end
              end

              unless Apps::Privileged.capable?(:is_assignable, app: bot.integration)
                # The bot cannot be assigned to issues
                raise Errors::Forbidden.new("Bot cannot be assigned to issues or pull requests.")
              end

              unless repository.copilot_swe_agent_enabled?(context[:viewer])
                raise Errors::Forbidden.new("Copilot Swe Agent app is not enabled in this repository.")
              end
            end
          end

          # After validations pass, use Copilot support if enabled for Issues
          if !is_pr && context[:viewer].feature_flag_enabled?(:issues_copilot_cross_repo_assign, default: false)
            token = Copilot::DecryptedToken.from(@context[:request_token].to_s)
            update_result = Issues.domain.copilot.update_assignees_with_copilot_support(
              actor: context[:viewer],
              issue: object,
              assignees: actors,
              token:
            )
            case update_result
            when GH::Result::Ok
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
            when GH::Result::Error::ServiceUnreachable
              {
                assignable: nil,
                errors: [
                  {
                    path: nil,
                    message: "Failed to trigger Copilot job: Service Unreachable",
                    short_message: "Failed to trigger Copilot job: Service Unreachable",
                    attribute: "base",
                  }
                ],
              }
            when GH::Result::Error
              {
                assignable: nil,
                errors: [
                  {
                    path: nil,
                    message: "An error occurred while updating assignees",
                    short_message: "An error occurred while updating assignees",
                    attribute: "base",
                  }
                ],
              }
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
    end
  end
end
