# typed: true
# frozen_string_literal: true

# Public: This class represents the mutation for repositioning discussion
# spotlights. This class is necessary due to complexity caused by MySQL
# update constraints around unique indexes.
class DiscussionSpotlightPositioner
  sig { params(repo: T.untyped, sorted_ids: T.untyped).returns(T.untyped) }
  def self.reposition!(repo, sorted_ids)
    new(repo, sorted_ids).reposition!
  end

  sig { params(repo: T.untyped, sorted_ids: T.untyped).void }
  def initialize(repo, sorted_ids)
    @repo = repo
    @sorted_ids = sorted_ids
  end

  sig { void }
  def reposition!
    DiscussionSpotlight.transaction do
      # First, sort the spotlights using positions *after* the max position.
      # MySQL doesn't allow an in-place swap via `update` so we have to swap
      # positions in two steps.
      safe_offset = repo.discussion_spotlights.maximum(:position) + 1
      reposition_with_offset!(safe_offset)

      # Now that we're past the maximum position, we can reposition again, but
      # start with 1. This is necessary because too many sorts could cause us
      # to go over the maximum value of `position`, so we reset each sort
      # back to the lowest number possible.
      reposition_with_offset!(1)
    end
  end

  private

  attr_reader :repo, :sorted_ids

  def reposition_with_offset!(offset)
    sql = Arel.sql "UPDATE discussion_spotlights SET position = CASE id"

    sorted_ids.map.with_index do |id, index|
      sql += Arel.sql("WHEN :id THEN :value", id: id, value: index + offset)
    end

    sql += Arel.sql("END WHERE repository_id = :repository_id AND id IN (:ids)", repository_id: @repo.id, ids: sorted_ids)
    DiscussionSpotlight.connection.update(sql)
  end
end
