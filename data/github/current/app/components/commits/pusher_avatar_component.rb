# typed: true
# frozen_string_literal: true

module Commits
  class PusherAvatarComponent < ApplicationComponent
    LARGE_AVATAR_SIZE = 32

    attr_reader :size, :pusher

    def initialize(pusher:, size: GitHub::AvatarComponent::DEFAULT_SIZE)
      @pusher = pusher
      @size = size
    end

    # Classes for AvatarStack parent element, which control display and sizing modifiers
    # See https://primer.style/css/components/avatars#avatar-stack
    #
    # Returns String
    def avatar_stack_classes
      "AvatarStack flex-self-start #{avatar_stack_count_class(1)} #{'AvatarStack--large' if size == LARGE_AVATAR_SIZE}"
    end

    # Attributes for the avatar profile link tag
    #
    # Returns Hash
    def profile_link_options
      options = {
        class: helpers.avatar_class_names(pusher),
        style: "width:#{size}px;height:#{size}px;",
        data: {
          "test-selector": "commits-pusher-avatar-link"
        }
      }
    end
  end
end
