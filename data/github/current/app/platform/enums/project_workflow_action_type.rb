# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ProjectWorkflowActionType < Platform::Enums::Base
      docs_category :projects_classic
      description "The type of action to perform for a project workflow."
      visibility :internal

      # There will eventually be more
      value "TRANSITION_TO_COLUMN", "Move card to another column", value: ProjectWorkflowAction::TRANSITION_TO_COLUMN
    end
  end
end
