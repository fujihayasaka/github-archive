# typed: true
# frozen_string_literal: true

require "test_helper"

class AppliedDiscussionLabelTest < GitHub::TestCase
  fixtures do
    @repo0, @repo1 = create_pair(:repository, has_discussions: true)

    @discussion0 = create(:discussion, repository: @repo0)
    @label0 = create(:label, repository: @repo0)
  end

  test "populates repository_id" do
    applied = create(:applied_discussion_label, label: @label0, discussion: @discussion0, repository: nil)
    assert_equal @repo0, applied.repository
  end

  context "validations" do
    test "requires a label" do
      applied = build(:applied_discussion_label, label: nil)
      refute_predicate applied, :valid?
    end

    test "requires a discussion" do
      applied = build(:applied_discussion_label, discussion: nil)
      refute_predicate applied, :valid?
    end

    test "ensures the label and discussion belong to the same repository" do
      discussion = create(:discussion, repository: @repo1)

      applied = build(:applied_discussion_label, label: @label0, discussion: discussion)
      refute_predicate applied, :valid?
    end
  end
end
