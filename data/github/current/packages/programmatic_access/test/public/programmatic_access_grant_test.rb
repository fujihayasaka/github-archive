# typed: true
# frozen_string_literal: true

require "test_helper"

class ProgrammaticAccessGrantTest < GitHub::TestCase
  include ApiProgrammaticGrantHelpers

  fixtures do
    @user = create(:user)
    @other_user = create(:user)
    @org  = create(:organization, admin: @user)
    @org.add_member(@other_user, action: :admin)
    @repo = create(:private_repository, :minimal, owner: @org)

    # PAT for user
    @pat1 = make_user_programmatic_access_with_grant(
      requester: @user, target: @org, permissions: { "members" => :read, "organization_secrets" => :write }
    )
    # PAT for other_user
    @pat2 = make_user_programmatic_access_with_grant(
      requester: @other_user, target: @org, repositories: [@repo], permissions: { "actions" => :read }
    )

    # All public repos
    @grant1 = @pat1.grant_for(@org)
    # Select private repo
    @grant2 = @pat2.grant_for(@org)

    @org_grants = [@grant1, @grant2]
  end

  context "#null_grant" do
    test "returns a NullProgrammaticAccessGrant" do
      pat = ProgrammaticAccess.new_access(@user)
      null_grant = ProgrammaticAccessGrant.null_grant(pat)

      assert_instance_of NullProgrammaticAccessGrant, null_grant
      assert_equal pat.owner, null_grant.target
      assert_equal pat, null_grant.user_programmatic_access
    end
  end

  context ".with_target" do
    test "it loads grants by target" do
      grants = ProgrammaticAccessGrant.with_target(@org)
      assert_same_elements @org_grants, grants
      assert_equal @org, grants.first.target
    end
  end

  context ".from_target_and_id" do
    test "it loads a grant by target and id" do
      grant = ProgrammaticAccessGrant.from_target_and_id(@org, @grant1.id)
      assert_equal @grant1, grant
    end

    test "it returns nil if the grant does not exist" do
      different_org = create(:organization, admin: @user)

      grant = ProgrammaticAccessGrant.from_target_and_id(different_org, @grant1.id)
      refute grant
    end
  end

  context ".with_target_and_filters" do

    test "it returns none if no target provided" do
      filters = {}
      grants = ProgrammaticAccessGrant.with_target_and_filters(nil, filters)
      assert_empty grants
    end

    test "it returns all target grant if no filters provided" do
      filters = {}
      grants = ProgrammaticAccessGrant.with_target_and_filters(@org, filters)
      assert_same_elements @org_grants, grants
    end

    context "when filter conditions intersect" do
      test "it returns grant matching permission filter" do
        filters = { permission: @grant1.permissions }
        grants = ProgrammaticAccessGrant.with_target_and_filters(@org, filters)
        assert_equal [@grant1], grants
      end

      test "it returns grant matching repo filter" do
        filters = { repository: @repo }
        grants = ProgrammaticAccessGrant.with_target_and_filters(@org, filters)
        assert_equal [@grant2], grants
      end

      test "it returns grant matching owner filter" do
        filters = { owner: @user }
        grants = ProgrammaticAccessGrant.with_target_and_filters(@org, filters)
        assert_equal [@grant1], grants
      end

      test "it returns grant matching repo & permission filter" do
        filters = { repository: @repo, permission: @grant2.permissions  }
        grants = ProgrammaticAccessGrant.with_target_and_filters(@org, filters)
        assert_equal [@grant2], grants
      end

      test "it returns grant matching owner & permission filter" do
        filters = { owner: @other_user, permission: @grant2.permissions  }
        grants = ProgrammaticAccessGrant.with_target_and_filters(@org, filters)
        assert_equal [@grant2], grants
      end

      test "it returns grant matching owner & repo filter" do
        filters = { owner: @other_user, repository: @repo  }
        grants = ProgrammaticAccessGrant.with_target_and_filters(@org, filters)
        assert_equal [@grant2], grants
      end

      test "it returns grant matching owner, repo & permission filter" do
        filters = { owner: @other_user, repository: @repo, permission: @grant2.permissions  }
        grants = ProgrammaticAccessGrant.with_target_and_filters(@org, filters)
        assert_equal [@grant2], grants
      end

      test "it returns grant with write permission if read filter is provided" do
        filters = { owner: @user, permission: { "organization_secrets" => :read } } # write permission is a superset of read
        grants = ProgrammaticAccessGrant.with_target_and_filters(@org, filters)
        assert_equal [@grant1], grants
      end
    end

    context "when filter conditions do not intersect" do
      test "it returns no grant matching owner & repo filter" do
        filters = { owner: @user, repository: @repo  }
        grants = ProgrammaticAccessGrant.with_target_and_filters(@org, filters)
        assert_equal [], grants
      end

      test "it returns no grant matching repo & permission filter" do
        filters = { repository: @repo, permission: @grant1.permissions  }
        grants = ProgrammaticAccessGrant.with_target_and_filters(@org, filters)
        assert_equal [], grants
      end

      test "it returns no grant matching owner & permission filter" do
        filters = { owner: @other_user, permission: @grant1.permissions  }
        grants = ProgrammaticAccessGrant.with_target_and_filters(@org, filters)
        assert_equal [], grants
      end

      test "it returns no grant with write permission" do
        filters = { owner: @user, permission: { "members" => :write } }
        grants = ProgrammaticAccessGrant.with_target_and_filters(@org, filters)
        assert_equal [], grants
      end
    end
  end
end
