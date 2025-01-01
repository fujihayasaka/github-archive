# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryCodeownersActiveRecordOwnerResolverTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, login: "owner")
    @org = create(:organization, admin: @owner, login: "github")
    @team = create(:team, organization: @org, name: "team", privacy: :closed)
    @repository = create(:repository, owner: @org)
  end

  setup do
    @resolver = Repository::Codeowners::ActiveRecordOwnerResolver.new(@repository)
  end

  context "#register_owners" do
    test "cannot be called after resolving an owner" do
      an_owner = ::Codeowners::Owner.new("@owner")
      another_owner = ::Codeowners::Owner.new("@someone")

      @resolver.register_owners([an_owner])
      @resolver.resolve("@owner")

      assert_raises(Repository::Codeowners::ActiveRecordOwnerResolver::LockedError) do
        @resolver.register_owners([another_owner])
      end
    end

    test "registers owner correctly on multi-tenant environments" do
      on_multi_tenant_enterprise
      GitHub.flipper.enable(:tenant_namespacing)
      owner = create(:emu, login: "owner")
      business = owner.enterprise_managed_business

      org = create :organization, admin: owner

      repo = create(:repository, owner: org)

      an_owner = ::Codeowners::Owner.new("@owner")
      resolver = Repository::Codeowners::ActiveRecordOwnerResolver.new(repo)

      resolver.register_owners([an_owner])
      resolver.resolve("@owner")

      assert_equal owner, resolver.users_by_username["@owner"]
    end
  end

  context "#resolve" do
    test "calls team_ids_with_direct_privileged_access" do
      team_owner = ::Codeowners::Owner.new("@#{@team.combined_slug}")
      @resolver.register_owners([team_owner])
      @repository.expects(:team_ids_with_direct_privileged_access).returns([])

      @resolver.resolve("@#{@team.combined_slug}")
    end
  end
end
