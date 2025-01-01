# typed: true
# frozen_string_literal: true

require "test_helper"

class ContributionCreatedIssueCommentTest < GitHub::TestCase
  include AuditLogHelpers

  fixtures do
    @user = create(:user, plan: "medium")
    @repo  = create(:repository, owner: @user)
    @issue = create(:issue, repository: @repo, body: "Heyo! An issue!", user: @user)
  end

  context "#occurred_at" do
    test "is the created_at of the issue comment" do
      issue_comment = create(:issue_comment, issue: @issue, user: @user)
      contribution = Contribution::CreatedIssueComment.new(
        subject: issue_comment,
        user: @user,
      )
      assert_equal issue_comment.created_at, contribution.occurred_at
    end
  end

  context "#repository" do
    test "returns the associated repository" do
      issue_comment = create(:issue_comment, issue: @issue, user: @user)
      contribution = Contribution::CreatedIssueComment.new(
        subject: issue_comment,
        user: @user,
      )
      assert_equal @repo, contribution.repository
    end
  end

  context "#associated_subject" do
    test "returns the repository of the issue comment" do
      issue_comment = create(:issue_comment, issue: @issue, user: @user)
      contribution = Contribution::CreatedIssueComment.new(
        subject: issue_comment,
        user: @user,
      )
      assert_equal issue_comment.repository, contribution.associated_subject
    end
  end

  context "#comment" do
    test "returns the issue comment" do
      issue_comment = create(:issue_comment, issue: @issue, user: @user)
      contribution = Contribution::CreatedIssueComment.new(
        subject: issue_comment,
        user: @user,
      )
      assert_equal issue_comment, contribution.comment
    end
  end

  context "#repository_id" do
    test "returns the id of the commit contribution's repository" do
      issue_comment = create(:issue_comment, issue: @issue, user: @user)
      contribution = Contribution::CreatedIssueComment.new(
        subject: issue_comment,
        user: @user,
      )
      assert_equal issue_comment.repository.id, contribution.repository_id
    end
  end

  def subjects_for(
    user,
    date_range: Date.yesterday..Date.tomorrow,
    organization_id: nil,
    excluded_organization_ids: []
  )
    contribution_class = Contribution::CreatedIssueComment
    contribution_class.subjects_for(
      user, date_range: date_range, organization_id: organization_id,
      excluded_organization_ids: excluded_organization_ids
    )
  end

  context "::subjects_for" do
    test "includes the user's issue comments" do
      issue_comment = create(:issue_comment, issue: @issue, user: @user)

      private_repo = create(:private_repository, owner: @user)
      private_issue = create(:issue, repository: private_repo, user: @user)
      private_issue_comment = create(:issue_comment, issue: private_issue, user: @user)

      subjects = subjects_for(@user)
      subjects.each do |subject|
        assert_kind_of IssueComment, subject
      end
      expected = [issue_comment, private_issue_comment]
      assert_same_elements expected, subjects
    end

    test "allows filtering comments by organization_id" do
      org_a, org_b = create_pair(:organization, public_members: [@user]).each do |org|
        repo = create(:private_repository, owner: org)
        issue = create(:issue, repository: repo, user: @user)
        create(:issue_comment, issue: issue, user: @user)
      end

      subjects = subjects_for(@user, organization_id: org_a.id)

      assert_same_elements org_a.repositories.first.issues.first.comments, subjects
    end

    test "excludes contributions in orgs specified by excluded_organization_ids" do
      excluded_org, other_org = create_pair(:organization, public_members: [@user]) do |org|
        repo = create(:private_repository, owner: org)
        issue = create(:issue, repository: repo, user: @user)
        create(:issue_comment, issue: issue, user: @user)
      end

      subjects = subjects_for(
        @user, date_range: Date.yesterday..Date.tomorrow, excluded_organization_ids: [excluded_org.id]
      )

      assert_same_elements other_org.repositories.first.issues.first.comments, subjects
    end

    test "only returns issue comments created in the given date range" do
      # Freeze time such that it is July 15 in San Francisco, July 16 in UTC
      Timecop.freeze(Time.local(2019, 7, 15, 20, 0, 0).in_time_zone("Pacific Time (US & Canada)")) do
        user = create(:user)
        repo = create(:repository, owner: user)
        issue = create(:issue, repository: repo, user: user)
        now = Time.zone.now
        create(:issue_comment, issue: issue, user: user, created_at: now)

        subjects = subjects_for(user, date_range: now.to_date..now.to_date)
        refute_empty subjects

        subjects = subjects_for(user, date_range: 3.days.ago.to_date..2.days.ago.to_date)
        assert_empty subjects

        subjects = subjects_for(user, date_range: 2.days.since.to_date..3.days.since.to_date)
        assert_empty subjects
      end
    end

    test "only returns commit contributions created by the specified user" do
      subjects = subjects_for(create(:user))
      assert_empty subjects
    end

    test "does not include spammy comments" do
      user = create(:user, spammy: true)
      repo = create(:repository, owner: user)
      issue = create(:issue, repository: repo, user: user)
      create(:issue_comment, user: user, issue: issue)

      subjects = subjects_for(@user, date_range: 3.days.ago.to_date..Date.today)
      assert_empty subjects
    end
  end
end
