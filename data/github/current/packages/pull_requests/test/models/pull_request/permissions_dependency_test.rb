# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestPermissionsDependencyTest < GitHub::TestCase
  fixtures do
    enable_feature_flag(:merge_queue_fgp_opt_out)

    @owner = create(:user)
    @org = create(:organization, login: "org", plan: "business_plus")
    @repo_with_merge_queue = create(:repository, :has_merge_queue, owner: @org)
    @viewer = create(:user, login: "viewer")
    @contributor = create(:user, login: "contributor")
    @maintainer = create(:user, login: "maintainer")
    @org.add_member(@maintainer)
    @repo_with_merge_queue.add_member @maintainer, action: :maintain
    @repo_with_merge_queue.add_member @contributor, action: :write
    @pull = create(:pull_request, :with_mergeable_head, repository: @repo_with_merge_queue, user: @owner)
  end

  context "#async_can_add_to_merge_queue?" do
    if GitHub.merge_queues_enabled?
      test "returns true for user with repo write access" do
        assert @pull.async_can_add_to_merge_queue?(@contributor).sync
      end

      test "returns false for user with less than write access" do
        refute @pull.async_can_add_to_merge_queue?(@viewer).sync
      end
    else
      test "returns false when merge queues are disabled" do
        refute @pull.async_can_add_to_merge_queue?(@contributor).sync
        refute @pull.async_can_add_to_merge_queue?(@viewer).sync
      end
    end
  end

  context "can_add_to_merge_queue_solo?" do
    test "returns true for user with repo write access" do
      assert @pull.can_add_to_merge_queue_solo?(@contributor)
    end

    test "returns false for user with less than write access" do
      refute @pull.can_add_to_merge_queue_solo?(@viewer)
    end
  end

  context "can_jump_merge_queue?" do
    test "returns true for user with repo admin or maintainer access" do
      assert @pull.can_jump_merge_queue?(@maintainer)
    end

    test "returns false for user with less than maintainer access" do
      refute @pull.can_jump_merge_queue?(@contributor)
    end
  end
end

class PullRequestPermissionsDependencyFGPTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper

  fixtures do
    @admin = create(:user)
    @contributor = create(:user, login: "contributor")
    @enqueuer = create(:user, login: "enqueuer")
    @viewer = create(:user, login: "viewer")
  end

  setup do
    skip unless GitHub.merge_queues_enabled?
    disable_feature_flag(:merge_queue_fgp_opt_out)
  end

  test "user repository" do
    repo = create(:repository, :has_merge_queue, owner: @admin)
    pull = create(:pull_request, :with_mergeable_head, repository: repo, user: @admin)

    repo.add_member(@contributor, action: :write)
    repo.add_member(@viewer, action: :read)

    assert pull.can_add_to_merge_queue?(@admin)
    assert pull.can_add_to_merge_queue_solo?(@admin)
    assert pull.can_jump_merge_queue?(@admin)

    assert pull.can_add_to_merge_queue?(@contributor)
    assert pull.can_add_to_merge_queue_solo?(@contributor)
    refute pull.can_jump_merge_queue?(@contributor)

    refute pull.can_add_to_merge_queue?(@viewer)
    refute pull.can_add_to_merge_queue_solo?(@viewer)
    refute pull.can_jump_merge_queue?(@viewer)
  end

  test "unpaid organization repository" do
    owner = create(:organization, admin: @admin)
    repo = create(:repository, :has_merge_queue, owner:)
    pull = create(:pull_request, :with_mergeable_head, repository: repo, user: @admin)

    repo.add_member(@contributor, action: :write)
    repo.add_member(@viewer, action: :read)

    assert pull.can_add_to_merge_queue?(@admin)
    assert pull.can_jump_merge_queue?(@admin)
    assert pull.can_add_to_merge_queue_solo?(@admin)

    assert pull.can_add_to_merge_queue?(@contributor)
    refute pull.can_add_to_merge_queue_solo?(@contributor)
    refute pull.can_jump_merge_queue?(@contributor)

    refute pull.can_add_to_merge_queue?(@viewer)
    refute pull.can_add_to_merge_queue_solo?(@viewer)
    refute pull.can_jump_merge_queue?(@viewer)
  end

  test "paid organization" do
    owner = create(:business_plus_organization, admin: @admin)
    repo = create(:repository, :has_merge_queue, owner:)
    pull = create(:pull_request, :with_mergeable_head, repository: repo, user: @admin)

    repo.add_member(@contributor, action: :write)
    repo.add_member(@viewer, action: :read)

    grant_custom_role(user: @enqueuer, target: repo, base_role: :write, fgps: [
      :jump_merge_queue,
      :create_solo_merge_queue_entry
    ])

    assert pull.can_add_to_merge_queue?(@admin)
    assert pull.can_add_to_merge_queue_solo?(@admin)
    assert pull.can_jump_merge_queue?(@admin)

    assert pull.can_add_to_merge_queue?(@enqueuer)
    assert pull.can_add_to_merge_queue_solo?(@enqueuer)
    assert pull.can_jump_merge_queue?(@enqueuer)

    assert pull.can_add_to_merge_queue?(@contributor)
    refute pull.can_add_to_merge_queue_solo?(@contributor)
    refute pull.can_jump_merge_queue?(@contributor)

    refute pull.can_add_to_merge_queue?(@viewer)
    refute pull.can_add_to_merge_queue_solo?(@viewer)
    refute pull.can_jump_merge_queue?(@viewer)
  end
end
