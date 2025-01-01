# typed: true
# frozen_string_literal: true

module Suggester
  # A composite serializer that converts User and Team objects into the
  # JSON format expected by the mention suggester protocol. The client-side
  # suggestion menu renders these JSON objects as menu items.
  #
  # Examples
  #
  #   format = Suggester::MentionSerializer.new(viewer: user)
  #
  #   format.dump(users, teams)
  #   # => [{id, login, …}]
  class MentionSerializer
    def initialize(viewer:, get_avatars: false)
      @viewer = viewer
      @get_avatars = get_avatars
    end

    def dump(users, teams, participants = [])
      to_hash = UserSerializer.new(viewer: @viewer, get_avatars: @get_avatars)

      mentions = participants.map do |participant|
        info = to_hash.dump(participant)
        info[:participant] = true
        info
      end

      mentions.concat(users.map(&to_hash))

      to_hash = TeamSerializer.new(get_avatars: @get_avatars)
      mentions + teams.map(&to_hash)
    end
  end
end
