# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestAccessorTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @pull = create(:pull_request, :disable_disk_access)
    @push = create(:push, repository: @pull.repository)
  end

  def setup
    @accessor = PullRequests::PullRequestAccessor.new
  end

  context "#by_number" do
    test "finds pull by number" do
      pull = @accessor.by_number(repository_id: @pull.repository_id, number: @pull.number)

      assert_equal(pull.id, @pull.id)
    end

    test "raises GH::Errors::ObjectNotFound if there is no matching pull for the given repo and number" do
      err = assert_raises(GH::Errors::ObjectNotFound) { @accessor.by_number(repository_id: 0, number: 123) }
      assert_instance_of GH::Errors::ObjectNotFound, err
      assert_equal PullRequests::IPullRequest, err.expected_type
    end
  end

  context "#by_merge_commit" do
    test "returns a pull request by a given merge commit" do
      repository_id = SecureRandom.random_number(1..1_000_000)
      base_branch_name = SecureRandom.uuid
      oid = SecureRandom.hex(20)

      Elastomer::Indexes::PullRequests.any_instance.
        expects(:id_by_merge_commit).with(
          repository_id: repository_id,
          base_branch_name: base_branch_name,
          oid: oid,
        ).returns([:found, @pull.id])

      pull =
        @accessor.by_merge_commit(
          repository_id: repository_id,
          base_branch_name: base_branch_name,
          oid: oid,
        )

      assert_equal @pull, pull
    end

    test "returns a single pull request by a given merge push when multiple exist" do
      repository_id = SecureRandom.random_number(1..1_000_000)
      base_branch_name = SecureRandom.uuid
      oid = SecureRandom.hex(20)

      Elastomer::Indexes::PullRequests.any_instance.
        expects(:id_by_merge_commit).with(
          repository_id: repository_id,
          base_branch_name: base_branch_name,
          oid: oid,
        ).returns([:multiple_found, @pull.id])

      pull =
        @accessor.by_merge_commit(
          repository_id: repository_id,
          base_branch_name: base_branch_name,
          oid: oid,
        )

      assert_equal @pull, pull
    end

    test "returns nil when no pull request was merged by the given push" do
      repository_id = SecureRandom.random_number(1..1_000_000)
      base_branch_name = SecureRandom.uuid
      oid = SecureRandom.hex(20)

      Elastomer::Indexes::PullRequests.any_instance.
        expects(:id_by_merge_commit).with(
          repository_id: repository_id,
          base_branch_name: base_branch_name,
          oid: oid,
        ).returns([:not_found, nil])

      pull =
        @accessor.by_merge_commit(
          repository_id: repository_id,
          base_branch_name: base_branch_name,
          oid: oid,
        )

      assert_nil pull
    end

    test "raises GH::Errors::DataStoreUnavailableError if the Elasticsearch query times out" do
      repository_id = SecureRandom.random_number(1..1_000_000)
      base_branch_name = SecureRandom.uuid
      oid = SecureRandom.hex(20)

      Elastomer::Indexes::PullRequests.any_instance.
        expects(:id_by_merge_commit).with(
          repository_id: repository_id,
          base_branch_name: base_branch_name,
          oid: oid,
        ).returns([:timed_out, nil])

      assert_raises(GH::Errors::DataStoreUnavailableError) do
        @accessor.by_merge_commit(
          repository_id: repository_id,
          base_branch_name: base_branch_name,
          oid: oid,
        )
      end
    end
  end
end
