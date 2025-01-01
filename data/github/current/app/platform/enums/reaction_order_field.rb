# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ReactionOrderField < Platform::Enums::Base
      description "A list of fields that reactions can be ordered by."

      value "CREATED_AT", "Allows ordering a list of reactions by when they were created.", value: "created_at"
    end
  end
end
