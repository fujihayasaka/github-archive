# typed: true
# frozen_string_literal: true

require "test_helper"

class ContributionCreatedRepositoryTest < GitHub::TestCase
  fixtures do
    @user = create :user, plan: "medium"
  end

  setup do
    reset_cache
  end

  context "#eql?" do
    test "is not equal to a restricted contribution" do
      contribution = Contribution::CreatedRepository.new(user: @user, subject: nil)

      refute_equal Contribution::RestrictedContribution.new(contribution), contribution
    end
  end

  context "#organization_id" do
    test "returns the organization ID of the repository" do
      org_id = 123
      repo = stub(organization_id: org_id)
      contribution = Contribution::CreatedRepository.new(user: @user, subject: repo)
      assert_equal org_id, contribution.organization_id
    end
  end

  context "#description" do
    test "returns the repository description" do
      repo = create(:repository, owner: @user, description: "Frank's Beans")
      contribution = Contribution::CreatedRepository.new(
        user: @user,
        subject: repo,
      )

      assert_equal "Frank's Beans", contribution.description
    end
  end

  context "#occurred_at" do
    test "returns the repository created_at" do
      repo = create(:repository, owner: @user)
      contribution = Contribution::CreatedRepository.new(
        user: @user,
        subject: repo,
      )

      assert_equal repo.created_at, contribution.occurred_at
    end
  end

  context "#primary_language" do
    test "returns the primary language for the repository" do
      repo = create(:repository, owner: @user)
      contribution = Contribution::CreatedRepository.new(
        user: @user,
        subject: repo,
      )
      repo.update_attribute(:primary_language_name, "ruby")
      contribution.repository.reload

      assert_equal "ruby", contribution.primary_language
    end
  end

  context "#contributors" do
    test "returns an empty array if the only contributor is the owner" do
      repo = create(:repository, owner: @user)
      create(:commit_contribution, repository: repo, user: @user)
      contribution = Contribution::CreatedRepository.new(
        user: @user,
        subject: repo,
      )

      assert_empty contribution.contributors(viewer: nil)
    end

    test "returns an array of contributing users" do
      repo = create(:repository, owner: @user)

      # Ghost user with the most contributions, which should be hidden
      User.create_ghost
      cc10 = create(:commit_contribution, repository: repo, commit_count: 10,
                                     user: User.ghost)

      # Users with single large contributions:
      cc5 = create(:commit_contribution, repository: repo, commit_count: 5)
      cc2 = create(:commit_contribution, repository: repo, commit_count: 2)
      cc8 = create(:commit_contribution, repository: repo, commit_count: 8)
      cc4 = create(:commit_contribution, repository: repo, commit_count: 4)

      # Not a top contributor:
      create(:commit_contribution, repository: repo, commit_count: 1)

      # One user with multiple contributions
      user_with_3 = create(:user)
      create(:commit_contribution, repository: repo, commit_count: 1,
                              user: user_with_3,
                              committed_date: Date.yesterday)
      create(:commit_contribution, repository: repo, commit_count: 1,
                              user: user_with_3,
                              committed_date: 4.days.ago)
      create(:commit_contribution, repository: repo, commit_count: 1,
                              user: user_with_3,
                              committed_date: 8.days.ago)

      contribution = Contribution::CreatedRepository.new(
        user: @user, subject: repo,
      )
      expected = [cc8.user, cc5.user, cc4.user, user_with_3, cc2.user]
      assert_equal expected, contribution.contributors(viewer: nil),
          "Only top 5 contributors should be returned"
    end
  end

  context "#associated_subject" do
    test "returns the repository" do
      repo = create(:repository, owner: @user)
      contribution = Contribution::CreatedRepository.new(
        user: @user,
        subject: repo,
      )

      assert_equal repo, contribution.associated_subject
    end
  end

  context "#repository" do
    test "returns the repository" do
      repo = create(:repository, owner: @user)
      contribution = Contribution::CreatedRepository.new(
        user: @user,
        subject: repo,
      )

      assert_equal repo, contribution.repository
    end
  end

  context "#repository_id" do
    test "returns the id of the repository" do
      repo = create(:repository, owner: @user)
      contribution = Contribution::CreatedRepository.new(
        user: @user,
        subject: repo,
      )
      assert_equal repo.id, contribution.repository_id
    end
  end

  context "#name" do
    test "returns the repository name" do
      repo = create(:repository, owner: @user)
      contribution = Contribution::CreatedRepository.new(
        user: @user,
        subject: repo,
      )

      assert_equal repo.name, contribution.name
    end
  end

  def subjects_for(user, date_range: Date.yesterday..Date.tomorrow, organization_id: nil)
    Contribution::CreatedRepository.subjects_for(user, date_range: date_range, organization_id: organization_id)
  end

  context "::subjects_for" do
    test "includes the user's public and private repositories" do
      private_repo = create :private_repository, owner: @user
      public_repo = create :repository, owner: @user

      subjects = subjects_for(@user)
      subjects.each do |subject|
        assert_kind_of Repository, subject
      end

      assert_same_elements [public_repo, private_repo], subjects
    end

    test "only returns repositories created by the given user" do
      create(:repository)

      assert_empty subjects_for(@user)
    end

    test "only returns repositories created in the given time range" do
      create(:repository, owner: @user, created_at: 3.days.ago)
      create(:repository, owner: @user, created_at: 2.days.since)

      assert_empty subjects_for(@user, date_range: 2.days.ago.to_date..Date.yesterday)
    end

    # https://github.com/github/profile/issues/214
    test "returns repositories sorted by most recent first" do
      first_repo = create(:repository, owner: @user, name: "blueberry", created_at: 2.days.ago)
      second_repo = create(:repository, owner: @user, name: "cantaloupe", created_at: 4.days.ago)
      third_repo = create(:repository, owner: @user, name: "dragonfruit", created_at: 6.days.ago)
      fourth_repo = create(:repository, owner: @user, name: "apple", created_at: 8.days.ago)

      Contribution::CreatedRepository.stub_const(:REPO_LIMIT, 2) do
        subjects = subjects_for(@user, date_range: 10.days.ago.to_date..Date.today)

        assert_equal first_repo, subjects.first
        assert_equal second_repo, subjects.second
        assert_equal third_repo, subjects.last
      end
    end

    test "includes forked repositories" do
      source_repo = create(:repository)
      fork = create(:fork_repository, forker: @user, fork_repo: source_repo)

      assert_equal [fork], subjects_for(@user)
    end

    test "returns empty array if filtering by organization" do
      create(:repository, owner: @user, created_at: Date.yesterday)

      assert_empty subjects_for(@user, organization_id: 123)
    end

    # https://github.com/github/github/issues/71686
    test "limits the number of repositories returned" do
      4.times do
        create :repository, owner: @user,
          created_at: DateTime.new(2014, 8, 4)
      end

      Contribution::CreatedRepository.stub_const(:REPO_LIMIT, 2) do
        subjects = subjects_for(@user, date_range: Date.new(2014, 8, 1)..Date.new(2014, 8, 31))

        assert_equal 3, subjects.size
      end
    end
  end

  context "::first_subject_for" do
    test "returns the repository with the lowest ID" do
      repo = create(:repository, owner: @user)
      # Create a repo with an older created_at but a higher ID
      Timecop.freeze(repo.created_at.yesterday) do
        create(:repository, owner: @user)
      end

      assert_equal repo, Contribution::CreatedRepository.
          first_subject_for(@user)
    end

    test "only returns a repository created by the specified user" do
      assert_nil Contribution::CreatedRepository.
          first_subject_for(create(:user))
    end

    test "excludes forked repositories" do
      source_repo = create(:repository)
      user = create(:user)
      create(:fork_repository, forker: user, fork_repo: source_repo)

      assert_nil Contribution::CreatedRepository.
          first_subject_for(@user)
    end
  end
end
