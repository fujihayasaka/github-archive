# typed: true
# frozen_string_literal: true

require "test_helper"

class StatusesDomainTest < GitHub::TestCase

  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user, from_example: :simple)
    @commit = create(:commit, repository: @repo).freeze
  end

  setup do
    @domain = Statuses.domain
  end

  teardown do
    GitHub::CurrentTenant.remove
  end

  sig { returns(Statuses::Domain) }
  def domain
    T.must(@domain)
  end

  context "#repository_has_statuses?" do
    test "true" do
      status = create(:status, repository: @repo)
      assert domain.repository_has_statuses?(repository_id: @repo.id)
    end

    test "false" do
      repo = create(:repository, owner: @user)
      refute domain.repository_has_statuses?(repository_id: repo.id)
    end

    test "returns false for nil repository_id" do
      refute domain.repository_has_statuses?(repository_id: nil)
    end
  end

  context "#current_statuses_for_shas" do
    test "returns the current statuses for the given shas" do
      status1 = create(:status, repository: @repo)

      assert_query_count(1) do
        statuses = domain.current_statuses_for_shas(repository_id: @repo.id, shas: [status1.sha])

        assert_equal [status1], statuses
      end
    end

    test "if there are multiple statuses per context, returns the current ones" do
      statuses = Set.new

      status1 = create(:status, state: "success", repository: @repo, context: "context 1")
      sha = status1.sha
      statuses << create(:status, sha: sha, state: "failure", repository: @repo, context: "context 1")

      create(:status, sha: sha, state: "pending", repository: @repo, context: "context 2")
      statuses << create(:status, sha: sha, state: "success", repository: @repo, context: "context 2")

      # When given no context it is treated as its own context.
      # This is so legacy contextless use works just like it used to.
      create(:status, sha: sha, state: "failure", creator: @user, repository: @repo)
      statuses << create(:status, sha: sha, state: "success", creator: @user, repository: @repo)

      assert_empty statuses.difference(domain.current_statuses_for_shas(repository_id: @repo.id, shas: [sha]))
    end
  end

  context "#current_statuses_for_shas_group_by_sha" do
    test "most recently created status is returned" do
      status1 = create(:status, repository: @repo)
      status2 = create(:status, repository: @repo, created_at: 1.day.from_now)

      statuses = domain.current_statuses_for_shas_group_by_sha(repository_id: @repo.id, shas: [status1.sha])
      assert_equal 1, statuses.size
      assert_equal [status2], statuses[status1.sha]
    end

    test "most recently created status for context is returned " do
      status1 = create(:status, repository: @repo, context: "context1")
      status2 = create(:status, repository: @repo, context: "context1", created_at: 1.day.from_now)

      statuses = domain.current_statuses_for_shas_group_by_sha(repository_id: @repo.id, shas: [status1.sha])
      assert_equal 1, statuses.size
      assert_equal [status2], statuses[status1.sha]
    end
  end

  context "#create" do
    test "successfully creates status" do
      result = domain.create(
        repository: @repo,
        sha: @commit.sha,
        state: "success",
        user: @user,
        context: "test/context",
        target_url: "https://example.com",
        description: "Test description"
      )

      assert result.ok?
      if result.is_a?(GH::Result::Ok)
        assert_equal @repo, result.value.repository
        assert_equal @commit.sha, result.value.sha
        assert_equal "success", result.value.state
        assert_equal @user, result.value.creator
        assert_equal "test/context", result.value.context
        assert_equal "https://example.com", result.value.target_url
        assert_equal "Test description", result.value.description
      end
    end

    test "successfully creates status with oauth application" do
      oauth_application = create(:oauth_application)

      result = domain.create(
        repository: @repo,
        sha: @commit.sha,
        state: "success",
        user: @user,
        context: "test/context",
        target_url: "https://example.com",
        description: "Test description",
        oauth_application_id: oauth_application.id
      )

      assert result.ok?
    end

    test "fails to create status with invalid data" do
      # Wrong SHA for the repository
      result = domain.create(
        repository: @repo,
        sha: "abc",
        state: "success",
        user: @user,
        context: " ",
      )

      assert !result.ok?
      assert result.is_a?(GH::Result::Error)
      if result.is_a?(GH::Result::Error)
        assert_equal "Validation failed: Sha must be a valid hex object ID, Context can't be blank", result.message
      end
    end
  end

  context "#statuses_created_before_timestamp" do
    test "returns the statuses for the given sha that were created before the given timestamp" do
      status1 = create(:status, repository: @repo)
      status2 = create(:status, repository: @repo, created_at: 1.day.ago)

      assert_query_count(1) do
        statuses = domain.statuses_created_before_timestamp(repository_id: @repo.id, sha: status1.sha, timestamp: Time.now)

        assert_equal [status2], statuses
      end
    end

    test "returns an empty array if repository_id is nil" do
      status = create(:status, repository: @repo)

      assert_query_count(0) do
        statuses = domain.statuses_created_before_timestamp(repository_id: nil, sha: status.sha, timestamp: 1.day.ago)

        assert_empty statuses
      end
    end
  end
end
