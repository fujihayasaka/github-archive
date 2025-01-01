# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ProjectTemplate < Platform::Enums::Base
      description "GitHub-provided templates for Projects"

      value "BASIC_KANBAN", "Create a board with columns for To do, In progress and Done.", value: "basic_kanban"
      value "AUTOMATED_KANBAN_V2", "Create a board with v2 triggers to automatically move cards across To do, In progress and Done columns.", value: "automated_kanban_v2"
      value "AUTOMATED_REVIEWS_KANBAN", "Create a board with triggers to automatically move cards across columns with review automation.", value: "automated_reviews_kanban"
      value "BUG_TRIAGE", "Create a board to triage and prioritize bugs with To do, priority, and Done columns.", value: "bug_triage"
    end
  end
end
