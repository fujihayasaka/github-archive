# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryInternalNetworkTest < GitHub::TestCase
  include RepositoriesTestHelper

  fixtures do
    @org = create(:enterprise_linked_organization)
    @admin = @org.admin
    @org.allow_private_repository_forking(actor: @admin, policy: Configurable::AllowPrivateRepositoryForking::EVERYWHERE)
    @org.business.allow_private_repository_forking(actor: @admin, policy: Configurable::AllowPrivateRepositoryForking::EVERYWHERE)

    @internal_root = create(:internal_repository, owner: @org, from_example: :simple)
    @internal_fork = create(:fork_repository, fork_repo: @internal_root, forker: @internal_root.owner.admins.first, owner: @org)
    @another_biz_org = create(:organization, business: @internal_root.owner.business)
    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  test "can_attach_to? is true when joining a private fork to an internal root" do
    @internal_fork.extract!(synchronous: true)

    allowed, reason = @internal_fork.can_attach_to?(@internal_root)
    assert_equal :valid, reason
    assert allowed
  end

  test "can_attach_to? is false when joining an internal fork to an internal root" do
    @internal_fork.extract!(synchronous: true)
    success = @internal_fork.transfer_ownership_to(@another_biz_org, actor: @internal_fork.owner)
    assert success
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @internal_fork.set_visibility(actor: @internal_fork.owner, visibility: "internal") }

    allowed, reason = @internal_fork.reload.can_attach_to?(@internal_root)
    assert_equal :visibility, reason
    refute allowed
    assert_predicate @internal_fork, :internal?
  end

  test "can_attach_to? is false when joining a public fork to an internal root" do
    @internal_fork.extract!(synchronous: true)
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @internal_fork.set_visibility(actor: @internal_fork.owner, visibility: "public") }
    allowed, reason = @internal_fork.reload.can_attach_to?(@internal_root)
    assert_equal :visibility, reason
    refute allowed
    assert_predicate @internal_fork, :public?
  end
end
