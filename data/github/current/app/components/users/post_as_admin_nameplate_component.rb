# typed: true
# frozen_string_literal: true

module Users
  class PostAsAdminNameplateComponent < ApplicationComponent
    def initialize(owner:, avatar_size: 24, avatar_spacing: 1, **system_arguments)
      @system_arguments = system_arguments
      @system_arguments[:label] = "#{owner.safe_profile_name} Admin"
      @system_arguments[:tag] = :span

      @avatar_arguments = {
        src: owner.primary_avatar_url,
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
