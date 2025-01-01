# typed: true
# frozen_string_literal: true

require "test_helper"

class ProjectColumnTemplateTest < GitHub::TestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @column = ProjectColumnTemplate.new(name: "todoodles")
  end

  test "initializes with the required attributes" do
    assert @column.name.length > 0
    assert_nil @column.purpose
    assert @column.workflows.empty?
    assert @column.cards.empty?
  end

  test "formats attributes to a hash" do
    assert_kind_of Hash, @column.data
    assert @column.data[:name]
    assert_nil @column.data[:purpose]
  end

  test "can build a ProjectColumn" do
    project_column = create(:project_column, @column.data)
    assert_equal project_column.name, @column.name
  end

  context "column templates contain workflow triggers" do
    test "to_do" do
      to_do = ProjectColumnTemplate.to_do
      assert_equal 1, to_do.workflows.length
      assert_equal 3, to_do.cards.length
    end

    test "to_do can omit cards" do
      to_do = ProjectColumnTemplate.to_do(include_cards: false)
      assert_equal 1, to_do.workflows.length
      assert_empty to_do.cards
    end

    test "in_progress" do
      in_progress = ProjectColumnTemplate.in_progress
      assert_equal 3, in_progress.workflows.length
    end

    test "needs_review" do
      needs_review = ProjectColumnTemplate.needs_review
      assert_equal 1, needs_review.workflows.length
    end

    test "reviewer_approved" do
      reviewer_approved = ProjectColumnTemplate.reviewer_approved
      assert_equal 1, reviewer_approved.workflows.length
    end

    test "done" do
      done = ProjectColumnTemplate.done
      assert_equal 3, done.workflows.length
    end
  end

  context "template groups" do
    test "creates a 3 column kanban" do
      assert_equal 3, ProjectColumnTemplate.kanban.length
      assert_same_elements [ProjectColumnTemplate.to_do, ProjectColumnTemplate.in_progress, ProjectColumnTemplate.done].map(&:name), ProjectColumnTemplate.kanban.map(&:name)
    end

    test "creates a 5 colummn review kanban" do
      assert_equal 5, ProjectColumnTemplate.kanban_with_reviews.length
      assert_same_elements [ProjectColumnTemplate.to_do, ProjectColumnTemplate.in_progress, ProjectColumnTemplate.needs_review, ProjectColumnTemplate.reviewer_approved, ProjectColumnTemplate.done].map(&:name), ProjectColumnTemplate.kanban_with_reviews.map(&:name)
    end

    test "creates 4 column bug triage" do
      assert_equal 4, ProjectColumnTemplate.bug_triage.length
    end
  end
end
