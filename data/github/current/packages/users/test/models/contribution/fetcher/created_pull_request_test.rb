# typed: true
# frozen_string_literal: true

require "test_helper"

class ContributionFetcherCreatedPullRequestTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @user = create :user, plan: "medium", login: "tesla"

    @repo = create :repository, owner: @user, from_example: :pull_request_fork
    @pull = make_pull_request(user: @user, repo: @repo, head_ref: "ahead")

    @org = create(:organization, public_members: [@user])
    org_repo = create :repository, owner: @org, from_example: :pull_request_fork
    @org_pull = make_pull_request(user: @user, repo: org_repo, head_ref: "ahead")
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

  def fetcher_for(user:, date_range: nil, organization_id: nil, excluded_organization_ids: [])
    date_range ||= Date.yesterday..Date.tomorrow
    Contribution::Fetcher::CreatedPullRequest.new(
      user: user,
      date_range: date_range,
      organization_id: organization_id,
      excluded_organization_ids: excluded_organization_ids,
      lightweight: true
    )
  end

  context "#subjects_in_date_range" do
    test "includes the user's pull requests" do
      private_repo = create :private_repository, owner: @user, from_example: :encodings
      private_pull = create(:pull_request,
        repository: private_repo,
        base_ref: "empty-branch",
        head_ref: "master",
        user: @user,
      )

      subjects = fetcher_for(user: @user).subjects_in_date_range
      subjects.each do |subject|
        assert_kind_of PullRequest, subject
      end
      assert_same_elements [private_pull, @pull, @org_pull], subjects
    end

    test "allows filtering pull requests by organization_id" do
      create_pair(:organization, public_members: [@user]).each do |org|
        repo = create :private_repository, owner: org, from_example: :encodings
        create(:pull_request, repository: repo, base_ref: "empty-branch", head_ref: "master", user: @user)
      end

      subjects = fetcher_for(user: @user, organization_id: @org.id).subjects_in_date_range

      assert_same_elements [@org_pull], subjects
    end

    test "excludes contributions in orgs specified by excluded_organization_ids" do
      excluded_org = create(:organization, public_members: [@user])
      repo = create :private_repository, owner: excluded_org, from_example: :encodings
      create(:pull_request, repository: repo, base_ref: "empty-branch", head_ref: "master", user: @user)

      subjects = fetcher_for(user: @user, excluded_organization_ids: [excluded_org.id]).subjects_in_date_range

      assert_same_elements \
        [@pull, @org_pull],
        subjects
    end

    test "returns an empty list if the user has no PRs in non-excluded orgs" do
      user = create(:user)
      excluded_org = create(:organization, public_members: [user])
      repo = create :private_repository, owner: excluded_org, from_example: :encodings
      create(:pull_request, repository: repo, base_ref: "empty-branch", head_ref: "master", user: user)

      subjects = fetcher_for(user: user, excluded_organization_ids: [excluded_org.id]).subjects_in_date_range
      assert_empty subjects
    end

    test "only returns pull requests created in the given time range with buffer" do
      travel_to Time.zone.local(2001, 9, 4, 00, 00, 00) do
        make_pull_request(user: @user, repo: @repo, head_ref: "master-plus-one-commit")

        assert_empty fetcher_for(user: @user, date_range: 3.days.ago...2.days.ago.to_date).subjects_in_date_range
      end
    end

    test "only returns pull requests created by the specified user" do
      assert_empty fetcher_for(user: create(:user)).subjects_in_date_range
    end

    test "limits the number of pull requests to avoid perfomance bottlenecks" do
      refute_empty fetcher_for(user: @user).subjects_in_date_range

      Contribution.stub_const(:DEFAULT_COUNT_LIMIT, 0) do
        assert_empty fetcher_for(user: @user).subjects_in_date_range
      end
    end

    test "returns events where contributed_at_timestamp is `nil`" do
      user = create(:user)
      repo = create(:repository, owner: user, from_example: :rebase_pull_request)
      pull = make_pull_request(user: user, repo: repo, head_ref: "contrib")

      pull.update contributed_at_timestamp: nil, contributed_at_offset: nil
      assert_nil pull.reload.contributed_at

      subjects = fetcher_for(user: user).subjects_in_date_range
      assert_equal [pull], subjects
    end
  end

  context "#any_contribution_before?" do
    test "returns false when the subject is the first contribution" do
      newer_pull = create(:pull_request, :with_mergeable_head, repository: @repo, user: @user)

      refute fetcher_for(user: @user).any_contribution_before?(@pull)
    end

    test "returns true when the subject is not the first contribution" do
      newer_pull = create(:pull_request, :with_mergeable_head, repository: @repo, user: @user)

      assert fetcher_for(user: @user).any_contribution_before?(newer_pull)
    end

    test "doesn't scope by org" do
      org = create(:organization, public_members: [@user])
      repo = create(:private_repository, owner: org, from_example: :simple)
      org_pull = create(:pull_request, :with_mergeable_head, repository: repo, user: @user)

      fetcher = fetcher_for(user: @user, organization_id: org.id)
      assert fetcher.any_contribution_before?(org_pull)
    end
  end

  context "#first_subject" do
    test "returns the first pull request" do
      create(:pull_request, :disable_disk_access, user: @user)

      assert_equal @pull, fetcher_for(user: @user).first_subject
    end

    test "ignores pull requests that were not created by the given user" do
      assert_nil fetcher_for(user: create(:user)).first_subject
    end

    test "returns the first private pull request" do
      @pull.repository.update!(private: true)
      create(:pull_request, :disable_disk_access, user: @user)

      assert_equal @pull, fetcher_for(user: @user).first_subject
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
        fetcher_for(user: user, excluded_organization_ids: [excluded_org.id]).first_subject
    end

    test "doesn't return orphaned pull requests" do
      @org_pull.destroy
      assert_equal @pull, fetcher_for(user: @user).first_subject

      @pull.repository.delete
      refute_nil @pull.reload.repository_id
      assert_nil @pull.repository

      assert_nil fetcher_for(user: @user).first_subject
    end

    test "doesn't return pull requests of deleted repositories" do
      @org_pull.destroy
      assert_equal @pull, fetcher_for(user: @user).first_subject

      @pull.repository.update(active: nil)

      assert_nil fetcher_for(user: @user).first_subject
    end

    test "emits a distribution timing metric" do
      fetcher_for(user: @user).first_subject
      assert_dogstats_distribution(1, "contributions.queries.dist.time")
    end
  end
end
