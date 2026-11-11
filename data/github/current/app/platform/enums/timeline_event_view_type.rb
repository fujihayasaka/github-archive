# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class TimelineEventViewType < Platform::Enums::Base
      docs_category :issues
      description "The view type of timeline events to return."
      visibility :internal

      value "CONVERSATION", "Only conversation events (comments, references, state changes).", value: :conversation
      value "ACTIVITY", "Only activity events (labels, assignments, etc.).", value: :activity
    end
  end
end
