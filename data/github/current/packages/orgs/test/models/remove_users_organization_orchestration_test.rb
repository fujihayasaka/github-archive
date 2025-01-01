# typed: true
# frozen_string_literal: true

require "test_helper"

class RemoveUsersOrganizationOrchestrationTest < GitHub::TestCase
  include ApiProgrammaticGrantHelpers

  fixtures do
    @owner = create(:user)
    @second_owner = create(:user)
    @org = create(:organization, :sponsorable, admins: [@owner, @second_owner])
    @user = create(:user)
    @org.add_member(@user)
    @repo = create :private_repository, owner: @org
  end

  test "removes user from org" do
    assert @org.member?(@user)

    perform_enqueued_jobs only: [RevokeOrgMembershipAbilitiesJob] do
      OrganizationOrchestration.remove_users(
        actor: @owner,
        organizations: [@org],
        teams: [],
        users: [@user]
      ).execute(synchronous: true)
    end

    refute @org.reload.member?(@user)
  end

  context "remove_organization_membership_entry step" do
    test "removes OrganizationMembershipEntry records", skip_enterprise: true do
      org_owner = create :emu
      business = org_owner.enterprise_managed_business
      org_member = create :emu, business: business
      org = create :organization, business: business, admin: org_owner
      org.add_member(org_member)
      team = create :team, organization: org

      OrganizationMembershipEntry.create_entry(
        user: org_member,
        organization_id: org.id,
        ability_id: 1,
        derived: true,
        adder_id: team.id,
        adder_type: :enterprise_team
      )

      assert_difference "OrganizationMembershipEntry.count", -1 do
        OrganizationOrchestration.remove_users(
          actor: org_owner,
          organizations: [org],
          teams: [],
          users: [org_member]
        ).execute(synchronous: true)
      end
    end
  end

  context "conceal_member step" do
    test "conceals members" do
      @org.publicize_member(@user)
      assert @org.public_member?(@user)

      OrganizationOrchestration.remove_users(
        actor: @owner,
        organizations: [@org],
        teams: [],
        users: [@user]
      ).execute(synchronous: true)

      refute @org.public_member?(@user)
    end
  end

  context "remove_all_member_requests step" do
    test "removes member feature requests" do
      create(
        :member_feature_request,
        request_entity: @org,
        requester: @user,
        feature: MemberFeatureRequest::Feature::ProtectedBranches
      )
      refute_empty MemberFeatureRequest.where(requester: @user, request_entity: @org)

      OrganizationOrchestration.remove_users(
        actor: @owner,
        organizations: [@org],
        teams: [],
        users: [@user]
      ).execute(synchronous: true)

      assert_empty MemberFeatureRequest.where(requester: @user, request_entity: @org)
    end
  end

  context "cancel_invitations step" do
    test "cancels invitations" do
      create :organization_invitation, \
        :email,
        organization: @org,
        inviter: @second_owner,
        email: "whoever@whatever.lol"
      refute_empty @org.pending_invitations.where(inviter_id: @second_owner.id)

      OrganizationOrchestration.remove_users(
        actor: @owner,
        organizations: [@org],
        teams: [],
        users: [@second_owner]
      ).execute(synchronous: true)

      assert_empty @org.pending_invitations.where(inviter_id: @second_owner.id)
    end
  end

  context "save_organization_settings step" do
    test "marks created restorable as complete" do
      assert_difference("Restorable::OrganizationUser.count", 1) do
        OrganizationOrchestration.remove_users(
          actor: @owner,
          organizations: [@org],
          teams: [],
          users: [@user],
          save_settings: true
        ).execute(synchronous: true)
      end

      organization_user = Restorable::OrganizationUser.first
      assert organization_user.restorable.saved?([:restorable_memberships])
    end
  end

  context "cancel_team_membership_requests step" do
    test "cancels team membership requests" do
      team = create :team, organization: @org, permission: "pull"
      team.request_membership(@user)
      assert_equal 1, team.pending_team_membership_requests.count

      OrganizationOrchestration.remove_users(
        actor: @owner,
        organizations: [@org],
        teams: [],
        users: [@user],
      ).execute(synchronous: true)

      assert_empty team.reload.pending_team_membership_requests
    end
  end

  context "unlink_trade_screening_records step" do
    test "unlinks trade screening records" do
      first_owner = create(:user, :verified)
      second_owner = create(:user, :verified)
      create(:account_screening_profile, owner: second_owner)
      org = create(:organization, admin: second_owner, plan: GitHub::Plan.free)
      org.add_admin(first_owner)

      second_owner.link_trade_screening_record_to_org(organization: org)
      assert second_owner.has_trade_screening_record_linked_to_org?(organization: org)
      refute first_owner.has_trade_screening_record_linked_to_org?(organization: org)

      OrganizationOrchestration.remove_users(
        actor: first_owner,
        organizations: [org],
        teams: [],
        users: [second_owner],
      ).execute(synchronous: true)

      org.reload
      first_owner.reload
      second_owner.reload

      refute first_owner.has_trade_screening_record_linked_to_org?(organization: org)
      refute second_owner.has_trade_screening_record_linked_to_org?(organization: org)
      refute_predicate org, :has_linked_trade_screening_record?
    end

    context "remove_billing_managers step" do
      if GitHub.billing_enabled?
        test "removes billing managers" do
          @org.billing.add_manager(@user, actor: @owner)
          assert @org.reload.billing.manager?(@user)

          OrganizationOrchestration.remove_users(
            actor: @owner,
            organizations: [@org],
            teams: [],
            users: [@user]
          ).execute(synchronous: true)

          refute @org.reload.billing.manager?(@user)
        end
      end
    end

    context "remove_moderators step" do
      if GitHub.organization_moderators_enabled?
        test "removes moderators" do
          @org.moderation.add_moderator(@user, actor: @owner)
          assert @org.reload.moderation.moderator?(@user)

          OrganizationOrchestration.remove_users(
            actor: @owner,
            organizations: [@org],
            teams: [],
            users: [@user]
          ).execute(synchronous: true)

          refute @org.reload.moderation.moderator?(@user)
        end
      end
    end

    context "remove_direct_repo_access step" do
      test "removes direct repo access" do
        @repo.add_member(@user)
        assert @repo.pullable_by?(@user)
        assert @repo.pushable_by?(@user)

        perform_enqueued_jobs only: [RevokeOrgMembershipAbilitiesJob] do
          OrganizationOrchestration.remove_users(
            actor: @owner,
            organizations: [@org],
            teams: [],
            users: [@user]
          ).execute(synchronous: true)
        end

        refute @repo.pullable_by?(@user)
      end
    end

    context "remove_direct_project_access step" do
      test "removes direct project access" do
        project = create :project, owner: @org
        project.update_user_permission(@user, :read)
        assert_includes project.direct_collaborators, @user

        OrganizationOrchestration.remove_users(
          actor: @owner,
          organizations: [@org],
          teams: [],
          users: [@user]
        ).execute(synchronous: true)

        refute_includes project.reload.direct_collaborators, @user
      end
    end

    context "remove_direct_project_next_access step" do
      test "removes direct project next access" do
        org_memex = create(:memex_project, :with_writer, writer: @user, owner: @org)
        another_memex = create(:memex_project, :with_writer, writer: @user)

        assert_equal 2, @user.user_roles.length

        perform_enqueued_jobs(only: [RemoveOrgMemberProjectsNextAccessJob]) do
          OrganizationOrchestration.remove_users(
            actor: @owner,
            organizations: [@org],
            teams: [],
            users: [@user]
          ).execute(synchronous: true)
        end

        assert_equal 1, @user.user_roles.reload.length
        assert_equal another_memex.id, @user.user_roles[0].target_id
      end
    end

    context "remove_users_from_business step" do
      unless GitHub.single_business_environment?
        test "removes users from business" do
          business = create :business, organizations: [@org]

          business.disable_feature(:remove_unaffiliated_users_from_business)
          business.disable_feature(:unaffiliated_user_accounts)
          business.disable_feature(:enterprise_teams_migrate_from_cfb)

          assert business_user_account = business.business_user_account_for(@user)

          OrganizationOrchestration.remove_users(
            actor: @owner,
            organizations: [@org],
            teams: [],
            users: [@user],
            business_id: business.id
          ).execute(synchronous: true)

          refute_includes business.user_accounts, business_user_account
        end
      end
    end

    context "revoke_programmatic_access_grants step" do
      test "removes programmatic access grants" do
        org_pat = make_user_programmatic_access_with_grant(requester: @second_owner, target: @org)
        refute_empty org_pat.organization_programmatic_access_grants

        assert_changes "OrganizationProgrammaticAccessGrant.count", -1 do
          perform_enqueued_jobs only: [RevokeOrgMemberProgrammaticAccessGrantsJob] do
            OrganizationOrchestration.remove_users(
              actor: @owner,
              organizations: [@org],
              teams: [],
              users: [@second_owner],
            ).execute(synchronous: true)
          end
        end

        assert_empty org_pat.organization_programmatic_access_grants
      end
    end

    context "revoke_internal_app_authorizations step" do
      test "revokes internal app authorizations" do
        business = create :business, organizations: [@org]
        app = create(:enterprise_owned_integration, owner: business)
        oauth_access = app.grant(@user)
        assert_equal 1, app.accesses.count
        assert_equal 1, app.authorizations.count

        assert_changes "OauthAuthorization.count", -1 do
          assert_changes "OauthAccess.count", -1 do
            perform_enqueued_jobs only: [RevokeInternalAppAuthorizationsJob] do
              OrganizationOrchestration.remove_users(
                actor: @owner,
                organizations: [@org],
                teams: [],
                users: [@user],
                business_id: business.id
              ).execute(synchronous: true)
            end
          end
        end

        assert_equal 0, app.accesses.count
        assert_equal 0, app.authorizations.count
      end
    end

    context "revoke_org_membership_abilities step" do
      test "revokes org membership abilities" do
        assert @org.direct_or_team_member?(@user)

        perform_enqueued_jobs only: [RevokeOrgMembershipAbilitiesJob] do
          OrganizationOrchestration.remove_users(
            actor: @owner,
            organizations: [@org],
            teams: [],
            users: [@user]
          ).execute(synchronous: true)
        end

        refute @org.direct_or_team_member?(@user)
      end
    end

    context "deny_fork_collab_state_for_user_pull_requests step" do
      test "enqueues DenyForkCollabStateForUserPullRequestsJob job" do
        assert_enqueued_jobs 1, only: DenyForkCollabStateForUserPullRequestsJob, queue: :deny_fork_collab_state do
          assert_enqueued_with \
            job: DenyForkCollabStateForUserPullRequestsJob,
            args: [user_id: @user.id, resource_id: @org.id, resource_class: @org.class.name] do
            OrganizationOrchestration.remove_users(
              actor: @owner,
              organizations: [@org],
              teams: [],
              users: [@user]
            ).execute(synchronous: true)
          end
        end
      end
    end

    context "remove_org_user_email_settings step" do
      test "removes org user email settings" do
        email = "hello@example.com"
        @user.add_email(email).verify!
        GitHub.newsies.get_and_update_settings(@user) do |settings|
          settings.email(@org, email)
        end

        assert_difference "Restorable::CustomEmailRouting.count", 1 do
          OrganizationOrchestration.remove_users(
            actor: @owner,
            organizations: [@org],
            teams: [],
            users: [@user]
          ).execute(synchronous: true)
        end
      end
    end

    context "unlink_saml_identities step" do
      test "unlinks SAML identities" do
        external_identity = create :external_identity
        provider = external_identity.provider
        org = provider.organization
        user = external_identity.user

        assert ExternalIdentity.linked?(provider: provider, user: user)

        assert_difference("org.saml_provider.external_identities.count", -1) do
          OrganizationOrchestration.remove_users(
            actor: org.admin,
            organizations: [org],
            teams: [],
            users: [user]
          ).execute(synchronous: true)
        end

        refute ExternalIdentity.linked?(provider: provider, user: user)
      end
    end

    context "destroy_sponsors_listing_featured_items step" do
      test "destroys sponsors listing featured items" do
        listing = @org.sponsors_listing
        listing.featured_items.create(featureable: @user)
        refute_empty listing.reload.featured_items

        assert_difference -> { SponsorsListingFeaturedItem.count }, -1 do
          OrganizationOrchestration.remove_users(
            actor: @owner,
            organizations: [@org],
            teams: [],
            users: [@user]
          ).execute(synchronous: true)
        end

        assert_empty listing.reload.featured_items
      end
    end

    context "send_email_notification step" do
      test "sends email" do
        OrganizationMailer.expects(:removed_from_org).returns(stub(deliver_later: true)).once

        OrganizationOrchestration.remove_users(
          actor: @owner,
          organizations: [@org],
          teams: [],
          users: [@user]
        ).execute(synchronous: true)
      end
    end

    context "instrument_removal step" do
      test "instruments removal" do
        events = subscribe "org.remove_member"
        reason = Organization::RemovedMemberNotification::TWO_FACTOR_REQUIREMENT_NON_COMPLIANCE

        OrganizationOrchestration.remove_users(
          actor: @owner,
          organizations: [@org],
          teams: [],
          users: [@user],
          reason: reason
        ).execute(synchronous: true)

        expected_payload = {
          user: @user.login,
          user_id: @user.id,
          org: @org.login,
          org_id: @org.id,
          membership_types: ["direct_member"],
          reason: reason,
          actor_id: @owner.id,
          actor: @owner.login,
        }

        assert event = events.pop, "expected an event"
        assert_includes event.payload, :reason
        assert_equal reason, event.payload[:reason]
        assert_equal expected_payload, event.payload
      end
    end

    context "clear_contribution_caches step" do
      test "clears contribution caches" do
        Contribution::Accessor.expects(:clear_cache_for_user).with(@user).once

        OrganizationOrchestration.remove_users(
          actor: @owner,
          organizations: [@org],
          teams: [],
          users: [@user],
        ).execute(synchronous: true)
      end
    end

    context "update_business_license_usage step" do
      unless GitHub.single_business_environment?
        test "enqueues BusinessUpdateLicenseUsageJob" do
          business = create :business, organizations: [@org]

          assert_enqueued_jobs 1, only: BusinessUpdateLicenseUsageJob, queue: :business_update_license_usage do
            OrganizationOrchestration.remove_users(
              actor: @owner,
              organizations: [@org],
              teams: [],
              users: [@user],
              business_id: business.id,
            ).execute(synchronous: true)
          end
        end
      end
    end

    context "destroy_org_restricted_user_status step" do
      test "destroys org restricted user status" do
        status = create(:user_status, user: @user, organization: @org)

        assert_difference "UserStatus.count", -1 do
          OrganizationOrchestration.remove_users(
            actor: @owner,
            organizations: [@org],
            teams: [],
            users: [@user],
          ).execute(synchronous: true)
        end

        refute UserStatus.exists?(status.id)
      end
    end

    context "remove_org_admin_abilities step" do
      test "removes org admin abilities" do
        assert @org.adminable_by?(@second_owner)

        OrganizationOrchestration.remove_users(
          actor: @owner,
          organizations: [@org],
          teams: [],
          users: [@second_owner],
        ).execute(synchronous: true)

        refute @org.adminable_by?(@second_owner)
      end
    end

    context "update_mailchimp step" do
      if GitHub.mailchimp_enabled?
        test "enqueues MailchimpTeamListJob" do
          assert_enqueued_with \
            job: MailchimpTeamListJob,
            args: [user: @user, org: @org] do
            OrganizationOrchestration.remove_users(
              actor: @owner,
              organizations: [@org],
              teams: [],
              users: [@user]
            ).execute(synchronous: true)
          end
        end
      end
    end
  end
end
