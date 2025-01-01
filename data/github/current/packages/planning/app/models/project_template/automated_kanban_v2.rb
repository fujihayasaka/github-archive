# typed: true
# frozen_string_literal: true

# Builds the necessary data structure for creating ProjectColumns and sample
# ProjectCards on an automated kanban-style Project board that does not incorporate
# review states
#
# See ProjectTemplate for usage instructions :sparkles:
#
class ProjectTemplate::AutomatedKanbanV2 < ProjectTemplate

  def build
    @columns = ProjectColumnTemplate.kanban
  end

  def self.title
    "Automated kanban"
  end

  # -----------------------------------------------
  # Meta information about this template for the UI
  #
  def self.description
    "Kanban-style board with built-in triggers to automatically move issues and pull requests across To do, In progress and Done columns."
  end
end
