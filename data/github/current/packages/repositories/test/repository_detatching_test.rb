# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositoryDetatchingTest < GitHub::TestCase
  fixtures do
    @org      = create(:organization)
    @org.allow_private_repository_forking(actor: @org.admins.first)

    @user     = create :user, plan: "medium"
    @org.add_member @user, action: :admin
    @forker   = create :user, plan: "medium"
    @org.add_admin(@forker)
    @repo     = create :private_repository, owner: @org, description: "boom"
    @fork = create(:fork_repository, forker: @forker, fork_repo: @repo)

    assert_equal @org, @fork.organization
    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @fork.detach! }
  end

  test "properly sets the plan owner" do
    assert_equal @fork.owner, @fork.plan_owner
  end

  test "properly sets the organization" do
    assert_nil @fork.organization
  end

  test "removes abilities for admins of old plan owner" do
    refute_able @user, :admin, @fork
  end
end
