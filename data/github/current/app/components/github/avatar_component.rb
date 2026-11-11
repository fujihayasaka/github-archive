# typed: true
# frozen_string_literal: true

module GitHub
  class AvatarComponent < ApplicationComponent
    include AvatarHelper

    DEFAULT_SIZE = 20

    def initialize(actor: nil, size: DEFAULT_SIZE, alt: nil, src: nil, is_user: nil, **system_arguments)
      @actor = actor
      @alt = alt
      @alt ||= alt_text(actor) if actor
      @src = src
      @is_user = is_user
      @is_user = avatar_user_actor?(actor) if @is_user.nil? && actor
      @system_arguments = system_arguments
      @system_arguments[:alt] = @alt
      @system_arguments[:size] = size
      @src ||= avatar_url_for(actor, @system_arguments[:size] * 2) if actor
      @system_arguments[:src] = @src
      @system_arguments[:shape] = @is_user ? :circle : :square
    end

    def call
      render(Primer::Beta::Avatar.new(**@system_arguments)) { content }
    end

    private

    def render?
      @src.present?
    end
  end
end
