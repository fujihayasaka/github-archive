# typed: true
# frozen_string_literal: true

class SlashCommands::StepBuilder::AddComment < SlashCommands::StepBuilder::PlatformBase
  def query
    <<~'GRAPHQL'
      mutation CreateComment($body: String!, $subjectId: ID!) {
        addComment(input: { body: $body, subjectId: $subjectId }) {
          commentEdge {
            node {
              id
              bodyText
            }
          }
        }
      }
    GRAPHQL
  end

  def variables_for(command)
    {
      "body" => render(step_config["body"], data: command.template_data),
      "subjectId" => command.context.subject.global_relay_id
    }
  end

  def transform_result(result)
    result.dig("data", "addComment", "commentEdge", "node")
  end
end
