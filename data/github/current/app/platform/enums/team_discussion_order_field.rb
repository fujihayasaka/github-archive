# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class TeamDiscussionOrderField < Platform::Enums::Base
      description "Properties by which team discussion connections can be ordered."

      value "CREATED_AT", "Allows chronological ordering of team discussions.", value: "created_at"
    end
  end
end
