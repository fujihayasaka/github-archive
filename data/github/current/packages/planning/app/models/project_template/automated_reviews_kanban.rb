# typed: true
# frozen_string_literal: true

# Builds the necessary data structure for creating ProjectColumns and sample
# ProjectCards on an automated kanban-style Project board with review automation
#
# See ProjectTemplate for usage instructions :sparkles:
#
class ProjectTemplate::AutomatedReviewsKanban < ProjectTemplate

  def build
    @columns = ProjectColumnTemplate.kanban_with_reviews
  end

  def self.title
    "Automated kanban with reviews"
  end

  # -----------------------------------------------
  # Meta information about this template for the UI
  #
  def self.description
    "Everything included in the Automated kanban template with additional triggers for pull request reviews."
  end
end
