# typed: true
# frozen_string_literal: true

require "test_helper"

class ContributionCreatedIssueTest < GitHub::TestCase
  fixtures do
    @user = create :user, plan: "medium"
    @repo = create :repository, owner: @user, from_example: :simple
    @issue = create :issue, user: @user, repository: @repo
  end

  setup do
    @contribution = Contribution::CreatedIssue.new(
      user: @user,
      subject: @issue,
    )
  end

  context "#occurred_at" do
    test "returns the issue's contribution_time" do
      assert_equal @issue.contribution_time, @contribution.occurred_at
    end
  end

  [:state, :repository, :contribution_time, :title, :number].each do |method|
    context "##{method}" do
      test "returns the issue #{method}" do
        assert_equal @issue.send(method), @contribution.send(method)
      end
    end
  end

  context "#associated_subject" do
    test "returns the repository of the issue" do
      assert_equal @issue.repository, @contribution.associated_subject
    end
  end

  context "#organization_id" do
    test "returns the organization ID of the repository of the issue" do
      org_id = 123
      repo = stub(organization_id: org_id)
      issue = stub(repository: repo)
      contribution = Contribution::CreatedIssue.new(user: @user, subject: issue)
      assert_equal org_id, contribution.organization_id
    end
  end

  context "#issue" do
    test "returns the issue" do
      assert_equal @issue, @contribution.issue
    end
  end

  context "#comments_count" do
    test "returns the issue comments count" do
      2.times { create :issue_comment, issue: @issue }
      assert_equal 2, @contribution.comments_count
    end
  end

  context "#repository_id" do
    test "returns the id of the issue's repository" do
      assert_equal @issue.repository_id, @contribution.repository_id
    end
  end

  def subjects_for(
    user,
    date_range: Date.yesterday..Date.tomorrow,
    organization_id: nil,
    excluded_organization_ids: []
  )
    contribution_class = Contribution::CreatedIssue
    contribution_class.subjects_for(
      user, date_range: date_range, organization_id: organization_id,
      excluded_organization_ids: excluded_organization_ids
    )
  end

  context "::subjects_for" do
    test "includes the user's issues" do
      private_repo = create :private_repository, owner: @user
      private_issue = create :issue, user: @user, repository: private_repo

      subjects = subjects_for(@user)
      subjects.each do |subject|
        assert_kind_of Issue, subject
      end
      assert_same_elements [@issue, private_issue], subjects
    end

    test "allows filtering issues by organization" do
      org_a, org_b = create_pair(:organization, public_members: [@user]).each do |org|
        repo = create :private_repository, owner: org
        create :issue, user: @user, repository: repo
      end

      subjects = subjects_for(@user, organization_id: org_a.id)

      assert_same_elements org_a.repositories.first.issues, subjects
    end

    test "excludes contributions in orgs specified by excluded_organization_ids" do
      excluded_org, other_org = create_pair(:organization, public_members: [@user]) do |org|
        repo = create :private_repository, owner: org
        create :issue, user: @user, repository: repo
      end

      subjects = subjects_for(@user, excluded_organization_ids: [excluded_org.id])

      assert_same_elements \
        [@issue, other_org.repositories.first.issues.first],
        subjects
    end

    test "excludes contributions when the repository has been deleted" do
      excluded_org, other_org = create_pair(:organization, public_members: [@user])
      excluded_org_repo = create :private_repository, owner: excluded_org
      create :issue, user: @user, repository: excluded_org_repo
      other_org_repo = create :private_repository, owner: other_org
      create :issue, user: @user, repository: other_org_repo

      excluded_org_repo.destroy

      subjects = subjects_for(@user, excluded_organization_ids: [excluded_org.id])

      assert_same_elements(
        [@issue, other_org.repositories.first.issues.first],
        subjects,
      )
    end

    test "only returns issues created in the given time range with buffer" do
      end_date = (@issue.created_at - Contribution::TimezoneFiltering::TIMEZONE_BUFFER - 2.days).to_date
      start_date = (end_date - 1.day).to_date

      subjects = subjects_for(@user, date_range: start_date..end_date)
      assert_empty subjects
    end

    test "only returns issues created by the specified user" do
      subjects = subjects_for(create(:user))
      assert_empty subjects
    end

    test "limits the number of issues to avoid performance bottlenecks" do
      subjects = subjects_for(@user)
      refute_empty subjects

      Contribution.stub_const(:DEFAULT_COUNT_LIMIT, 0) do
        subjects = subjects_for(@user)
        assert_empty subjects
      end
    end

    test "does not return a contribution for an issue tied to a pull request" do
      subjects = subjects_for(@user)
      assert_equal 1, subjects.to_a.size

      create(:pull_request, user: @user, issue: @issue, repository: @repo,
                       created_at: Time.zone.now, head_ref: "cr-line-endings")

      subjects = subjects_for(@user)
      assert_empty subjects
    end

    test "returns issues where contributed_at_timestamp is `nil`" do
      user = create(:user)
      issue = create(:issue, user: user)

      issue.update contributed_at_timestamp: nil, contributed_at_offset: nil
      assert_nil issue.reload.contributed_at

      subjects = subjects_for(user)
      assert_equal [issue], subjects
    end
  end

  context "::first_subject_for" do
    test "returns the first issue" do
      issue = Timecop.freeze(@issue.created_at.yesterday) do
        create(:issue, user: @user)
      end

      assert_equal issue, Contribution::CreatedIssue.first_subject_for(@user)
    end

    test "does not return an issue tied to a pull request" do
      create(:pull_request, user: @user, repository: @repo,
                       head_ref: "cr-line-endings", issue: @issue)

      assert_nil Contribution::CreatedIssue.first_subject_for(@user)
    end

    test "includes the first issue from a private repository" do
      user = create(:user, plan: "medium")
      private_repo = create(:private_repository, owner: user)
      issue = create(:issue, user: user, repository: private_repo)

      assert_equal issue, Contribution::CreatedIssue.first_subject_for(user)
    end

    test "returns the first issue excluding issues in orgs specified by excluded_organization_ids" do
      user = create :user

      excluded_org = create :organization, admin: user
      excluded_org_repo = create :private_repository, owner: excluded_org
      excluded_issue = create :issue, user: user, repository: excluded_org_repo

      other_org = create :organization, admin: user
      other_org_repo = create :private_repository, owner: other_org
      other_issue = create :issue, user: user, repository: other_org_repo

      assert_equal \
        other_issue,
        Contribution::CreatedIssue.first_subject_for(
          user, excluded_organization_ids: [excluded_org.id]
        )
    end

    test "only returns the first issue created by the specified user" do
      user = create(:user)

      assert_nil Contribution::CreatedIssue.first_subject_for(user)
    end

    test "doesn't return orphaned issues" do
      assert_equal @issue, Contribution::CreatedIssue.first_subject_for(@user)

      @issue.repository.destroy
      refute_nil @issue.reload.repository_id
      assert_nil @issue.repository

      assert_nil Contribution::CreatedIssue.first_subject_for(@user)
    end

    test "doesn't return issues of deleted repositories" do
      assert_equal @issue, Contribution::CreatedIssue.first_subject_for(@user)

      @issue.repository.update(active: nil)

      assert_nil Contribution::CreatedIssue.first_subject_for(@user)
    end
  end
end
