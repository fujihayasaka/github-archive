# typed: true
# frozen_string_literal: true

# Builds the necessary data structure for creating ProjectColumns and sample
# ProjectCards on a simple kanban-style Project board
#
# See ProjectTemplate for usage instructions :sparkles:
#
class ProjectTemplate::BasicKanban < ProjectTemplate

  def build
    @columns = build_columns
  end

  def build_columns
    columns = ProjectColumnTemplate.kanban
    columns.map { |column| column.workflows.clear }
    columns
  end

  def self.title
    "Basic kanban"
  end

  # -----------------------------------------------
  # Meta information about this template for the UI
  #
  def self.description
    "Basic kanban-style board with columns for To do, In progress and Done."
  end
end
