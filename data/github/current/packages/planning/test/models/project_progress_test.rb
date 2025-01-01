# typed: true
# frozen_string_literal: true

require "test_helper"

class ProjectProgressTest < GitHub::TestCase
  test "reports nothing for projects with no columns that have a purpose" do
    repo = create(:repository)
    project = create(:project, owner: repo, track_progress: true)
    no_purpose_column = create(:project_column, project: project)
    3.times { create(:project_card, column: no_purpose_column) }
    progress = ProjectProgress.new(project)

    refute_predicate progress, :enabled?
    assert_equal 0, progress.todo_count
    assert_equal 0, progress.in_progress_count
    assert_equal 0, progress.done_count
    assert_equal 0, progress.todo_percentage
    assert_equal 0, progress.in_progress_percentage
    assert_equal 0, progress.done_percentage
  end

  test "reports nothing for projects that do not have progress tracking enabled" do
    repo = create(:repository)
    project = create(:project, owner: repo, track_progress: false)
    todo_column = create(:project_column, project: project, purpose: ProjectColumn::PURPOSE_TODO)
    create(:project_card, column: todo_column)
    in_progress_column = create(:project_column, project: project, purpose: ProjectColumn::PURPOSE_IN_PROGRESS)
    create(:project_card, column: in_progress_column)
    done_column = create(:project_column, project: project, purpose: ProjectColumn::PURPOSE_DONE)
    create(:project_card, column: done_column)
    progress = ProjectProgress.new(project)

    refute_predicate progress, :enabled?
    assert_equal 0, progress.todo_count
    assert_equal 0, progress.in_progress_count
    assert_equal 0, progress.done_count
    assert_equal 0, progress.todo_percentage
    assert_equal 0, progress.in_progress_percentage
    assert_equal 0, progress.done_percentage
  end

  test "reports the number/percentage of todo, in-progress, and done cards" do
    repo = create(:repository)
    project = create(:project, owner: repo, track_progress: true)
    todo_column = create(:project_column, project: project, purpose: ProjectColumn::PURPOSE_TODO)
    create(:project_card, column: todo_column)
    in_progress_column = create(:project_column, project: project, purpose: ProjectColumn::PURPOSE_IN_PROGRESS)
    2.times { create(:project_card, column: in_progress_column) }
    done_column = create(:project_column, project: project, purpose: ProjectColumn::PURPOSE_DONE)
    3.times { create(:project_card, column: done_column) }
    no_purpose_column = create(:project_column, project: project)
    4.times { create(:project_card, column: no_purpose_column) }
    progress = ProjectProgress.new(project)

    assert_predicate progress, :enabled?
    assert_equal 1, progress.todo_count
    assert_equal 2, progress.in_progress_count
    assert_equal 3, progress.done_count
    assert_equal 1.0 / 6 * 100, progress.todo_percentage
    assert_equal 2.0 / 6 * 100, progress.in_progress_percentage
    assert_equal 50, progress.done_percentage
  end

  test "ignores archived cards" do
    repo = create(:repository)
    project = create(:project, owner: repo, track_progress: true)

    todo_column = create(:project_column, project: project, purpose: ProjectColumn::PURPOSE_TODO)
    todo_cards = Array.new(4) { create(:project_card, column: todo_column) }

    in_progress_column = create(:project_column, project: project, purpose: ProjectColumn::PURPOSE_IN_PROGRESS)
    in_progress_cards = Array.new(4) { create(:project_card, column: in_progress_column) }

    done_column = create(:project_column, project: project, purpose: ProjectColumn::PURPOSE_DONE)
    done_cards = Array.new(4) { create(:project_card, column: done_column) }

    no_purpose_column = create(:project_column, project: project)
    2.times { create(:project_card, column: no_purpose_column) }

    [
      todo_cards[0],
      in_progress_cards[0],
      in_progress_cards[1],
      done_cards[0],
      done_cards[1],
      done_cards[2],
    ].each(&:archive)

    progress = ProjectProgress.new(project)

    assert_equal 3, progress.todo_count
    assert_equal 2, progress.in_progress_count
    assert_equal 1, progress.done_count
    assert_equal 50, progress.todo_percentage
    assert_equal 2.0 / 6 * 100, progress.in_progress_percentage
    assert_equal 1.0 / 6 * 100, progress.done_percentage
  end
end
