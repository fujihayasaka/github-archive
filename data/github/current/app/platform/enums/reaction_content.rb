# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ReactionContent < Platform::Enums::Base
      description "Emojis that can be attached to Issues, Pull Requests and Comments."

      Emotion.all.each do |emotion|
        value emotion.platform_enum, "Represents the `:#{emotion.label}:` emoji.", value: emotion.content
      end
    end
  end
end
