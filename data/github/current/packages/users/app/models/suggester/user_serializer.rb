# typed: true
# frozen_string_literal: true

module Suggester
  # Converts User objects into the JSON format expected by the mention
  # suggester protocol. The client-side suggestion menu renders these
  # JSON objects as menu items.
  #
  # Examples
  #
  #   format = Suggester::UserSerializer.new(viewer: user)
  #
  #   format.dump(user)
  #   # => {id, login, …}
  #
  #   users.map(&format)
  #   # => [{id, login, …}, …]
  class UserSerializer
    def initialize(viewer:, get_avatars: false)
      @viewer = viewer
      @get_avatars = get_avatars
    end

    def dump(user)
      data = {
        type: "user",
        id: user.id,
        login: login(user),
        name: name(user),
      }
      data[:avatarUrl] = user.primary_avatar_url if @get_avatars
      data
    end

    def to_proc
      method(:dump).to_proc
    end

    private

    def name(user)
      return user.display_login if user.is_a?(Bot) && Apps::Privileged.capable?(:pr_autocomplete_mentionable_as_author, app: user.integration)

      prefix = user.profile_name
      suffix = user.busy?(viewer: @viewer) ? "(busy)" : nil
      [prefix, suffix].compact.join(" ")
    end

    def login(user)
      if user.is_a?(Bot)
        return user.slug if user.is_dependabot?
        return user.display_login.downcase if Apps::Privileged.capable?(:pr_autocomplete_mentionable_as_author, app: user.integration)
      end

      user.display_login
    end
  end
end
