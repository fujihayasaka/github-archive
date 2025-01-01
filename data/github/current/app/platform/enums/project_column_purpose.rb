# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ProjectColumnPurpose < Platform::Enums::Base
      description "The semantic purpose of the column - todo, in progress, or done."

      value "TODO", "The column contains cards still to be worked on", value: "todo"
      value "IN_PROGRESS", "The column contains cards which are currently being worked on", value: "in_progress"
      value "DONE", "The column contains cards which are complete", value: "done"
    end
  end
end
