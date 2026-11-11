# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class DiscussionState < Platform::Enums::Base
      docs_category :discussions
      description "The possible states of a discussion."

      value "OPEN", "A discussion that is open", value: :open
      value "CLOSED", "A discussion that has been closed", value: :closed
    end
  end
end
