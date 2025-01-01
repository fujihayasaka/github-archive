# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryPublicNetworkTest < GitHub::TestCase
  include RepositoriesTestHelper
  fixtures do
    @root = create(:repository, from_example: :simple)

    @child1 = create(:fork_repository, fork_repo: @root, forker: create(:user))
    @child2 = create(:fork_repository, fork_repo: @root, forker: create(:user))
    @child3 = create(:fork_repository, fork_repo: @root, forker: create(:user))

    @grandchild1_1 = create(:fork_repository, fork_repo: @child1, forker: create(:user))
    @grandchild1_2 = create(:fork_repository, fork_repo: @child1, forker: create(:user))
    @grandchild1_3 = create(:fork_repository, fork_repo: @child1, forker: create(:user))

    @grandchild2_1 = create(:fork_repository, fork_repo: @child2, forker: create(:user))
    @grandchild2_2 = create(:fork_repository, fork_repo: @child2, forker: create(:user))
    @grandchild2_3 = create(:fork_repository, fork_repo: @child2, forker: create(:user))

    @grandchild3_1 = create(:fork_repository, fork_repo: @child3, forker: create(:user))
    @grandchild3_2 = create(:fork_repository, fork_repo: @child3, forker: create(:user))
    @grandchild3_3 = create(:fork_repository, fork_repo: @child3, forker: create(:user))

    @unrelated_repo = create(:repository)
    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  test "root_network returns self for root network" do
    assert_equal @root.source_id, @grandchild3_3.network.root_network.id
  end

  test "root_network returns root for nested networks" do
    create(:fork_repository, fork_repo: @child1, forker: create(:user))
    create(:fork_repository, fork_repo: @child2, forker: create(:user))
    create(:fork_repository, fork_repo: @child3, forker: create(:user))

    create(:fork_repository, fork_repo: @grandchild1_1, forker: create(:user))
    create(:fork_repository, fork_repo: @grandchild2_1, forker: create(:user))
    create(:fork_repository, fork_repo: @grandchild3_1, forker: create(:user))

    assert_equal @root.source_id, @child1.network.root_network.id
    assert_equal @root.source_id, @child2.network.root_network.id
    assert_equal @root.source_id, @child3.network.root_network.id
    assert_equal @root.source_id, @grandchild1_1.network.root_network.id
    assert_equal @root.source_id, @grandchild2_1.network.root_network.id
    assert_equal @root.source_id, @grandchild3_1.network.root_network.id
  end

  def detach_all(repos)
    network_ids = []
    repos.each do |repo|
      prev_network = repo.network
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { repo.detach! if repo.reload.parent }
      network_ids << repo.reload.network_id
    end
    network_ids
  end

  test "family_ids, family_networks, family_root_repositories, and can_attach_to? work as expected when all are detached" do
    assert_equal [@root.network_id], @root.network.family_ids


    all_related_repos = @root.network.repositories.order(id: :desc)
    new_network_ids = detach_all(all_related_repos)
    assert_same_elements new_network_ids, @root.reload.network.family_ids
    assert_same_elements new_network_ids, RepositoryNetwork.family_networks(@root.network).pluck(:id)

    allowed, reason = @grandchild3_3.reload.can_attach_to? @grandchild1_1.reload
    assert allowed
    assert_equal :valid, reason

    allowed, reason = @unrelated_repo.can_attach_to? @root.reload
    refute allowed
    assert_equal :unrelated, reason

    assert_same_elements all_related_repos, RepositoryNetwork.family_root_repositories(@root.network)
  end

  test "family_ids, family_root_repositories, and can_attach_to? work as expected when one per generation are detached" do
    assert_equal [@root.network_id], @root.network.family_ids

    expected_network_family_ids = [@root.network_id]
    [@grandchild3_3, @child2].each do |repo|
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { repo.detach! }
      expected_network_family_ids << repo.reload.network_id
    end
    assert_same_elements expected_network_family_ids, @root.reload.network.family_ids
    assert_same_elements expected_network_family_ids, RepositoryNetwork.family_networks(@root.network).pluck(:id)

    allowed, reason = @grandchild3_3.reload.can_attach_to? @child2.reload
    assert allowed
    assert_equal :valid, reason

    allowed, reason = @grandchild3_3.can_attach_to? @grandchild1_1.reload
    assert allowed
    assert_equal :valid, reason

    allowed, reason = @unrelated_repo.can_attach_to? @grandchild3_3
    refute allowed
    assert_equal :unrelated, reason

    allowed, reason = @unrelated_repo.can_attach_to? @child2
    refute allowed
    assert_equal :unrelated, reason

    allowed, reason = @unrelated_repo.can_attach_to? @root.reload
    refute allowed
    assert_equal :unrelated, reason

    assert_same_elements [@root, @child2, @grandchild3_3], RepositoryNetwork.family_root_repositories(@root.network)
  end

  test "family_ids, family_root_repositories, and can_attach_to? work as expected when just one in the middle of the graph is detached" do
    assert_equal [@root.network_id], @root.network.family_ids

    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @child2.detach! }
    expected_network_family_ids = [@root.network_id, @child2.reload.network_id]
    assert_same_elements expected_network_family_ids, @root.reload.network.family_ids
    assert_same_elements expected_network_family_ids, RepositoryNetwork.family_networks(@root.network).pluck(:id)

    allowed, reason = @grandchild3_3.reload.can_attach_to? @child2.reload
    assert allowed
    assert_equal :valid, reason

    allowed, reason = @unrelated_repo.can_attach_to? @child2
    refute allowed
    assert_equal :unrelated, reason

    assert_same_elements [@root, @child2], RepositoryNetwork.family_root_repositories(@root.network)
  end

  test "can_attach_to? is false for repos in the same network" do
    allowed, reason = @grandchild3_3.can_attach_to?(@root)
    refute allowed
    assert_equal :same_network, reason

    allowed, reason = @child2.can_attach_to?(@grandchild1_1)
    refute allowed
    assert_equal :same_network, reason
  end

  test "arbitrary networks within a family can be attached" do
    assert_equal [@root.network_id], @root.network.family_ids

    all_related_repos = @root.network.repositories.order(id: :desc)
    network_ids = detach_all(all_related_repos)
    destroyed_network_ids = []

    destroyed_network_ids << @root.reload.source_id
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @root.attach_to!(@grandchild3_3.reload) }
    assert_equal @root.reload.source_id, @grandchild3_3.reload.source_id
    assert_equal @root.parent_id, @grandchild3_3.id

    destroyed_network_ids << @child1.reload.source_id
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @child1.attach_to!(@child3.reload) }
    assert_equal @child1.reload.source_id, @child3.reload.source_id
    assert_equal @child1.parent_id, @child3.id

    destroyed_network_ids << @child2.reload.source_id
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @child2.attach_to!(@grandchild2_2.reload) }
    assert_equal @child2.reload.source_id, @grandchild2_2.reload.source_id
    assert_equal @child2.parent_id, @grandchild2_2.id

    destroyed_network_ids << @child3.reload.source_id
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @child3.attach_to!(@grandchild2_2.reload) }
    assert_equal @child3.reload.source_id, @grandchild2_2.reload.source_id
    assert_equal @child3.parent_id, @grandchild2_2.id

    expected_network_family_ids = network_ids - destroyed_network_ids
    assert_same_elements expected_network_family_ids, @root.network.family_ids
  end

  test "#root_network fails fast on circular reference" do
    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @child1.detach! }
    @child1.reload
    @child1.network.update_attribute(:owner_id, @child1.network.id)
    assert_raises { @child1.reload.network.root_network }
  end

  test "#family_ids fails fast on circular reference" do
    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @child1.detach! }
    @child1.reload
    @child1.network.update_attribute(:owner_id, @child1.network.id)
    assert_raises { @child1.reload.network.family_ids }
  end

  test "#family_network_trees does not include empty networks" do
    root = create(:repository)
    create(:fork_repository, fork_repo: root, forker: create(:user))

    empty_network = create(:repository_network)
    empty_network.update_columns(owner_id: root.network.id)
    result = root.network.reload.family_network_trees

    # assert that empty network is part of the family
    assert_equal [root.network.id, empty_network.id], root.network.family_ids
    repo_map = root.network.full_network_tree
    assert_equal [[root, repo_map]], result
  end
end
