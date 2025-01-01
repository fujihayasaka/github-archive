# typed: true
# frozen_string_literal: true

# Helper class to track overall project progress based on cards in columns
# with a to do, in progress, or done purpose configured.
#
# This class will only return progress details if the project has been
# configured to track progress via the `track_progress` field.
#
# It should be accessed via `project.progress` which will never be nil
# and returns counts and percentages of the number of cards in to do,
# in-progress, and done columns (i.e `todo_count`, `done_percentage`, etc.)
class ProjectProgress

  attr_reader :todo_count, :in_progress_count, :done_count
  attr_reader :todo_percentage, :in_progress_percentage, :done_percentage

  def initialize(project)
    if project.track_progress
      purpose_counts = project.cards.not_archived.with_purpose.group(:purpose).size

      @todo_count = purpose_counts.fetch(ProjectColumn::PURPOSE_TODO, 0)
      @in_progress_count = purpose_counts.fetch(ProjectColumn::PURPOSE_IN_PROGRESS, 0)
      @done_count = purpose_counts.fetch(ProjectColumn::PURPOSE_DONE, 0)
    else
      @todo_count = 0
      @in_progress_count = 0
      @done_count = 0
    end

    @todo_percentage = to_percentage(todo_count)
    @in_progress_percentage = to_percentage(in_progress_count)
    @done_percentage = to_percentage(done_count)
  end

  # Is the project configured to track progress and does it have at least one
  # card in a to do, in progress, or done column?
  def enabled?
    cards_with_purpose_count > 0
  end

  private

  def cards_with_purpose_count
    todo_count + in_progress_count + done_count
  end

  def to_percentage(count)
    total = cards_with_purpose_count
    if total > 0
      (count.to_f / total) * 100
    else
      0
    end
  end
end
