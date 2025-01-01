# typed: true
# frozen_string_literal: true

module Users
  class NameplateComponent < ApplicationComponent
    include AvatarHelper

    def initialize(user:, tag: :a, hovercard: false, avatar_size: 24, avatar_spacing: 1, **system_arguments)
      @user = user
      @hovercard = hovercard

      @system_arguments = system_arguments
      @system_arguments[:tag] = tag
      @system_arguments[:label] = @user.display_login
      @system_arguments[:href] = user_path(@user) if tag == :a

      @avatar_arguments = {
        src: avatar_url_for(@user, avatar_size * 2),
        size: avatar_size,
        mr: avatar_spacing
      }
    end

    def call
      render(Primer::Experimental::Nameplate.new(**@system_arguments)) do |c|
        c.with_avatar(**@avatar_arguments)
      end
    end

    # This calls `controller` which is not accessible during initialization
    def before_render
      return unless @hovercard

      @system_arguments[:data] ||= {}
      @system_arguments[:data].merge!(hovercard_data_attributes_for_user(@user))
    end
  end
end
