# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryBillingDependencyTest < GitHub::TestCase
  fixtures do
    @admin    = create(:user, login: "d12")
    @admin_2  = create(:user, login: "iolsen")
    @defunkt  = create(:user, login: "defunkt",  plan: "medium")
    @member   = create(:user, login: "member")
    @org = create(:organization, business: create(:business))
    @org.add_admin(@admin)
    @org.add_admin(@admin_2)
    @org.add_member(@member, action: :read)

    @ambition = create(:private_repository, name: "ambition", owner: @defunkt)
    @simple   = create(:repository, name: "simple",   owner: @defunkt)
  end

  context "#can_privatize?" do
    test "returns true if private repository" do
      assert @ambition.can_privatize?
    end

    test "returns true if the owner of a per seat plan has available collaborator seats" do
      assert @simple.can_privatize?
    end

    test "returns false if the owner of a per seat plan does not have anymore collaborator seats" do
      @defunkt.update(plan: "business")
      @simple.stubs(:owner_has_seats_for_collaborators?).returns(false)

      refute @simple.can_privatize?
    end

    test "returns true if the owner of a non per seat plan has available private repos and has available collaborator seats" do
      @simple.owner.stubs(:at_private_repo_limit?).returns(false)
      @simple.stubs(:over_collaborator_limit_for_private_repos?).returns(false)

      assert @simple.can_privatize?
    end

    test "returns false if the owner of a non per seat plan does not have any available private repos" do
      @simple.owner.stubs(:at_private_repo_limit?).returns(true)

      refute @simple.can_privatize?
    end

    test "returns false if the owner of non per set plan has available private repos but no collaborator seats" do
      @simple.owner.stubs(:at_private_repo_limit?).returns(true)
      @simple.stubs(:over_collaborator_limit_for_private_repos?).returns(true)

      refute @simple.can_privatize?
    end
  end

  context "#over_collaborator_limit_for_private_repos?" do
    test "returns false if the owner of a public repo has enough seats to cover collaborators when made private" do
      @defunkt.update(plan: "free")

      refute @simple.over_collaborator_limit_for_private_repos?
    end

    test "returns false if the owner of a public repo is at the collaborator seat limit allowed to make a repo private" do
      @defunkt.update(plan: "free")

      @simple.stubs(:filled_seats).returns(3) # the maximum # of allowed collaborators to make a repo private is 3
      refute @simple.over_collaborator_limit_for_private_repos?
    end
  end
end
