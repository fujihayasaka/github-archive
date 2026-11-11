# typed: true
# frozen_string_literal: true

class SlashCommands::StepBuilder::AddLabels < SlashCommands::StepBuilder::PlatformBase
  def query
    <<~'GRAPHQL'
      mutation AddLabels($labelIds: [ID!]!, $labelableId: ID!) {
        addLabelsToLabelable(input: { labelIds: $labelIds, labelableId: $labelableId }) {
          labelable {
            ... on Issue {
              number
            }
          }
        }
      }
    GRAPHQL
  end

  def variables_for(command)
    labels = command.current_repository.labels.where(name: step_config["labels"])

    {
      "labelIds" => labels.map(&:global_relay_id),
      "labelableId" => command.context.subject.global_relay_id
    }
  end

  def transform_result(result)
    result.dig("data", "addLabelsToLabelable")
  end
end
