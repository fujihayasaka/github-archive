# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryAbilitiesTest < GitHub::TestCase
  fixtures do
    @org = create(:organization, plan: "bronze")
    @org.update_default_repository_permission(:none, actor: @org.admins.first)

    @owner = create(:user, plan: GitHub::Plan.find!("medium"))
    @user = create(:user)
    @public_repo = create(:repository)
    @private_repo = create :private_repository, owner: @owner
    @team = create :team, organization: @org
  end

  context "#grant?" do
    test "allows users as actors" do
      repo = create(:repository)
      user = create(:user)
      assert repo.send(:grant?, user, :write)
    end

    test "allows organizations as actors" do
      repo = create(:repository)
      org = create(:organization)
      assert repo.send(:grant?, org, :write)
    end

    test "allows teams as actors" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      team = create(:team, organization: org)
      assert repo.send(:grant?, team, :write)
    end

    test "does not allow actors other than users, organizations, or teams" do
      unsupported_actor_type = Class.new do
        include Ability::Actor
      end

      actor = unsupported_actor_type.new
      repo = create(:repository)
      refute repo.send(:grant?, actor, :write)
    end
  end

  test "disallows read access when a public repo is destroyed" do
    @public_repo.destroy

    refute_able @user, :read, @public_repo
    refute_able @team, :read, @public_repo
  end

  test "disallows read access when a public repo is marked as deleted in the database" do
    @public_repo.remove(@owner)

    refute_able @user, :read, @public_repo
    refute_able @team, :read, @public_repo
  end

  test "disallows orgs from having permissions" do
    refute_able @org, :read, @public_repo
  end

  test "allows admin access to repositories whose owner has been unlocked by the requesting user" do
    staff = create :staff_admin_user, stafftools_roles: ["can-unlock-repos-with-owners-permission"]
    refute_able staff, :admin, @private_repo
    admin_unlock_repo(staff, @private_repo)
    assert_able staff, :admin, @private_repo
  end

  if GitHub.public_push_enabled?
    test "allows write access to public push repositories by anyone" do
      @public_repo.update_attribute(:public_push, true)
      assert_able @user, :write, @public_repo
      refute_able @user, :admin, @public_repo
    end
  else
    test "disallows write access to public push repositories by anyone" do
      @public_repo.update_attribute(:public_push, true)
      refute_able @user, :write, @public_repo
      refute_able @user, :admin, @public_repo
    end
  end

  test "user is granted write when added as a collaborator" do
    @private_repo.add_member @user
    assert_able @user, :write, @private_repo
  end

  test "user has permissions revoked when removed as a collaborator" do
    @private_repo.add_member @user
    assert_able @user, :write, @private_repo
    @private_repo.remove_member @user
    refute_able @user, :write, @private_repo
  end

  test "allows org-owned fork of private org-owned repo to be read by an owner of the source's owning organization" do
    source_org_owner = create(:user, login: "source-org-owner")
    source_org       = create(:organization, login: "source-org", admin: source_org_owner)
    fork_org_owner   = create(:user, login: "fork-org-owner")
    fork_org         = create(:organization, login: "fork-org", admin: fork_org_owner)

    source_org.allow_private_repository_forking(actor: source_org_owner)

    source = create(:private_repository, owner: source_org)
    team   = create :team, organization: source_org
    team.add_repository(source, :pull)
    team.add_member(fork_org_owner)

    fork = create(:fork_repository, forker: fork_org_owner, fork_repo: source, organization: fork_org)

    assert_able source_org_owner, :read, fork
  end

  test "allows an org member to read a private org-owned repo when the repo grants read to the org" do
    org_repo   = create(:private_repository, owner: @org)
    org_member = create(:user, login: "org-member")
    @org.add_member(org_member)

    refute_able org_member, :read, org_repo

    org_repo.add_organization(@org, action: :read)
    org_repo.reload

    assert_able org_member, :read, org_repo
  end

  test "doesn't allow a non-org-member to read a private org-owned repo when the repo grants read to the org" do
    org_repo = create(:private_repository, owner: @org)

    refute_able @user, :read, org_repo

    org_repo.add_organization(@org, action: :read)
    org_repo.reload

    refute_able @user, :read, org_repo
  end

  context "access_level_for" do
    test "is nil when the repo hasn't been saved" do
      assert_nil Repository.new.access_level_for(@user)
    end

    test "is nil when a public repo is destroyed" do
      @public_repo.destroy

      assert_nil @public_repo.access_level_for(@user)
    end

    test "is nil when a public repo is marked as deleted in the database" do
      @public_repo.remove(@owner)

      assert_nil @public_repo.access_level_for(@user)
    end

    test "is nil for an organization" do
      assert_nil @public_repo.access_level_for(@org)
    end

    test "is nil for a bot" do
      bot = create(:integration).bot
      assert_nil @public_repo.access_level_for(bot)
    end

    test "is nil when the repo is private and the user is nil" do
      assert_nil @private_repo.access_level_for(nil)
    end

    test "is nil when the repo is private and the user is unsaved" do
      assert_nil @private_repo.access_level_for(User.new)
    end

    test "is :read when the repo is public and the user is nil" do
      assert_equal :read, @public_repo.access_level_for(nil)
    end

    test "is :read when the repo is public and the user is unsaved" do
      assert_equal :read, @public_repo.access_level_for(User.new)
    end

    test "is :read when the repo is public and the user has no other access to it" do
      assert_equal :read, @public_repo.access_level_for(@user)
    end

    test "is :admin for the owner of the repo" do
      assert_equal :admin, @public_repo.access_level_for(@public_repo.owner)
    end

    test "is :write for a repo collaborator" do
      @public_repo.add_member(@user)

      assert_equal :write, @public_repo.access_level_for(@user)
    end

    test "is the team's permission for a member of the team" do
      org_repo    = create(:private_repository, owner: @org)
      team_member = create(:user, login: "team-member")
      assert_nil org_repo.access_level_for(team_member)

      @team.add_member(team_member)
      @team.add_repository(org_repo, :pull)

      assert_equal :read, org_repo.access_level_for(team_member)
    end

    test "is :read for an org-owned fork of private org-owned repo being accessed by an owner of the source's owning organization" do
      source_org_owner = create(:user, login: "source-org-owner")
      source_org       = create(:organization, login: "source-org", admin: source_org_owner)
      fork_org_owner   = create(:user, login: "fork-org-owner")
      fork_org         = create(:organization, login: "fork-org", admin: fork_org_owner)

      source_org.allow_private_repository_forking(actor: source_org_owner)

      source = create(:private_repository, owner: source_org)
      team   = create :team, organization: source_org
      team.add_repository(source, :pull)
      team.add_member(fork_org_owner)

      fork = create(:fork_repository, forker: fork_org_owner, fork_repo: source, organization: fork_org)

      assert_equal :read, fork.access_level_for(source_org_owner)
    end

    test "is :read for a business member with no other access" do
      internal_repo = create(:internal_repository)
      business = internal_repo.owner.business
      other_business_org = create(:enterprise_linked_organization, business: business)
      business_member = create(:user)
      assert_nil internal_repo.access_level_for(business_member)

      other_business_org.add_member(business_member, adder: other_business_org.admins.first)
      business_member = User.find(business_member.id)
      assert_equal :read, internal_repo.access_level_for(business_member.reload)
    end

    test "is :read for an org member when the repo is org-owned and private and the repo grants read to the org" do
      org_repo   = create(:private_repository, owner: @org)
      org_member = create(:user, login: "org-member")
      @org.add_member(org_member)

      assert_nil org_repo.access_level_for(org_member)

      org_repo.add_organization(@org, action: :read)
      org_repo.reload

      assert_equal :read, org_repo.access_level_for(org_member)
    end

    test "is nil for a non-org-member when the repo is org-owned and private and the repo grants read to the org" do
      org_repo = create(:private_repository, owner: @org)

      assert_nil org_repo.access_level_for(@user)

      org_repo.add_organization(@org, action: :read)
      org_repo.reload

      assert_nil org_repo.access_level_for(@user)
    end
  end

  context "owner_of_parent_org?" do
    test "is true when the repo is an org-owned fork of a private org-owned repo and the user is an owner of the source's owning organization" do
      source_org_owner = create(:user, login: "source-org-owner")
      source_org       = create(:organization, login: "source-org", admin: source_org_owner)
      fork_org_owner   = create(:user, login: "fork-org-owner")
      fork_org         = create(:organization, login: "fork-org", admin: fork_org_owner)

      source_org.allow_private_repository_forking(actor: source_org_owner)

      source = create(:private_repository, owner: source_org)
      team   = create :team, organization: source_org
      team.add_repository(source, :pull)
      team.add_member(fork_org_owner)

      fork = create(:fork_repository, forker: fork_org_owner, fork_repo: source, organization: fork_org)

      assert fork.owner_of_parent_org?(source_org_owner)
    end

    test "is false when the repo is an org-owned fork of a private org-owned repo and the user is a non-owner member of the source's owning organization" do
      source_org        = create(:organization, login: "source-org")
      source_org_member = create(:user, login: "source-org-member")
      source_team = create(:team, organization: source_org).add_member(source_org_member)
      source_org.allow_private_repository_forking(actor: source_org.admins.first)

      fork_org_owner = create(:user, login: "fork-org-owner")
      fork_org       = create(:organization, login: "fork-org", admin: fork_org_owner)

      source = create(:private_repository, owner: source_org)
      team   = create(:team, organization: source_org)
      team.add_repository(source, :pull)
      team.add_member(fork_org_owner)

      fork = create(:fork_repository, forker: fork_org_owner, fork_repo: source, organization: fork_org)

      refute fork.owner_of_parent_org?(source_org_member)
    end
  end
