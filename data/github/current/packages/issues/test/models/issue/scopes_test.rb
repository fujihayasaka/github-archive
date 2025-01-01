# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueScopesTest < GitHub::TestCase
  fixtures do
    @owner = create :user, login: "owner", plan: "large"
    @repo  = create :private_repository, owner: @owner
    @issue_bug = create :issue, repository: @repo, user: @repo.owner
    @issue_feature = create :issue, repository: @repo, user: @repo.owner
    @issue_bug_and_feature = create :issue, repository: @repo, user: @repo.owner

    @label_bug = create(:label, color: "ff0000", name: "Bug", repository: @repo)
    @label_feature = create(:label, color: "ff0000", name: "Feature", repository: @repo)
    @issue_bug.labels << @label_bug
    @issue_feature.labels << @label_feature
    @issue_bug_and_feature.labels << [@label_feature, @label_bug]

    @sorted1 = create :issue, \
      repository: @repo,
      user: @repo.owner,
      created_at: 4.weeks.ago,
      updated_at: 1.day.ago
    @sorted2 = create :issue, \
      repository: @repo,
      user: @repo.owner,
      created_at: 3.weeks.ago,
      updated_at: 2.days.ago
    @sorted3 = create :issue, \
      repository: @repo,
      user: @repo.owner,
      created_at: 2.weeks.ago,
      updated_at: 3.days.ago
    @sorted4 = create :issue, \
      repository: @repo,
      user: @repo.owner,
      created_at: 1.week.ago,
      updated_at: 4.days.ago
    @sorted_issue_ids = [@sorted1, @sorted2, @sorted3, @sorted4].map(&:id)
  end

  context "#labeled" do
    test "returns all issues if nil is provided" do
      assert_equal Issue.all, Issue.labeled(nil)
    end

    test "returns all issues if wrong parameters type is sent" do
      assert_equal Issue.all, Issue.labeled(true)
    end

    test "returns no issues if wrong parameters array is sent" do
      assert_equal [], Issue.labeled([true, false, true])
    end

    test "returns no issues when a non-matching label name is provided" do
      assert_equal [], Issue.labeled("unknown")
    end

    test "returns labels matching the provided label name, case insensitive" do
      assert_equal [@issue_bug, @issue_bug_and_feature], Issue.labeled("bug")
    end

    test "returns issues matching all labels when multiple label names (case insensitive) provided" do
      assert_equal [@issue_bug_and_feature], Issue.labeled(%w[bug feature])
    end

    test "returns labels matching a specific label instance" do
      assert_equal [@issue_bug, @issue_bug_and_feature], Issue.labeled(@label_bug)
    end

    test "returns issues matching all labels when multiple label instances provided" do
      assert_equal [@issue_bug_and_feature], Issue.labeled([@label_bug, @label_feature])
    end

    test "returns labels matching a specific label id" do
      assert_equal [@issue_bug, @issue_bug_and_feature], Issue.labeled(@label_bug.id)
    end

    test "returns issues matching all labels when multiple label ids provided" do
      assert_equal [@issue_bug_and_feature], Issue.labeled([@label_bug.id, @label_feature.id])
    end

    test "returns matching issues and also plays nice with pagination" do
      assert_equal [@issue_bug], Issue.labeled([@label_bug]).paginate(page: 1, per_page: 1)
      assert_equal [@issue_bug_and_feature], Issue.labeled([@label_bug]).paginate(page: 2, per_page: 1)
      assert_equal [@issue_bug, @issue_bug_and_feature], Issue.labeled([@label_bug]).paginate(page: 1, per_page: 10)
    end
  end

  context "#sorted_by" do
    test "with default order" do
      assert_equal [@sorted1, @sorted2, @sorted3, @sorted4], Issue.where(id: @sorted_issue_ids).sorted_by(nil, "asc")
      assert_equal [@sorted4, @sorted3, @sorted2, @sorted1], Issue.where(id: @sorted_issue_ids).sorted_by(nil, "desc")
      assert_equal [@sorted4, @sorted3, @sorted2, @sorted1], Issue.where(id: @sorted_issue_ids).sorted_by(nil)
    end

    test "with order=updated" do
      assert_equal [@sorted4, @sorted3, @sorted2, @sorted1], Issue.where(id: @sorted_issue_ids).sorted_by("updated", "asc")
      assert_equal [@sorted1, @sorted2, @sorted3, @sorted4], Issue.where(id: @sorted_issue_ids).sorted_by("updated", "desc")
      assert_equal [@sorted1, @sorted2, @sorted3, @sorted4], Issue.where(id: @sorted_issue_ids).sorted_by("updated")
    end
  end
end
