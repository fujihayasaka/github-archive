# typed: true
# frozen_string_literal: true

class SlashCommands::StepBuilder::AddToProject < SlashCommands::StepBuilder::PlatformBase
  def query
    <<~'GRAPHQL'
      mutation AddProjectCard($contentId: ID!, $projectColumnId: ID!) {
        addProjectCard(input: { contentId: $contentId, projectColumnId: $projectColumnId }) {
          projectColumn {
            name
          }
        }
      }
    GRAPHQL
  end

  def variables_for(command)
    # What if there are two open projects with the same name?
    project = command
      .current_repository
      .projects
      .open_projects
      .find_by!(name: step_config["project"])

    column =
      if step_config["column"].present?
        project.columns.find_by!(name: step_config["column"])
      else
        project.columns.first
      end

    {
      "contentId" => command.context.subject.global_relay_id,
      "projectColumnId" => column.global_relay_id
    }
  end
end
