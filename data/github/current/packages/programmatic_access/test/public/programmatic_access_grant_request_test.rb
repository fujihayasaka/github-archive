# typed: true
# frozen_string_literal: true

require "test_helper"

class ProgrammaticAccessGrantRequestTest < GitHub::TestCase
  include ApiProgrammaticGrantHelpers

  fixtures do
    @org = create(:organization)
    @admin = @org.admins.first

    @member1 = create(:user)
    @member2 = create(:user)
    @org.add_member(@member1)
    @org.add_member(@member2)
    @repo = create(:private_repository, :minimal, owner: @org)

    # PAT for member1
    @pat1 = make_user_programmatic_access_with_grant_request(
      target: @org, actor: @member1, permissions: { "members" => :read, "organization_secrets" => :write }
    )
    # PAT for member2
    @pat2 = make_user_programmatic_access_with_grant_request(
      target: @org, repositories: [@repo], actor: @member2, permissions: { "actions" => :read }
    )

    # All public repos
    @grant_request1 = @pat1.grant_request
    # Select private repo
    @grant_request2 = @pat2.grant_request

    @org_grant_requests = [@grant_request1, @grant_request2]
    @org_grant_requests.each { |grant| refute_nil grant }
  end

  context ".with_target" do
    test "it loads requests by target" do
      requests = ProgrammaticAccessGrantRequest.with_target(@org)

      assert_same_elements @org_grant_requests, requests
      assert_equal @org, requests.first.target
    end
  end

  context ".from_target_and_id" do
    test "it loads a grant by target and id" do
      grant = ProgrammaticAccessGrantRequest.from_target_and_id(@org, @grant_request1.id)
      assert_equal @grant_request1, grant
    end

    test "it returns nil if the request does not exist" do
      different_org = create(:organization)
      assert_nil ProgrammaticAccessGrantRequest.from_target_and_id(different_org, @grant_request1.id)
    end
  end

  context ".targeted_organization_ids" do
    test "return empty relation without request targeting orgs" do
      @org_grant_requests.each(&:delete)

      orgs = ProgrammaticAccessGrantRequest.targeted_organization_ids
      assert_predicate orgs, :empty?
    end

    test "returns multiple distinct orgs" do
      # Another request targeting other org
      other_org = create(:organization)
      other_org_member = create(:user)
      other_org.add_member(other_org_member)

      make_user_programmatic_access_with_grant_request(
        target: other_org, actor: other_org_member, permissions: { "members" => :read }
      )

      # Another request targeting same org
      other_member = create(:user)
      @org.add_member(other_member)

      make_user_programmatic_access_with_grant_request(
        target: @org, actor: other_member, permissions: { "members" => :read }
      )

      org_ids = ProgrammaticAccessGrantRequest.targeted_organization_ids
      assert_same_elements [@org.id, other_org.id], org_ids
    end

    test "returns ascending organization ids" do
      second_org = create(:organization)
      member = create(:user)
      second_org.add_member(member)

      make_user_programmatic_access_with_grant_request(
        target: second_org, actor: member, permissions: { "members" => :read }
      )

      org_ids = ProgrammaticAccessGrantRequest.targeted_organization_ids
      assert_equal [@org.id, second_org.id].sort, org_ids
    end

    test "skip all organization ids up to next_id when given" do
      second_org = create(:organization)
      member_2 = create(:user)
      second_org.add_member(member_2)

      make_user_programmatic_access_with_grant_request(
        target: second_org, actor: member_2, permissions: { "members" => :read }
      )

      third_org = create(:organization)
      member_3 = create(:user)
      third_org.add_member(member_3)

      make_user_programmatic_access_with_grant_request(
        target: third_org, actor: member_3, permissions: { "members" => :read }
      )

      org_ids = ProgrammaticAccessGrantRequest.targeted_organization_ids(next_id: second_org.id)
      assert_equal [second_org.id, third_org.id].sort, org_ids
    end
  end

  context ".approvable_by?" do
    context "organization target" do
      test "returns true if the grant target is adminable by the actor" do
        assert ProgrammaticAccessGrantRequest.approvable_by?(@org, @admin)
      end

      context "for org members" do
        test "returns true if the org has opted into auto approving requests" do
          @org.enable_auto_pat_request_approval(actor: @admin)
          assert ProgrammaticAccessGrantRequest.approvable_by?(@org, @member1)
        end

        test "returns false by default" do
          refute ProgrammaticAccessGrantRequest.approvable_by?(@org, @member1)
        end
      end
    end

    context "user target" do
      test "returns true if the user is requesting access on themselves" do
        assert ProgrammaticAccessGrantRequest.approvable_by?(@admin, @admin)
      end

      test "returns false if the user is requesting access on another user" do
        refute ProgrammaticAccessGrantRequest.approvable_by?(@admin, @member1)
      end
    end
  end

  test ".none" do
    assert_empty ProgrammaticAccessGrantRequest.none
  end

  context ".with_target_and_filters" do
    test "it returns none if no target provided" do
      filters = {}
      requests = ProgrammaticAccessGrantRequest.with_target_and_filters(nil, filters)
      assert_empty requests
    end

    test "it returns all target grant requests if no filters provided" do
      filters = {}
      requests = ProgrammaticAccessGrantRequest.with_target_and_filters(@org, filters)
      assert_same_elements @org_grant_requests, requests
    end

    context "when filter conditions intersect" do
      test "it returns grant request matching permission filter" do
        filters = { permission: @grant_request1.permissions }
        requests = ProgrammaticAccessGrantRequest.with_target_and_filters(@org, filters)
        assert_equal [@grant_request1], requests
      end

      test "it returns grant requests matching repo filter" do
        filters = { repository: @repo }
        requests = ProgrammaticAccessGrantRequest.with_target_and_filters(@org, filters)
        assert_equal [@grant_request2], requests
      end

      test "it returns grant requests matching owner filter" do
        filters = { owner: @member1 }
        requests = ProgrammaticAccessGrantRequest.with_target_and_filters(@org, filters)
        assert_equal [@grant_request1], requests
      end

      test "it returns grant requests matching repo & permission filter" do
        filters = { repository: @repo, permission: @grant_request2.permissions }
        requests = ProgrammaticAccessGrantRequest.with_target_and_filters(@org, filters)
        assert_equal [@grant_request2], requests
      end

      test "it returns grant requests matching owner & permission filter" do
        filters = { owner: @member2, permission: @grant_request2.permissions  }
        requests = ProgrammaticAccessGrantRequest.with_target_and_filters(@org, filters)
        assert_equal [@grant_request2], requests
      end

      test "it returns grant requests matching owner & repo filter" do
        filters = { owner: @member2, repository: @repo  }
        requests = ProgrammaticAccessGrantRequest.with_target_and_filters(@org, filters)
        assert_equal [@grant_request2], requests
      end

      test "it returns grant requests matching owner, repo & permission  filter" do
        filters = { owner: @member2, repository: @repo, permission: @grant_request2.permissions  }
        requests = ProgrammaticAccessGrantRequest.with_target_and_filters(@org, filters)
        assert_equal [@grant_request2], requests
      end


      test "it returns grant with write permission if read filter is provided" do
        filters = { owner: @member1, permission: { "organization_secrets" => :read } } # write permission is a superset of read
        grants = ProgrammaticAccessGrantRequest.with_target_and_filters(@org, filters)
        assert_equal [@grant_request1], grants
      end
    end

    context "when filter conditions do not intersect" do
      test "it returns no grant requests matching owner & repo filter" do
        filters = { owner: @member1, repository: @repo  }
        requests = ProgrammaticAccessGrantRequest.with_target_and_filters(@org, filters)
        assert_equal [], requests
      end

      test "it returns no grant requests matching repo & permission filter" do
        filters = { repository: @repo, permission: @grant_request1.permissions  }
        requests = ProgrammaticAccessGrantRequest.with_target_and_filters(@org, filters)
        assert_equal [], requests
      end

      test "it returns no grant requests matching owner & permission filter" do
        filters = { owner: @member2, permission: @grant_request1.permissions  }
        requests = ProgrammaticAccessGrantRequest.with_target_and_filters(@org, filters)
        assert_equal [], requests
      end

      test "it returns no grant with write permission" do
        filters = { owner: @user, permission: { "members" => :write } }
        grants = ProgrammaticAccessGrantRequest.with_target_and_filters(@org, filters)
        assert_equal [], grants
      end
    end
  end
end
