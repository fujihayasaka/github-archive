# typed: true
# frozen_string_literal: true

class SlashCommands::StepBuilder::CreateIssue < SlashCommands::StepBuilder::PlatformBase
  def query
    <<~'GRAPHQL'
      mutation CreateIssue($body: String!, $title: String!, $repositoryId: ID!) {
        createIssue(input: { body: $body, title: $title, repositoryId: $repositoryId }) {
          issue {
            title
            number
          }
        }
      }
    GRAPHQL
  end

  def variables_for(command)
    title = render(step_config["title"] || "New issue", data: command.template_data)
    body = render(step_config["body"] || "", data: command.template_data)

    {
      "repositoryId" => command.current_repository.global_relay_id,
      "title" => title,
      "body" => body,
    }
  end

  def transform_result(result)
    result.dig("data", "createIssue", "issue")
  end
end