end

class EMURepositoryAbilitiesTest < GitHub::TestCase
  skip_enterprise

  fixtures do
    @owner = create :emu, :owner
    @business = @owner.enterprise_managed_business
    @owner_without_license = create :emu, :owner, business: @business

    @org = create :enterprise_linked_organization, business: @business, admin: @owner
    @org_two = create :enterprise_linked_organization, business: @business, admin: @owner
    @internal_repo = create(:internal_repository, owner: @org)
    @private_repo = create :private_repository, owner: @org

    @team = create :team, organization: @org
  end

  context "EMUs without a valid license can't view internal repos?" do
    test "is the team's permission for a member of the team" do
      team_member = create :emu, business: @business
      assert_nil @private_repo.access_level_for(team_member)

      @team.add_member(team_member)
      @team.add_repository(@private_repo, :pull)

      assert_equal :read, @private_repo.access_level_for(team_member)
    end

    test "can read internal repo if the user's a member of different org" do
      disable_feature_flag(:emu_vss_business, @business)
      member = create :emu, business: @business
      assert_nil @internal_repo.access_level_for(member)

      @org_two.add_member(member)
      member.reload
      @org_two.reload

      assert_equal :read, @internal_repo.access_level_for(member)
    end

    test "Private repos require explicit addition to the repo" do
      org_repo = create(:private_repository, owner: @org)
      member = create(:emu, business: @business)

      # member_two is an org member (but has no repo access yet)
      member_two = create(:emu, business: @business)
      @org_two.add_member(member_two)
      @org_two.reload
      member_two.reload

      # business members can't read private repo
      assert_nil org_repo.access_level_for(member) #member is not a member of the org that owns the repo
      assert_nil org_repo.access_level_for(member_two) #doesn't have access to private repo

      assert_nil org_repo.access_level_for(@owner_without_license)
      assert_equal :admin, org_repo.access_level_for(@owner) # Org admin and has acess to all repos

      @org.add_member(member)
      org_repo.add_member(member)
      org_repo.reload
      member.reload
      @org.reload

      assert_equal :write, org_repo.access_level_for(member) #member is added to the org+repo
      assert_nil org_repo.access_level_for(member_two) #doesn't have access to private repo
      assert_nil org_repo.access_level_for(@owner_without_license)
      assert_equal :admin, org_repo.access_level_for(@owner) # Org admin and has acess to all repos
    end
  end

  context "#multiple_target_for_conditional_access" do
    test "gracefully handles a deleted owner" do
      repos = create_list(:repository, 4)
      repos.first.owner.destroy!
      repos.first.reload

      result = Repository.multiple_target_for_conditional_access(repos)
      assert_equal 3, result.keys.count
      refute_includes result.keys, repos.first
    end
  end
end
