# typed: true
# frozen_string_literal: true

class SlashCommands::StepBuilder::AddAssignees < SlashCommands::StepBuilder::PlatformBase
  def query
    <<~'GRAPHQL'
      mutation AddAssignees($assigneeIds: [ID!]!, $assignableId: ID!) {
        addAssigneesToAssignable(input: { assigneeIds: $assigneeIds, assignableId: $assignableId }) {
          assignable {
            ... on Issue {
              number
            }
          }
        }
      }
    GRAPHQL
  end

  def variables_for(command)
    # TODO: Add lookup for teams
    # TODO: Can this be scoped down further?
    assignees = User.where(login: step_config["assignees"])

    {
      "assigneeIds" => assignees.map(&:global_relay_id),
      "assignableId" => command.context.subject.global_relay_id
    }
  end
end
