# typed: strict
# frozen_string_literal: true

module Actions::WorkflowTemplate
  module Source
    NONE = 0
    SHARED = 1
    OWNER = 2
    ALL = 3

    # Repository visibility constants
    module Visibility
      PUBLIC = "public"
      PRIVATE = "private"
      INTERNAL = "internal"
      SHARED = "shared"
      BLANK = "blank"
    end
  end
end
