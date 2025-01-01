# typed: true
# frozen_string_literal: true

require "test_helper"

class ContributionCreatedPullRequestTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @user = create :user, plan: "medium", login: "tesla"
    @repo = create :repository, owner: @user, from_example: :pull_request_fork


    @pull = make_pull_request(user: @user, repo: @repo, head_ref: "ahead")
  end

  def make_pull_request(options)
    repo = options.delete(:repo)
    user = options.fetch(:user)
    issue = options.fetch(:issue, create(:issue, repository: repo, user: user))
    create(:pull_request, options.reverse_merge(
      repository: repo,
      base_repository: repo,
      base_user: user,
      base_ref: "master",
      head_repository: repo,
      head_user: user,
      issue: issue,
    ))
  end

  setup do
    @contribution = Contribution::CreatedPullRequest.new(
      user: @user,
      subject: @pull,
    )
  end

  context "#organization_id" do
    test "returns the organization ID of the repository of the pull request" do
      org = create(:organization, admin: @user)
      repo = create(:repository, owner: org, from_example: :simple)
      ref = repo.heads.create("topic", repo.heads.find("master").target, repo.owner)
      commit = ref.append_commit({ message: "Add file1", committer: repo.owner }, @repo.owner) do |files|
        files.add("file1.txt", "line1\nline2\nline3\n")
      end

      pull = PullRequest.create_for!(
        repo,
        user: @user,
        base: "master",
        head: "topic",
        title: "hello world"
      )

      contribution = Contribution::CreatedPullRequest.new(user: @user, subject: pull)
      assert_equal repo.organization_id, contribution.organization_id
    end
  end

  context "#occurred_at" do
    test "returns the pull request's contribution_time" do
      assert_equal @pull.contribution_time, @contribution.occurred_at
    end
  end

  context "#repository" do
    test "returns the associated repository" do
      assert_equal @repo, @contribution.repository
    end
  end

  context "#number" do
    test "returns the pull request number" do
      assert_equal @pull.number, @contribution.number
    end
  end

  context "#associated_subject" do
    test "returns the repository of the pull request" do
      assert_equal @pull.repository, @contribution.associated_subject
    end
  end

  context "#pull_request" do
    test "returns the pull request" do
      assert_equal @pull, @contribution.pull_request
    end
  end

  context "#repository_id" do
    test "returns the id of the pull request's repository" do
      assert_equal @pull.repository_id, @contribution.repository_id
    end
  end

  def subjects_for(
    user,
    date_range: Date.yesterday..Date.tomorrow,
    organization_id: nil,
    excluded_organization_ids: []
  )
    Contribution::CreatedPullRequest.subjects_for(
      user, date_range: date_range, organization_id: organization_id,
      excluded_organization_ids: excluded_organization_ids
    )
  end

  context "::subjects_for" do
    test "includes the user's pull requests" do
      private_repo = create :private_repository, owner: @user, from_example: :encodings
      private_pull = create(:pull_request,
        repository: private_repo,
        base_ref: "empty-branch",
        head_ref: "master",
        user: @user,
      )

      subjects = subjects_for(@user)
      subjects.each do |subject|
        assert_kind_of PullRequest, subject
      end
      assert_same_elements [private_pull, @pull], subjects
    end

    test "allows filtering pull requests by organization_id" do
      org_a, org_b = create_pair(:organization, public_members: [@user]).each do |org|
        repo = create :private_repository, owner: org, from_example: :encodings
        create(:pull_request, repository: repo, base_ref: "empty-branch", head_ref: "master", user: @user)
      end

      subjects = subjects_for(@user, organization_id: org_a.id)

      assert_same_elements org_a.repositories.first.pull_requests, subjects
    end

    test "excludes contributions in orgs specified by excluded_organization_ids" do
      excluded_org, other_org = create_pair(:organization, public_members: [@user]) do |org|
        repo = create :private_repository, owner: org, from_example: :encodings
        create(:pull_request, repository: repo, base_ref: "empty-branch", head_ref: "master", user: @user)
      end

      subjects = subjects_for(@user, excluded_organization_ids: [excluded_org.id])

      assert_same_elements \
        [@pull, other_org.repositories.first.pull_requests.first],
        subjects
    end

    test "only returns pull requests created in the given time range with buffer" do
      travel_to Time.zone.local(2001, 9, 4, 00, 00, 00) do
        make_pull_request(user: @user, repo: @repo, head_ref: "master-plus-one-commit")

        assert_empty subjects_for(@user, date_range: 3.days.ago...2.days.ago.to_date)
      end
    end

    test "only returns pull requests created by the specified user" do
      assert_empty subjects_for(create(:user))
    end

    test "limits the number of pull requests to avoid perfomance bottlenecks" do
      refute_empty subjects_for(@user)

      Contribution.stub_const(:DEFAULT_COUNT_LIMIT, 0) do
        assert_empty subjects_for(@user)
      end
    end

    test "returns events where contributed_at_timestamp is `nil`" do
      user = create(:user)
      repo = create(:repository, owner: user, from_example: :rebase_pull_request)
      pull = make_pull_request(user: user, repo: repo, head_ref: "contrib")

      pull.update contributed_at_timestamp: nil, contributed_at_offset: nil
      assert_nil pull.reload.contributed_at

      subjects = subjects_for(user)
      assert_equal [pull], subjects
    end
  end

  context "::first_subject_for" do
    test "returns the first pull request" do
      create(:pull_request, :disable_disk_access, user: @user)

      assert_equal @pull, Contribution::CreatedPullRequest.first_subject_for(@user)
    end

    test "ignores pull requests that were not created by the given user" do
      assert_nil Contribution::CreatedPullRequest.first_subject_for(create(:user))
    end

    test "returns the first private pull request" do
      @pull.repository.update!(private: true)
      create(:pull_request, :disable_disk_access, user: @user)

      assert_equal @pull, Contribution::CreatedPullRequest.first_subject_for(@user)
    end

    test "returns the first pull request excluding pull requests in orgs specified by excluded_organization_ids" do
      user = create :user

      excluded_org = create :organization, admin: user
      excluded_org_repo = create :private_repository, owner: excluded_org, from_example: :simple
      excluded_pull = Timecop.freeze(@pull.created_at.yesterday) do
        create :pull_request, repository: excluded_org_repo, head_ref: "cr-line-endings", user: user
      end

      other_org = create :organization, admin: user
      other_org_repo = create :private_repository, owner: other_org, from_example: :simple
      other_pull = Timecop.freeze(@pull.created_at.yesterday) do
        create :pull_request, repository: other_org_repo, head_ref: "cr-line-endings", user: user
      end

      assert_equal \
        other_pull,
        Contribution::CreatedPullRequest.first_subject_for(
          user, excluded_organization_ids: [excluded_org.id]
        )
    end

    test "doesn't return orphaned pull requests" do
      assert_equal @pull, Contribution::CreatedPullRequest.first_subject_for(@user)

      @pull.repository.delete
      refute_nil @pull.reload.repository_id
      assert_nil @pull.repository

      assert_nil Contribution::CreatedPullRequest.first_subject_for(@user)
    end

    test "doesn't return pull requests of deleted repositories" do
      assert_equal @pull, Contribution::CreatedPullRequest.first_subject_for(@user)

      @pull.repository.update(active: nil)

      assert_nil Contribution::CreatedPullRequest.first_subject_for(@user)
    end

    test "emits a distribution timing metric" do
      Contribution::CreatedPullRequest.first_subject_for(@user)
      assert_dogstats_distribution(1, "contributions.queries.dist.time")
    end
  end
end
