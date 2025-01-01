# typed: true
# frozen_string_literal: true

require "test_helper"

class OctoshiftAuthorizationPolicyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @org = create(:organization, plan: GitHub::Plan.free)

    @business_org_user = create(:user)
    @business_org = create :business_org
    @billing_manager = create(:user, login: "billing-manager")
    @business_owner = create(:user)

    @business = create(:business, owners: [@business_owner])
    @business.billing.add_manager(@billing_manager, actor: @business_owner)

    @business.add_organization(@business_org)

    @org_user = create(:user)
    @org.add_member(@org_user)
    @team = create(:team, organization: @org)
    @team_user = create(:user, login: "team-user")
    @team.add_member(@team_user)
    @role = Role.octoshift_migrator_role
  end

  context "#can_import_repo?" do
    context "when importing into user account" do
      test "allows import into own user account" do
        assert Octoshift::AuthorizationPolicy.can_import_repo?(user: @user, owner: @user)
      end

      test "disallows import into another user's account" do
        rando = create(:user)
        refute Octoshift::AuthorizationPolicy.can_import_repo?(user: @user, owner: rando)
      end
    end

    context "when importing into organization account" do
      context "when admin" do
        test "allows import into organization when user has admin access" do
          @org.add_member(@user, action: :admin)
          assert Octoshift::AuthorizationPolicy.can_import_repo?(user: @user, owner: @org)
        end
      end

      context "when octoshift_migrator" do
        test "allows import into organization when user is an octoshift_migrator and org member" do
          @org.add_member(@user, action: :write)
          Permissions::Granters::RoleGranter.new(actor: @user, target: @org, role: Role.octoshift_migrator_role).grant!
          assert Octoshift::AuthorizationPolicy.can_import_repo?(user: @user, owner: @org)
        end

        test "allows import into organization when user's team is an octoshift_migrator and team is part of org" do
          Permissions::Granters::RoleGranter.new(actor: @team, target: @org, role: Role.octoshift_migrator_role).grant!
          assert Octoshift::AuthorizationPolicy.can_import_repo?(user: @team_user, owner: @org)
        end

        test "disallows import into organization when user's team is an octoshift_migrator but team is not part of org" do
          other_org = create(:organization, plan: GitHub::Plan.free)
          team = create(:team, organization: other_org)
          team_user = create(:user, login: "other-org-team-user")
          team.add_member(team_user)
          Permissions::Granters::RoleGranter.new(actor: team, target: @org, role: Role.octoshift_migrator_role).grant!
          refute Octoshift::AuthorizationPolicy.can_import_repo?(user: @user, owner: @org)
        end

        test "disallows import into organization when user is an octoshift_migrator and not an org member" do
          Permissions::Granters::RoleGranter.new(actor: @user, target: @org, role: Role.octoshift_migrator_role).grant!
          refute Octoshift::AuthorizationPolicy.can_import_repo?(user: @user, owner: @org)
        end
      end

      context "when neither an admin or octoshift_migrator" do
        test "disallows import into organization when user has read access" do
          @org.add_member(@user, action: :read)
          refute Octoshift::AuthorizationPolicy.can_import_repo?(user: @user, owner: @org)
        end

        test "disallows import into organization when user only has write access" do
          @org.add_member(@user, action: :write)
          refute Octoshift::AuthorizationPolicy.can_import_repo?(user: @user, owner: @org)
        end
      end
    end

    context "when importing into business owned organization account" do
      context "when admin" do
        test "allow import into business organization" do
          @business_org.add_member(@business_org_user, action: :admin)
          assert Octoshift::AuthorizationPolicy.can_import_repo?(user: @business_org_user, owner: @business_org)
        end
      end

      context "when octoshift_migrator" do
        test "allow import into business organization" do
          @business_org.add_member(@business_org_user, action: :write)
          Permissions::Granters::RoleGranter.new(actor: @business_org_user, target: @business_org, role: Role.octoshift_migrator_role).grant!
          assert Octoshift::AuthorizationPolicy.can_import_repo?(user: @business_org_user, owner: @business_org)
        end
      end

      test "disallows import into business organization when user has read access" do
        @business_org.add_member(@business_org_user, action: :read)
        refute Octoshift::AuthorizationPolicy.can_import_repo?(user: @business_org_user, owner: @business_org)
      end

      test "disallows import into business organization when user has write access" do
        @business_org.add_member(@business_org_user, action: :write)
        refute Octoshift::AuthorizationPolicy.can_import_repo?(user: @business_org_user, owner: @business_org)
      end

      test "disallow import into business organization when user is business owner" do
        refute Octoshift::AuthorizationPolicy.can_import_repo?(user: @business_owner, owner: @business_org)
      end

      test "disallow import into business organization when user is member of business but not member of any org" do
        refute Octoshift::AuthorizationPolicy.can_import_repo?(user: @billing_manager, owner: @business_org)
      end

      test "disallow import into business organization when user is an admin of a different org" do
        user = create(:user)
        other_org = create(:business_org)
        @business.add_organization(other_org)
        other_org.add_member(user, action: :admin)
        refute Octoshift::AuthorizationPolicy.can_import_repo?(user: user, owner: @business_org)
        assert Octoshift::AuthorizationPolicy.can_import_repo?(user: user, owner: other_org)
      end
    end
  end

  context "#can_export_repo?" do
    context "when exporting from organization account" do
      context "when admin" do
        test "allows export from organization when user has admin access" do
          @org.add_member(@user, action: :admin)
          assert Octoshift::AuthorizationPolicy.can_export_repo?(user: @user, owner: @org)
        end
      end

      context "when octoshift_migrator" do
        test "allows export from organization when user is an octoshift_migrator and org member" do
          @org.add_member(@user, action: :write)
          Permissions::Granters::RoleGranter.new(actor: @user, target: @org, role: Role.octoshift_migrator_role).grant!
          assert Octoshift::AuthorizationPolicy.can_export_repo?(user: @user, owner: @org)
        end

        test "allows export from organization when user's team is an octoshift_migrator and team is part of org" do
          Permissions::Granters::RoleGranter.new(actor: @team, target: @org, role: Role.octoshift_migrator_role).grant!
          assert Octoshift::AuthorizationPolicy.can_export_repo?(user: @team_user, owner: @org)
        end

        test "disallows export from organization when user's team is an octoshift_migrator but team is not part of org" do
          other_org = create(:organization, plan: GitHub::Plan.free)
          team = create(:team, organization: other_org)
          team_user = create(:user, login: "other-org-team-user")
          team.add_member(team_user)
          Permissions::Granters::RoleGranter.new(actor: team, target: @org, role: Role.octoshift_migrator_role).grant!
          refute Octoshift::AuthorizationPolicy.can_export_repo?(user: @user, owner: @org)
        end

        test "disallows export from organization when user is an octoshift_migrator and not an org member" do
          Permissions::Granters::RoleGranter.new(actor: @user, target: @org, role: Role.octoshift_migrator_role).grant!
          refute Octoshift::AuthorizationPolicy.can_export_repo?(user: @user, owner: @org)
        end
      end

      context "when neither an admin or octoshift_migrator" do
        test "disallows export from organization when user has read access" do
          @org.add_member(@user, action: :read)
          refute Octoshift::AuthorizationPolicy.can_export_repo?(user: @user, owner: @org)
        end

        test "disallows export from organization when user only has write access" do
          @org.add_member(@user, action: :write)
          refute Octoshift::AuthorizationPolicy.can_export_repo?(user: @user, owner: @org)
        end
      end
    end
  end

  context ".has_octoshift_migrator_role?" do
    test "returns true when user has the octoshift_migrator role" do
      Octoshift::AuthorizationPolicy.grant_octoshift_migrator!(actor_type: "USER", actor: @org_user.display_login, organization: @org)

      assert Octoshift::AuthorizationPolicy.has_octoshift_migrator_role?(@org_user, @org)
    end

    test "returns false when user does not have the octoshift_migrator role" do
      Octoshift::AuthorizationPolicy.revoke_octoshift_migrator!(actor_type: "USER", actor: @org_user.display_login, organization: @org)

      refute Octoshift::AuthorizationPolicy.has_octoshift_migrator_role?(@org_user, @org)
    end
  end

  context ".grant_octoshift_migrator!" do
    test "grants a user who is the org member the octoshift_migrator fine-grained permission" do
      result = Octoshift::AuthorizationPolicy.grant_octoshift_migrator!(actor_type: "USER", actor: @org_user.display_login, organization: @org)
      assert result.success?
      assert UserRole.find_by(actor: @org_user, target_id: @org.id, target_type: "Organization", role: @role)
    end

    test "raises UserDoesNotBelongToOrgError error when the user is not a member of the org" do
      random_user = create(:user)

      assert_raises_with_message(
        Octoshift::AuthorizationPolicy::UserDoesNotBelongToOrgError,
        "#{random_user.display_login} is not a member of #{@org.display_login} organization."
      ) do
        Octoshift::AuthorizationPolicy.grant_octoshift_migrator!(actor_type: "USER", actor: random_user.display_login, organization: @org)
      end
    end

    test "grants a team the octoshift_migrator fine-grained permission" do
      result = Octoshift::AuthorizationPolicy.grant_octoshift_migrator!(actor_type: "TEAM", actor: @team.slug, organization: @org)
      assert result.success?
      assert UserRole.find_by(actor: @team, target_id: @org.id, target_type: "Organization", role: @role)
    end

    test "is idempotent" do
      2.times.each do
        result = Octoshift::AuthorizationPolicy.grant_octoshift_migrator!(actor_type: "USER", actor: @org_user.display_login, organization: @org)
        assert result.success?
      end
    end

    test "raises an error when org does not have the necessary plan to grant this role" do
      other_org = create(:organization)
      other_org_user = create(:user)
      other_org.add_member(other_org_user)

      assert_raises_with_message(
        Octoshift::AuthorizationPolicy::RoleGranterError,
        "Validation failed: Target does not have the necessary plan to grant this role"
      ) do
        Octoshift::AuthorizationPolicy.grant_octoshift_migrator!(actor_type: "USER", actor: other_org_user.display_login, organization: other_org)
      end
    end

    test "raises ActorNotFoundError if the user wasn't found" do
      assert_raises_with_message(
        Octoshift::AuthorizationPolicy::ActorNotFoundError,
        "Could not find the user: 'not_existing_user'"
      ) do
        Octoshift::AuthorizationPolicy.grant_octoshift_migrator!(actor_type: "USER", actor: "not_existing_user", organization: @org)
      end
    end

    test "raises ActorNotFoundError if the team wasn't found" do
      assert_raises_with_message(
        Octoshift::AuthorizationPolicy::ActorNotFoundError,
        "Could not find the team: 'not_existing_team'"
      ) do
        Octoshift::AuthorizationPolicy.grant_octoshift_migrator!(actor_type: "TEAM", actor: "not_existing_team", organization: @org)
      end
    end
  end

  context ".revoke_octoshift_migrator!" do
    test "revokes octoshift_migrator from a user who is the org member" do
      Octoshift::AuthorizationPolicy.grant_octoshift_migrator!(actor_type: "USER", actor: @org_user.display_login, organization: @org)
      assert UserRole.find_by(actor: @org_user, target_id: @org.id, target_type: "Organization", role: @role)

      result = Octoshift::AuthorizationPolicy.revoke_octoshift_migrator!(actor_type: "USER", actor: @org_user.display_login, organization: @org)
      assert result.success?
      refute UserRole.find_by(actor: @org_user, target_id: @org.id, target_type: "Organization", role: @role)
    end

    test "trying to revoke octoshift_migrator from a user who is not a member of the org succeeds" do
      random_user = create(:user)
      result = Octoshift::AuthorizationPolicy.revoke_octoshift_migrator!(actor_type: "USER", actor: random_user.display_login, organization: @org)
      assert result.success?
    end

    test "revokes octoshift_migrator from a team" do
      Octoshift::AuthorizationPolicy.grant_octoshift_migrator!(actor_type: "TEAM", actor: @team.slug, organization: @org)
      assert UserRole.find_by(actor: @team, target_id: @org.id, target_type: "Organization", role: @role)

      result = Octoshift::AuthorizationPolicy.revoke_octoshift_migrator!(actor_type: "TEAM", actor: @team.slug, organization: @org)
      assert result.success?
      refute UserRole.find_by(actor: @team, target_id: @org.id, target_type: "Organization", role: @role)
    end

    test "is idempotent" do
      2.times.each do
        result = Octoshift::AuthorizationPolicy.revoke_octoshift_migrator!(actor_type: "USER", actor: @org_user.display_login, organization: @org)
        assert result.success?
      end
    end

    test "raises ActorNotFoundError if the user wasn't found" do
      assert_raises_with_message(
        Octoshift::AuthorizationPolicy::ActorNotFoundError,
        "Could not find the user: 'not_existing_user'"
      ) do
        Octoshift::AuthorizationPolicy.revoke_octoshift_migrator!(actor_type: "USER", actor: "not_existing_user", organization: @org)
      end
    end

    test "raises ActorNotFoundError if the team wasn't found" do
      assert_raises_with_message(
        Octoshift::AuthorizationPolicy::ActorNotFoundError,
        "Could not find the team: 'not_existing_team'"
      ) do
        Octoshift::AuthorizationPolicy.revoke_octoshift_migrator!(actor_type: "TEAM", actor: "not_existing_team", organization: @org)
      end
    end
  end
end
