# typed: true
# frozen_string_literal: true

# Builds the necessary data structure for creating ProjectColumns and
# ProjectWorkflows on a bug triaging board
#
# See ProjectTemplate for usage instructions :sparkles:
#
class ProjectTemplate::BugTriage < ProjectTemplate

  def build
    @columns = ProjectColumnTemplate.bug_triage
  end

  def self.title
    "Bug triage"
  end

  # -----------------------------------------------
  # Meta information about this template for the UI
  #
  def self.description
    "Triage and prioritize bugs with columns for To do, High priority, Low priority, and Closed."
  end
end
