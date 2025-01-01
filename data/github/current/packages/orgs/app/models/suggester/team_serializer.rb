# typed: true
# frozen_string_literal: true

module Suggester
  # Converts Team objects into the JSON format expected by the mention
  # suggester protocol. The client-side suggestion menu renders these
  # JSON objects as menu items.
  #
  # Examples
  #
  #   format = Suggester::TeamSerializer.new
  #
  #   format.dump(team)
  #   # => {id, name, …}
  #
  #   teams.map(&format)
  #   # => [{id, name, …}, …]
  class TeamSerializer
    def initialize(get_avatars: false)
      @get_avatars = get_avatars
    end

    def dump(team)
      data = {
        type: "team",
        id: team.id,
        name: team.combined_slug,
        description: (team.description || "").truncate(100, separator: " "),
      }
      data[:avatarUrl] = team.primary_avatar_url if @get_avatars
      data
    end

    def to_proc
      method(:dump).to_proc
    end
  end
end
