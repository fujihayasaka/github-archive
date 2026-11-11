# typed: true
# frozen_string_literal: true

class MergeQueues::EntryStatus::MergeConflictsComponent < ApplicationComponent
  def initialize(blocked:)
    @blocked = blocked
  end

  def call
    render MergeQueues::EntryStatus::DetailComponent.new(
      summary_color: summary_color,
      summary: summary,
      details: details,
      test_selector_prefix: "merge-conflicts-status",
    )
  end

  private

  def blocked?
    @blocked
  end

  def summary_color
    if blocked?
      :danger
    else
      :success
    end
  end

  def summary
    if blocked?
      "This branch has conflicts"
    else
      "This branch has no conflicts"
    end
  end

  def details
    if blocked?
      "Resolve conflicts before merging."
    else
      "Merging can be performed automatically."
    end
  end
end
