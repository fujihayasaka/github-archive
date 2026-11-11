# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ProjectCardState < Platform::Enums::Base
      description "Various content states of a ProjectCard"

      value "CONTENT_ONLY", "The card has content only."
      value "NOTE_ONLY", "The card has a note only."
      value "REDACTED", "The card is redacted."
    end
  end
end
