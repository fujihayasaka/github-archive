# typed: true
# frozen_string_literal: true
module Repository::MilestoneDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { Repository }

  # Returns available milestones for this repository (for use in suggestion experiences).
  #
  # current_milestone - Milestone that should be omitted from the result (presumably because the
  #   caller is presenting an issue or pull request that is already assigned this milestone).
  #
  # Returns a two-element Array where the first element is itself an Array of all open milestones
  #   sorted by title and the second element is Array of all closed milestones sorted by
  #   descending updated_at time.
  def available_milestones(current_milestone: nil)
    all_milestones = milestones.all.to_a
    all_milestones.delete(current_milestone) if current_milestone

    open_milestones, closed_milestones = all_milestones.partition(&:open?)

    open_milestones.sort_by!(&:title)
    closed_milestones.sort_by!(&:updated_at).reverse!

    [open_milestones, closed_milestones]
  end
end
