# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueLinkTest < GitHub::TestCase
  context "validations" do
    test "requires source issue" do
      link = IssueLink.new
      refute_predicate link, :valid?
      assert_includes link.errors[:source_issue], "must exist"
    end

    test "requires target issue" do
      link = IssueLink.new
      refute_predicate link, :valid?
      assert_includes link.errors[:target_issue], "must exist"
    end

    test "requires actor" do
      link = IssueLink.new
      refute_predicate link, :valid?
      assert_includes link.errors[:actor], "must exist"
    end

    test "requires source_repository_id" do
      link = IssueLink.new
      refute_predicate link, :valid?
      assert_includes link.errors[:source_repository], "can't be blank"
    end

    test "requires target_repository_id" do
      link = IssueLink.new
      refute_predicate link, :valid?
      assert_includes link.errors[:target_repository], "can't be blank"
    end

    test "requires a unique issues + link_type pair" do
      issue_link = create(:issue_link)

      duplicated_issue_link = build(:issue_link,
        source_issue: issue_link.source_issue,
        target_issue: issue_link.target_issue,
        link_type: issue_link.link_type
      )
      refute_predicate duplicated_issue_link, :valid?
      assert duplicated_issue_link.errors.details[:target_issue_id]&.first[:error], :taken
      assert_includes duplicated_issue_link.errors[:target_issue_id], "has already been taken"

      other_issue_link = build(:issue_link,
        source_issue: issue_link.source_issue,
        target_issue: create(:issue),
      )
      assert_predicate other_issue_link, :valid?
    end

    test "requires a tracked issues's source and target to be unequal" do
      issue = create(:issue)
      issue_link = build(:issue_link,
        source_issue: issue,
        target_issue: issue,
        link_type: :track
      )

      refute_predicate issue_link, :valid?
      assert issue_link.errors.details[:base]&.first[:error], :self_reference
      assert_includes issue_link.errors[:base], "Tracking Source and Target have to be different"
    end
  end
end
