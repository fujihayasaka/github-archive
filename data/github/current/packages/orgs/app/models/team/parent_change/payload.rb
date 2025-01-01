# typed: true
# frozen_string_literal: true

module Team::ParentChange

  # Encapsulates the data needed to perform the recalculation of
  # user permissions when a team is moved inside a hierarchy
  # plus a set of convenient operations.
  class Payload
    attr_reader :team_id,         # Team being moved
                :old_path,        # Old path the team had inside the hierarchy before the parent change
                :new_path,        # New path the team has inside the hierarchy after the parent change
                :old_descendants  # Old descendants in the hierarchy. This is necessary as descendants
    # are updated in the foreground one the team is moved in the hierarchy,
    # so that information is no longer available in the background.

    def initialize(team_id:, old_path:, new_path:, old_descendants:)
      @team_id = team_id
      @old_path = old_path
      @new_path = new_path
      @old_descendants = old_descendants
    end

    # Parses de old path extracting a list of integers, each of which was
    # an ancestor of this instance's team_id before the change
    def old_ancestors
      @old_ancestors ||= Team::Nested::TeamTreeNode.new(old_path).ancestors
    end

    # Parses de new path extracting a list of integers, each of which is
    # an ancestor of this instance's team_id after the change
    def new_ancestors
      @new_ancestors ||= Team::Nested::TeamTreeNode.new(new_path).ancestors
    end

    def to_hash
      {
        team_id: team_id,
        old_path: old_path,
        new_path: new_path,
        old_descendants: old_descendants,
      }
    end

    def self.from_hash(h)
      h.symbolize_keys!
      new(team_id: h[:team_id], old_path: h[:old_path], new_path: h[:new_path], old_descendants: h[:old_descendants])
    end

    def hash
      to_hash.hash
    end

    def ==(other)
      other.is_a?(Payload) && to_hash == other.to_hash
    end
  end
end
