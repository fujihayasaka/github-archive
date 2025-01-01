# typed: true
# frozen_string_literal: true

require "test_helper"

class ContributionCreatedCommitTest < GitHub::TestCase
  include AuditLogHelpers

  fixtures do
    @user = create(:user, plan: "medium")
  end

  context "#organization_id" do
    test "returns the organization ID of the repository of the commit contribution" do
      org_id = 123
      repo = stub(organization_id: org_id)
      commit_contribution = stub(repository: repo)
      contribution = Contribution::CreatedCommit.new(user: @user, subject: commit_contribution)
      assert_equal org_id, contribution.organization_id
    end
  end

  context "#occurred_at" do
    test "is the committed_date of the commit contribution" do
      commit_contribution = create(:commit_contribution, :with_summaries, user: @user)
      contribution = Contribution::CreatedCommit.new(
        subject: commit_contribution,
        user: @user,
      )

      assert_equal commit_contribution.committed_date, contribution.occurred_at
    end

    test "is the contributed_on date of the commit contribution" do
      commit_contribution = create(:commit_contribution, :with_summaries, user: @user)
      contribution = Contribution::CreatedCommit.new(
        subject: commit_contribution,
        user: @user,
      )

      assert_equal commit_contribution.contributed_on, contribution.occurred_at
    end
  end

  context "#repository" do
    test "returns the associated repository" do
      commit_contribution = create(:commit_contribution, :with_summaries, user: @user)
      contribution = Contribution::CreatedCommit.new(
        subject: commit_contribution,
        user: @user,
      )

      assert_equal commit_contribution.repository, contribution.repository
    end
  end

  context "#associated_subject" do
    test "returns the repository of the commit contribution" do
      commit_contribution = create(:commit_contribution, :with_summaries, user: @user)
      contribution = Contribution::CreatedCommit.new(
        subject: commit_contribution,
        user: @user,
      )

      assert_equal commit_contribution.repository, contribution.associated_subject
    end
  end

  context "#commit_contribution" do
    test "returns the commit contribution" do
      commit_contribution = create(:commit_contribution, :with_summaries, user: @user)
      contribution = Contribution::CreatedCommit.new(
        subject: commit_contribution,
        user: @user,
      )

      assert_equal commit_contribution, contribution.commit_contribution
    end
  end

  context "#repository_id" do
    test "returns the id of the commit contribution's repository" do
      commit_contribution = create(:commit_contribution, :with_summaries, user: @user)
      contribution = Contribution::CreatedCommit.new(
        subject: commit_contribution,
        user: @user,
      )

      assert_equal commit_contribution.repository.id, contribution.repository_id
    end
  end

  context "#contributions_count" do
    test "returns the number of commits of the commit contribution" do
      commit_contribution = create(:commit_contribution, :with_summaries, user: @user, commit_count: 10)
      contribution = Contribution::CreatedCommit.new(
        subject: commit_contribution,
        user: @user,
      )

      assert_equal commit_contribution.commit_count, contribution.contributions_count
    end
  end

  def subjects_for(
    user,
    date_range: Date.yesterday..Date.tomorrow,
    organization_id: nil,
    excluded_organization_ids: []
  )
    contribution_class = Contribution::CreatedCommit
    contribution_class.subjects_for(
      user, date_range: date_range, organization_id: organization_id,
      excluded_organization_ids: excluded_organization_ids
    )
  end

  def create_contribution_for(user, repository: nil, date: Date.today)
    unless repository
      repository = create(:repository)
      repository.add_member(user)
    end
    create(:commit_contribution, :with_summaries, user: user,
      repository: repository,
      committed_date: date)
  end

  def assert_same_contributions(expected, actual)
    expected_attributes = expected.map { |c| c.slice(:user_id, :repository_id, :commit_count, :committed_date) }
    actual_attributes = actual.map { |c| c.slice(:user_id, :repository_id, :commit_count, :committed_date) }
    assert_same_elements expected_attributes, actual_attributes
  end

  context "::subjects_for" do
    test "includes the user's commit contributions" do
      public_contribution = create_contribution_for(@user)
      private_repo = create(:private_repository, owner: @user)
      private_contribution = create_contribution_for(@user, repository: private_repo)

      subjects = subjects_for(@user)
      subjects.each do |subject|
        assert_kind_of CommitContribution, subject
      end
      expected = [public_contribution, private_contribution]
      assert_same_contributions expected, subjects
    end

    test "only returns commit contributions created in the given date range" do
      # Freeze time such that it is July 15 in San Francisco, July 16 in UTC
      Timecop.freeze(Time.local(2019, 7, 15, 20, 0, 0).in_time_zone("Pacific Time (US & Canada)")) do
        commit = create_contribution_for(@user)
        subjects = subjects_for(@user, date_range: Date.today..Date.today)
        refute_empty subjects

        subjects = subjects_for(@user, date_range: Date.new(2019, 7, 13)..Date.new(2019, 7, 14))
        assert_empty subjects

        subjects = subjects_for(@user, date_range: Date.new(2019, 7, 16)..Date.new(2019, 7, 17))
        assert_empty subjects
      end
    end

    test "allows filtering by organization for normal contributors" do
      create_contribution_for(@user, repository: create(:repository, owner: @user)) # non-org contribution
      org_a, org_b = create_pair(:organization, public_members: [@user]) do |org|
        repo = create(:repository, owner: org)
        create_contribution_for(@user, repository: repo)
      end

      subjects = subjects_for(@user, date_range: Date.yesterday..Date.tomorrow, organization_id: org_a.id)

      assert_same_contributions CommitContribution.for_repository(org_a.repositories.first), subjects
    end

    test "excludes contributions in orgs specified by excluded_organization_ids" do
      excluded_org, other_org = create_pair(:organization, public_members: [@user]) do |org|
        repo = create(:repository, owner: org)
        create_contribution_for(@user, repository: repo)
      end

      subjects = subjects_for(
        @user, date_range: Date.yesterday..Date.tomorrow, excluded_organization_ids: [excluded_org.id]
      )

      assert_same_contributions CommitContribution.for_repository(other_org.repositories.first), subjects
    end

    test "allows filtering by organization for large-scale contributors, returns empty collection" do
      create_contribution_for(@user, repository: create(:repository, owner: @user)) # non-org contribution
      org_a, org_b = create_pair(:organization, public_members: [@user]) do |org|
        repo = create(:repository, owner: org)
        create_contribution_for(@user, repository: repo)
      end

      @user.flag_as_large_scale_contributor!

      subjects = subjects_for(@user, date_range: Date.yesterday..Date.tomorrow, organization_id: org_a.id)

      assert_empty subjects
    end

    test "only returns commit contributions created by the specified user" do
      create_contribution_for(@user)

      subjects = subjects_for(create(:user))
      assert_empty subjects
    end

    test "only considers contributions to owned public repositories when user is a large-scale contributor" do
      public_owned_repo = create(:public_repository, owner: @user)
      public_owned_contribution = create_contribution_for(@user,
                                    repository: public_owned_repo)
      public_repo = create(:public_repository, owner: create(:user))
      create_contribution_for(@user, repository: public_repo)
      private_repo = create(:private_repository, owner: @user)
      create_contribution_for(@user, repository: private_repo)

      @user.flag_as_large_scale_contributor!
      subjects = subjects_for(@user)
      assert_same_contributions [public_owned_contribution], subjects
    end

    context "large scale contributors" do
      test "marks a user with lots of contribution records as a large scale contributor" do
        create_contribution_for(@user)
        create_contribution_for(@user)

        CommitContribution.stub_const(:LARGE_SCALE_CONTRIBUTOR_LIMIT, 1) do
          refute @user.large_scale_contributor?
          subjects_for(@user)
          assert @user.large_scale_contributor?
        end
      end

      test "does not mark a user as a large scale contributor if they're under the limit" do
        create_contribution_for(@user)

        CommitContribution.stub_const(:LARGE_SCALE_CONTRIBUTOR_LIMIT, 1) do
          refute @user.large_scale_contributor?
          subjects_for(@user)
          refute @user.large_scale_contributor?
        end
      end
    end

    context "spam protection" do
      test "includes commit contributions made to repositories the user is a collaborator of" do
        repo = create(:repository)
        create_contribution_for(@user, repository: repo)

        assert_empty subjects_for(@user)

        repo.add_member(@user)

        assert_equal 1, subjects_for(@user).size
      end

      test "includes commit contributions made to repositories owned by organization the user is a member of" do
        org = create(:organization)
        repo = create(:repository, owner: org)
        create_contribution_for(@user, repository: repo)

        assert_empty subjects_for(@user)

        org.add_member(@user)

        assert_equal 1, subjects_for(@user).size
      end

      test "includes commit contributions made to repositories the user cannot access but are owned by an organization the user is a member of" do
        org = create(:organization, plan: "bronze")
        # Make sure we don't grant read access to repositories by default
        org.update_default_repository_permission(:none, actor: org.admins.first)
        repo = create(:private_repository, owner: org)
        create_contribution_for(@user, repository: repo)

        assert_empty subjects_for(@user),
          "Commit contributions should be ignored when user is not a member of the organization"

        org.add_member(@user)

        @user = User.find(@user.id)
        refute repo.readable_by?(@user),
          "User should not have any access to the repository"

        assert_equal 1, subjects_for(@user).size,
          "Commit contributions should be included when user is a member of the organization"
      end

      test "includes commit contributions made to repositories owned by organization the user is a member of via a team" do
        org = create(:organization)
        team = create(:team, organization: org)
        repo = create(:repository, owner: org)
        create_contribution_for(@user, repository: repo)

        assert_empty subjects_for(@user)

        team.add_member @user

        assert_equal 1, subjects_for(@user).size
      end

      test "includes commit contributions made to repositories the user has forked" do
        repo = create(:repository)
        create_contribution_for(@user, repository: repo)

        assert_empty subjects_for(@user)

        create(:fork_repository, forker: @user, fork_repo: repo)

        assert_equal 1, subjects_for(@user).size
      end

      test "includes commit contributions made to repositories the user has created an issue for" do
        repo = create(:repository)
        create_contribution_for(@user, repository: repo)

        assert_empty subjects_for(@user)

        create(:issue, user: @user, repository: repo)

        assert_equal 1, subjects_for(@user).size
      end

      test "includes commit contributions made to repositories the user has starred when feature flag is disabled" do
        disable_feature_flag(:disable_starred_repo_validation)
        repo = create(:repository)
        create_contribution_for(@user, repository: repo)

        assert_empty subjects_for(@user)

        @user.star(repo)

        assert_equal 1, subjects_for(@user).size
      end

      test "does not include commit contributions made to repositories the user has starred when feature flag is enabled" do
        enable_feature_flag(:disable_starred_repo_validation)
        repo = create(:repository)
        create_contribution_for(@user, repository: repo)

        assert_empty subjects_for(@user)

        @user.star(repo)

        assert_empty subjects_for(@user)
      end

      test "excludes commit contributions made to orphan repositories" do
        repo = create(:repository, owner: @user)
        create_contribution_for(@user, repository: repo)

        assert_equal 1, subjects_for(@user).size

        repo.delete

        assert_empty subjects_for(@user)
      end
    end

    test "eager loads repositories" do
      repo = create(:repository, owner: @user)
      create_contribution_for(@user, repository: repo)
      contribution = subjects_for(@user).first

      assert contribution.association(:repository).loaded?
    end

    test "eager loads repositories for large-scale contributors" do
      repo = create(:repository, owner: @user)
      create_contribution_for(@user, repository: repo)

      @user.flag_as_large_scale_contributor!
      contribution = subjects_for(@user).first

      assert contribution.association(:repository).loaded?
    end

    # https://github.com/github/github/issues/37698
    test "counts commits when a date is specified but no issues or PRs were opened on that date" do
      date = Date.today
      user = create(:user, email: "rtomayko@gmail.com")
      repo = create(:repository, owner: user, from_example: :review_comment_source)

      commit_contribution = create(:commit_contribution, :with_summaries, user: user, repository: repo, committed_date: date)

      create(:issue, repository: repo, user: user, created_at: 10.days.ago)

      contributions = subjects_for(user, date_range: date..date)
      assert_same_contributions [commit_contribution], contributions
    end
  end
end
