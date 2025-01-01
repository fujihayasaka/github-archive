# typed: true
# frozen_string_literal: true

module Users
  class PostAsAdminNameplateComponent < ApplicationComponent

    def initialize(avatar_size: 24, avatar_spacing: 1, **system_arguments)
      @system_arguments = system_arguments
      @system_arguments[:label] = "Admin"
      @system_arguments[:tag] = :span

      @avatar_arguments = {
        src: ::User::AvatarList.default_image_url,
        size: avatar_size,
        mr: avatar_spacing
      }
    end

    def call
      render(Primer::Experimental::Nameplate.new(**@system_arguments)) do |c|
        c.with_avatar(**@avatar_arguments)
      end
    end
  end
end
