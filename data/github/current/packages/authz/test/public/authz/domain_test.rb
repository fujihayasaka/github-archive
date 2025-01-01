# typed: true
# frozen_string_literal: true

require "test_helper"

module Authz
  class DomainTest < GitHub::TestCase
    include FineGrainedPermissionsTestHelper
    include ApiProgrammaticGrantHelpers
    include DogstatsTestHelpers

    fixtures do
      @biz_admin = create(:user)
      @org_admin = create(:user)
      @member = create(:user)

      @business = create :business, owners: [@biz_admin]
      @org = create :business_plus_organization, business: @business, admin: @org_admin
      @repo = create(:repository, :minimal, owner: @org)

      @enterprise_team = create(:enterprise_team, business: @business)

      @org.add_member(@member)
      @org_team = create(:team, organization: @org, privacy: :closed)
      @org_child_team = create(:team, organization: @org, parent_team_id: @org_team.id, privacy: :closed)

      @custom_repo_role = create(:custom_repository_role, owner_id: @org.id, owner_type: "Organization", base_role_id: Role.triage_role.id)
      @custom_org_role = create(:custom_organization_role, owner_id: @org.id)
    end

    setup do
      enable_feature_flag(:custom_enterprise_role_feature)
      @domain = T.let(Authz::Domain.new, T.nilable(Authz::Domain))
      @org_fgp = Permissions::FineGrainedPermissionIm.find!(:organization_test_read_permission).action.to_sym
      @biz_fgp = Permissions::FineGrainedPermissionIm.find!(:enterprise_test_read_permission).action.to_sym
    end

    sig { returns(Authz::Domain) }
    def domain
      T.must(@domain)
    end

    sig { params(request_response_map: T::Hash[Authz::Request, Authzd::Proto::Decision]).returns(Authzd::BatchResponse) }
    def build_authzd_batch_response(request_response_map)
      authzd_reqs = request_response_map.keys.map do |domain_request|
        Authzd::Proto::Request.new(attributes: Permissions::Enforcer.attrs_for(**domain_request.authzd_request_hash))
      end
      batch_req = Authzd::Proto::BatchRequest.new(requests: authzd_reqs)
      batch_decision = Authzd::Proto::BatchDecision.new(decisions: request_response_map.values)
      Authzd::BatchResponse.from_decision(batch_req, batch_decision)
    end

    context "check_allowed" do
      test "authorizes a user with an organization FGP" do
        refute domain.check_allowed(@member, @org_fgp, @org)

        grant_custom_org_role(user: @member, target: @org, fgps: [@org_fgp])
        assert domain.check_allowed(@member, @org_fgp, @org)
      end

      test "authorizes a user with a team-granted organization FGP" do
        @org_team.add_member(@member)

        refute domain.check_allowed(@member, @org_fgp, @org)

        grant_custom_org_role(user: @org_team, target: @org, fgps: [@org_fgp])
        assert domain.check_allowed(@member, @org_fgp, @org)
      end

      test "authorizes a user with a parent-team-granted organization FGP" do
        @org_child_team.add_member(@member)
        refute domain.check_allowed(@member, @org_fgp, @org)

        grant_custom_org_role(user: @org_child_team, target: @org, fgps: [@org_fgp])
        assert domain.check_allowed(@member, @org_fgp, @org)
      end

      test "authorizes a user who is an org admin" do
        refute domain.check_allowed(@member, @org_fgp, @org)

        @org.update_member(@member, action: :admin)
        assert domain.check_allowed(@member, @org_fgp, @org)
      end

      test "authorizes a user with an enterprise FGP", skip_if_feature_disabled: :custom_enterprise_role_feature do
        refute domain.check_allowed(@member, @biz_fgp, @business)

        grant_custom_enterprise_role(user: @member, target: @business, fgps: [@biz_fgp])
        assert domain.check_allowed(@member, @biz_fgp, @business)
      end

      test "authorizes a user with an enterprise-team granted FGP", skip_if_feature_disabled: :custom_enterprise_role_feature do
        EnterpriseTeamMembership.create!(enterprise_team: @enterprise_team, user: @member)
        refute domain.check_allowed(@member, @biz_fgp, @business)

        role = create_custom_enterprise_role(owner: @business, fgps: [@biz_fgp])
        UserRole.new(actor: @enterprise_team, target: @business, role: role).save!(validate: false)
        assert domain.check_allowed(@member, @biz_fgp, @business)
      end

      test "authorizes a user with an enterprise team v2 granted org FGP" do
        org = create(:enterprise_linked_organization)
        # helper method enables FF for ETv2
        team_member, team = add_user_to_enterprise_team(business: org.business)
        refute domain.check_allowed(team_member, @org_fgp, org)

        # grant FGP to team
        grant_fgp_to_enterprise_team(team: team, target: org, fgps: [@org_fgp])

        # @TODO authz-exp fix the authzd policy to allow for Business Team role grants
        # assert domain.check_allowed(team_member, @org_fgp, org)
      end

      test "authorizes a user with an enterprise team v2 granted enterprise FGP" do
        # helper method enables FF for ETv2
        team_member, team = add_user_to_enterprise_team(business: @business)

        refute domain.check_allowed(team_member, @biz_fgp, @business)

        # grant FGP to team
        grant_fgp_to_enterprise_team(team: team, target: @business, fgps: [@biz_fgp])

        assert domain.check_allowed(team_member, @biz_fgp, @business)
      end

      test "authorizes a user who is an enterprise admin" do
        refute domain.check_allowed(@org_admin, @biz_fgp, @business)
        assert domain.check_allowed(@biz_admin, @biz_fgp, @business)
      end

      test "authorizes a fine-grained organization PAT" do
        patv2 = create(:user_programmatic_access, owner: @member)
        fgp = Permissions::FineGrainedPermissionIm.find!(@org_fgp)

        grant = make_programmatic_access_grant(access: patv2, permissions: {}, target: @org)
        refute domain.check_allowed(grant, @org_fgp, @org)

        permissions = { fgp.programmatic_resource => fgp.programmatic_action }
        grant = make_programmatic_access_grant(access: patv2, permissions: permissions, target: @org)
        assert domain.check_allowed(grant, @org_fgp, @org)
      end

      test "raises an error when indeterminate from authzd and records failure metric" do
        domain_req = Request.new(actor: @member, permission: @org_fgp, subject: @org)
        batch_response = build_authzd_batch_response({ domain_req => Authzd::Proto::Decision.indeterminate })
        grant_custom_org_role(user: @member, target: @org, fgps: [@org_fgp])
        Permissions::Enforcer.stubs(:batch_authorize).returns(batch_response)
        assert_raises_with_message(IndeterminateError, "Indeterminate response(s) from authzd.\nReason: Indeterminate\nError: ") do
          domain.check_allowed(@member, @org_fgp, @org)
        end

        assert_dogstats_distribution(1, "authz.domain.check_allowed", tags: [
          "success:false",
          "permission:#{@org_fgp}",
          "actor_type:User",
          "subject_type:Organization",
        ])
      end

      test "raises any unexpected errors and records failure metric" do
        grant_custom_org_role(user: @member, target: @org, fgps: [@org_fgp])
        Permissions::Enforcer.stubs(:batch_authorize).raises(StandardError.new("Oh wow that is bad"))
        assert_raises_with_message(StandardError, "Oh wow that is bad") do
          domain.check_allowed(@member, @org_fgp, @org)
        end

        assert_dogstats_distribution(1, "authz.domain.check_allowed", tags: [
          "success:false",
          "permission:#{@org_fgp}",
          "actor_type:User",
          "subject_type:Organization",
        ])
      end

      test "emits performance metrics" do
        domain.check_allowed(@biz_admin, @biz_fgp, @business)

        assert_dogstats_distribution(1, "authz.domain.check_allowed", tags: [
          "success:true",
          "permission:#{@biz_fgp}",
          "actor_type:User",
          "subject_type:Business",
        ])
      end
    end

    context "check_multiple_permissions" do
      test "returns results for each permission" do
        not_granted_org_fgp = Permissions::FineGrainedPermissionIm.find!(:read_organization_custom_org_role).action.to_sym
        grant_custom_org_role(user: @member, target: @org, fgps: [@org_fgp])

        results = domain.check_multiple_permissions(@member, [@org_fgp, not_granted_org_fgp], @org)
        assert results[@org_fgp]
        refute results[not_granted_org_fgp]
      end

      test "returns results for programmatic actors" do
        patv2 = create(:user_programmatic_access, owner: @member)
        not_granted_fgp = :read_organization_custom_org_role

        fgp = Permissions::FineGrainedPermissionIm.find!(@org_fgp)
        permissions = { fgp.programmatic_resource => fgp.programmatic_action }
        grant = make_programmatic_access_grant(access: patv2, permissions: permissions, target: @org)

        results = domain.check_multiple_permissions(grant, [@org_fgp, not_granted_fgp], @org)
        assert results[@org_fgp]
        refute results[not_granted_fgp]
      end

      test "raises if any request is indeterminate" do
        req1 = Request.new(actor: @member, permission: @org_fgp, subject: @org)
        req2 = Request.new(actor: @member, permission: :read_organization_custom_org_role, subject: @org)
        batch_response = build_authzd_batch_response({
          req1 => Authzd::Proto::Decision.deny,
          req2 => Authzd::Proto::Decision.indeterminate
        })

        Permissions::Enforcer.stubs(:batch_authorize).returns(batch_response)
        assert_raises_with_message(IndeterminateError, "Indeterminate response(s) from authzd.\nReason: Indeterminate\nError: ") do
          domain.check_multiple_permissions(@member, [@org_fgp, :read_organization_custom_org_role], @org)
        end
      end

      test "raises unexpected errors" do
        Permissions::Enforcer.stubs(:batch_authorize).raises(StandardError.new("Oh wow that is bad"))
        assert_raises_with_message(StandardError, "Oh wow that is bad") do
          domain.check_multiple_permissions(@member, [@org_fgp, :read_organization_custom_org_role], @org)
        end
      end
    end
  end
end
