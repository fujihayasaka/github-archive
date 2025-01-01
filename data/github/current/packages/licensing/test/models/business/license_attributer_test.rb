# typed: true
# frozen_string_literal: true

require "test_helper"
require "turboghas"

class BusinessLicenseAttributerTest < GitHub::TestCase
  include DogstatsTestHelpers
  include ExternalGroupHelpers

  extend GitHub::FeatureFlagTestHelper

  fixtures do
    @business_admin = create :user, login: "business-admin"
    @business_admin.emails.each(&:verify!)
    @business = create(:business, owners: [@business_admin])
    @business_billing_manager = create :user, login: "business-billing-manager"
    @business_billing_manager.emails.each(&:verify!)
    @business.billing.add_manager(@business_billing_manager, actor: @business_admin)

    @business_invited_admin = create :user, login: "business-invited-admin"
    @business_invited_admin.emails.each(&:verify!)
    @business.invite_admin(user: @business_invited_admin, inviter: @business_admin, role: :owner)

    @business_invited_admin_email = "invited-admin@example.com"
    @business.invite_admin(email: @business_invited_admin_email, inviter: @business_admin, role: :owner)

    @organization_admin = create :user, login: "organization-admin"
    @organization = create(:organization, admin: @organization_admin)
    @business.add_organization @organization

    @other_org_admin = create :user, login: "other-org-admin"
    @other_org = create(:organization, admin: @other_org_admin)
    @business.add_organization @other_org

    @rando = create :user, login: "rando"
    @private_repo = create(:private_repository, owner: @organization)

    @public_repo_member = create :user, login: "public-repo-member"
    @public_repo_invitee = create :user, login: "public-repo-invitee"
    @public_repo_invitee_email = "public-repo-invitee@example.com"
    public_repo = create(:public_repository, owner: @organization)
    public_repo.add_member(@public_repo_member)
    RepositoryInvitation.invite_to_repo @public_repo_invitee, @organization_admin, public_repo
    RepositoryInvitation.invite_to_repo_by_email @public_repo_invitee_email, @organization_admin, public_repo

    @enterprise_installation = create(:enterprise_installation, owner: @business)

    unless GitHub.single_business_environment?
      @emu = create(:emu, :owner)
      @emu_business = @emu.enterprise_managed_business
      @emu2 = create(:emu, :owner, business: @emu_business)
      @emu_business_org = create :enterprise_linked_organization, business: @emu_business, admin: @emu
      @emu_business_org.add_member(@emu2)
      @emu_business_repo = create(:private_repository, owner: @emu_business_org)
    end

    perform_enqueued_jobs only: BusinessUpdateLicenseUsageJob
  end

  setup do
    enable_cache_storage
    reset_cache
    perform_enqueued_jobs only: BusinessUpdateLicenseUsageJob
    @licensed_roles_hash = Business::LicenseAttributer.new(@business).license_usage_hash
    @nonlicensed_roles_hash = Business::LicenseAttributer.new(@business,
      options: { include_nonlicensed_roles: true }).license_usage_hash
    Billing::Platform::Api::Client.any_instance
      .stubs(:get_subscribed_items)
      .returns({ subscribedItems: [] })

    enable_feature_flag(:batch_business_org_abilities)
    disable_feature_flag(:licensing_server_users_from_licensify, @business)
  end

  teardown do
    disable_cache_storage
  end

  def hash_for_user(license_hash, user)
    case user
    when ::User
      license_hash[:users].find { |users| users[:github_com_login] == user.display_login }
    when ::String
      license_hash[:users].find { |users| users[:github_com_login] == user }
    end
  end

  def add_variety_of_users_to_business
    # Standard user
    @organization.add_member(create(:user))

    # Invited user
    @organization.invite(create(:user), inviter: @organization_admin)

    # Invited user by email
    @organization.invite(email: "variety_org_invite@example.com", inviter: @organization_admin)

    # Repository invitation
    RepositoryInvitation.invite_to_repo create(:user), @organization_admin, @private_repo

    # Repository invitatin by email
    RepositoryInvitation.invite_to_repo_by_email "variety_repo_invite@example.com", @organization_admin, @private_repo

    # Outside collaborators
    @private_repo.add_member(create(:user))

    # User based business user account
    create(:business_user_account, business: @business, user: create(:user), roles: [:server_member])

    # Email based business user account with blank login
    create(:business_user_account, business: @business, user: nil, login: "", roles: [:server_member]).tap do |business_user_account|
      enterprise_installation_user_account = create(
        :enterprise_installation_user_account,
        enterprise_installation: @enterprise_installation,
        business_user_account: business_user_account
      )
      create(
        :enterprise_installation_user_account_email,
        enterprise_installation_user_account: enterprise_installation_user_account,
        email: "example@example.com",
        primary: true,
      )
    end

    # GHES-only user with different primary email addresses on different instances
    ghes_user2_email = "variety-ghes-user2@example.com"
    ghes_user2_email2 = "variety-a-ghes-user2@example.com"
    ghes_user2_act = create :enterprise_installation_user_account,
      enterprise_installation: @enterprise_installation

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ghes_user2_act,
      email: ghes_user2_email, primary: true

    ghes_user2_bus_act = create :business_user_account, business: @business, user: nil,
      enterprise_installation_user_accounts: [ghes_user2_act],
      login: ghes_user2_email, roles: [:server_member]

    enterprise_installation2 = create(:enterprise_installation, owner: @business)
    ghes_user2_act2 = create :enterprise_installation_user_account,
      enterprise_installation: enterprise_installation2,
      site_admin: true,
      business_user_account: ghes_user2_bus_act

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ghes_user2_act2,
      email: ghes_user2_email2, primary: true

    # Email based business user account with populated login
    create(:business_user_account, business: @business, user: nil, login: "variety_email_bua", roles: [:server_member]).tap do |business_user_account|
      enterprise_installation_user_account = create(
        :enterprise_installation_user_account,
        enterprise_installation: @enterprise_installation,
        business_user_account: business_user_account
      )
      create(
        :enterprise_installation_user_account_email,
        enterprise_installation_user_account: enterprise_installation_user_account,
        email: "variety_email_bua@example.com",
        primary: true,
      )
    end

    # Business user account with blank login and no emails
    create(:business_user_account, business: @business, user: nil, login: "", roles: [:server_member]).tap do |business_user_account|
      create(
        :enterprise_installation_user_account,
        enterprise_installation: @enterprise_installation,
        business_user_account: business_user_account
      )
    end

    # Business user account with populated login and no emails
    create(:business_user_account, business: @business, user: nil, login: "variety_no_email_bua", roles: [:server_member]).tap do |business_user_account|
      create(
        :enterprise_installation_user_account,
        enterprise_installation: @enterprise_installation,
        business_user_account: business_user_account
      )
    end

    # Business user account with only secondary email
    create(:business_user_account, business: @business, user: nil, roles: [:server_member]).tap do |business_user_account|
      enterprise_installation_user_account = create(
        :enterprise_installation_user_account,
        enterprise_installation: @enterprise_installation,
        business_user_account: business_user_account
      )
      create(
        :enterprise_installation_user_account_email,
        enterprise_installation_user_account: enterprise_installation_user_account,
        email: "example@example.com",
        primary: false
      )
    end

    # Bundled license assignments
    create(:enterprise_agreement, :visual_studio_bundle, business: @business)

    # Assignment without user
    create(:licensing_bundled_license_assignment, business: @business, user: nil, email: "variety_assignment_wo_user@example.com")

    # User assignment
    create(:licensing_bundled_license_assignment, business: @business, user: create(:user), email: "variety_assignment_user@example.com")

    # Revoked assignment
    create(:licensing_bundled_license_assignment, business: @business, user: nil, email: "variety_assignment_revoked@example.com", revoked: true)

    perform_enqueued_jobs only: BusinessUpdateLicenseUsageJob
  end

  # Clear the cache of the attributer
  def fresh_attributer(include_nonlicensed_roles: false)
    @business = Business.find(@business.id)
    Business::LicenseAttributer.new(@business, options: { include_nonlicensed_roles: include_nonlicensed_roles })
  end

  context "#user_ids" do
    context "business admins" do
      test "does not include business admins if they aren't explicitly added to an organization or a GHES user" do
        refute_includes Business::LicenseAttributer.new(@business).user_ids, @business_admin.id
      end

      test "includes business admins if they are explicitly added to an organization" do
        perform_enqueued_jobs(only: [BusinessUpdateLicenseUsageJob]) do
          @organization.add_member(@business_admin)
        end

        @business = Business.find @business.id
        assert_includes Business::LicenseAttributer.new(@business).user_ids, @business_admin.id
      end

      test "includes business admins if they are explicitly invited to an organization" do
        perform_enqueued_jobs(only: [BusinessUpdateLicenseUsageJob]) do
          @organization.invite(@business_admin, inviter: @organization_admin)
        end

        @business = Business.find @business.id
        assert_includes Business::LicenseAttributer.new(@business).user_ids, @business_admin.id
      end

      test "includes business admins if they are explitly added as an outside collaborator on a private repository owned by a controlled organization" do
        perform_enqueued_jobs(only: [BusinessUpdateLicenseUsageJob]) do
          @private_repo.add_member(@business_admin)
        end

        @business = Business.find @business.id
        assert_includes Business::LicenseAttributer.new(@business).user_ids, @business_admin.id
      end

      test "includes business admins if they are explitly invited as an outside collaborator on a private repository owned by a controlled organization" do
        perform_enqueued_jobs(only: [BusinessUpdateLicenseUsageJob]) do
          RepositoryInvitation.invite_to_repo @business_admin, @organization_admin, @private_repo
        end

        @business = Business.find @business.id
        assert_includes Business::LicenseAttributer.new(@business).user_ids, @business_admin.id
      end

      test "includes business admins if they are a GHES user" do
        business_user_account = @business_admin.business_user_accounts.find_by!(business: @business)
        enterprise_installation_user_account = create(
          :enterprise_installation_user_account,
          enterprise_installation: @enterprise_installation,
          business_user_account: business_user_account,
        )
        create(
          :enterprise_installation_user_account_email,
          enterprise_installation_user_account: enterprise_installation_user_account,
          email: @business_admin.email,
          primary: true,
        )
        perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)

        @business = Business.find @business.id
        assert_includes Business::LicenseAttributer.new(@business).user_ids, @business_admin.id
      end

      unless GitHub.single_business_environment?
        test "includes guest collaborators if they are added to emu team" do
          disable_feature_flag(:disable_external_group_team_reconcile_job)

          business = create(:business, :enterprise_managed)
          guest_collaborator = create(:emu, :guest_collaborator, business: business)
          external_group = create(:external_group, :with_members, :with_team, business: business).reload
          team = external_group.external_group_teams.first.team

          refute_includes Business::LicenseAttributer.new(business).user_ids, guest_collaborator.id

          perform_enqueued_jobs(only: [BusinessUpdateLicenseUsageJob]) do
            team.add_member(guest_collaborator)
            ExternalIdentityGroupMembership.create(external_group: external_group, external_identity: guest_collaborator.external_identities.first)
            reconcile_external_group_teams(external_group: external_group)
          end

          business = Business.find(business.id)
          assert_includes Business::LicenseAttributer.new(business).user_ids, guest_collaborator.id
        end

        test "guest collaborators license query counts stay the same" do
          disable_feature_flag(:disable_external_group_team_reconcile_job)

          business = create(:business, :enterprise_managed)
          organization_admin = create :emu, business: business
          organization = create :organization, business: business, admin: organization_admin
          team = create :team, organization: organization
          external_group = create :external_group, :with_members, business: business, number_of_members: 1
          external_group_team = ExternalGroupTeam.create(external_group: external_group, team: team)
          ExternalGroupTeamLinkJob.perform_now(external_group_team.id, caller: self.class.name)

          guest_collaborator = create(:emu, :guest_collaborator, business: business)

          perform_enqueued_jobs(only: [BusinessUpdateLicenseUsageJob]) do
            team.add_member(guest_collaborator)
            ExternalIdentityGroupMembership.create(external_group: external_group, external_identity: guest_collaborator.external_identities.first)
            reconcile_external_group_teams(external_group: external_group)
          end

          assert_query_count(4, ignore_feature_flags: true) do
            Business::LicenseAttributer.new(business).user_ids
          end
        end
      end
    end

    context "business billing managers" do
      test "does not include business billing managers if they aren't explicitly added to an organization or a GHES user" do
        refute_includes Business::LicenseAttributer.new(@business).user_ids, @business_billing_manager.id
      end

      test "includes business billing managers if they are explicitly added to an organization" do
        @organization.add_member(@business_billing_manager)

        assert_includes Business::LicenseAttributer.new(@business).user_ids, @business_billing_manager.id
      end

      test "includes business billing managers if they are explicitly invited to an organization" do
        @organization.invite(@business_billing_manager, inviter: @organization_admin)

        assert_includes Business::LicenseAttributer.new(@business).user_ids, @business_billing_manager.id
      end

      test "includes business billing managers if they are explitly added as an outside collaborator on a private repository owned by a controlled organization" do
        perform_enqueued_jobs(only: [BusinessUpdateLicenseUsageJob]) do
          @private_repo.add_member(@business_billing_manager)
        end

        @business = Business.find @business.id
        assert_includes Business::LicenseAttributer.new(@business).user_ids, @business_billing_manager.id
      end

      test "includes business billing managers if they are explitly invited as an outside collaborator on a private repository owned by a controlled organization" do
        RepositoryInvitation.invite_to_repo @business_billing_manager, @organization_admin, @private_repo

        @business = Business.find @business.id
        assert_includes Business::LicenseAttributer.new(@business).user_ids, @business_billing_manager.id
      end

      test "includes business billing managers if they are a GHES user" do
        perform_enqueued_jobs(only: [BusinessUpdateLicenseUsageJob]) do
          business_user_account = @business_billing_manager.business_user_accounts.find_by!(business: @business)
          enterprise_installation_user_account = create(
            :enterprise_installation_user_account,
            enterprise_installation: @enterprise_installation,
            business_user_account: business_user_account,
          )
          create(
            :enterprise_installation_user_account_email,
            enterprise_installation_user_account: enterprise_installation_user_account,
            email: @business_billing_manager.email,
            primary: true,
          )
        end

        @business = Business.find @business.id
        assert_includes Business::LicenseAttributer.new(@business).user_ids, @business_billing_manager.id
      end
    end

    context "organizations" do
      test "includes the IDs of members of organizations" do
        user = create(:user)
        @organization.add_member user

        assert_includes Business::LicenseAttributer.new(@business).user_ids, user.id
      end

      test "includes the IDs of users with pending invites to organizations" do
        user = create(:user)
        @organization.invite(user, inviter: @organization_admin)

        assert_includes Business::LicenseAttributer.new(@business).user_ids, user.id
      end

      test "does not include IDs of users with pending invites to organizations when the business has metered GHE" do
        @business.customer.update(metered_plan: true)
        user = create(:user)
        @organization.invite(user, inviter: @organization_admin)

        refute_includes Business::LicenseAttributer.new(@business).user_ids, user.id
      end
    end

    context "outside collaborators (private repositories owned by a member organization)" do
      test "only includes the IDs of outside collaborators on private repositories" do
        private_repo_member = create :user
        perform_enqueued_jobs(only: [BusinessUpdateLicenseUsageJob]) do
          @private_repo.add_member(private_repo_member)
        end
        public_repo_member = create :user
        public_repo = create(:public_repository, owner: @organization)
        perform_enqueued_jobs(only: [BusinessUpdateLicenseUsageJob]) do
          public_repo.add_member(public_repo_member)
        end

        @business = Business.find @business.id
        assert_includes Business::LicenseAttributer.new(@business).user_ids, private_repo_member.id
        refute_includes Business::LicenseAttributer.new(@business).user_ids, public_repo_member.id
      end

      test "only includes the IDs of users invited to private repositories" do
        private_repo_invitee = create :user
        RepositoryInvitation.invite_to_repo private_repo_invitee, @organization_admin, @private_repo
        public_repo_invitee = create :user
        public_repo = create(:public_repository, owner: @organization)
        RepositoryInvitation.invite_to_repo public_repo_invitee, @organization_admin, public_repo

        assert_includes Business::LicenseAttributer.new(@business).user_ids, private_repo_invitee.id
        refute_includes Business::LicenseAttributer.new(@business).user_ids, public_repo_invitee.id
      end

      test "does not include the IDs of outside collaborator invites when the business has metered GHE" do
        @business.customer.update(metered_plan: true)
        private_repo_invitee = create :user
        RepositoryInvitation.invite_to_repo private_repo_invitee, @organization_admin, @private_repo
        public_repo_invitee = create :user
        public_repo = create(:public_repository, owner: @organization)
        RepositoryInvitation.invite_to_repo public_repo_invitee, @organization_admin, public_repo

        refute_includes Business::LicenseAttributer.new(@business).user_ids, private_repo_invitee.id
        refute_includes Business::LicenseAttributer.new(@business).user_ids, public_repo_invitee.id
      end
    end

    context "enterprise installation user accounts (AKA GHES users)" do
      test "includes ID of user with matching verfied email address to a GHES user when the user already has an association with the business" do
        email = "example@example.com"
        user = create(:user, :verified, email: email)
        @organization.add_member user
        business_user_account = user.business_user_accounts.find_by!(business: @business)
        enterprise_installation_user_account = create(
          :enterprise_installation_user_account,
          enterprise_installation: @enterprise_installation,
          business_user_account: business_user_account,
        )
        create(
          :enterprise_installation_user_account_email,
          enterprise_installation_user_account: enterprise_installation_user_account,
          email: email,
          primary: true,
        )

        assert_includes Business::LicenseAttributer.new(@business).user_ids, user.id
      end

      test "does not include the ID of the user with matching verified email address to a GHES user if the user has no association with the business" do
        email = "example@example.com"
        user = create(:user, :verified, email: email)
        enterprise_installation_user_account = create(
          :enterprise_installation_user_account,
          enterprise_installation: @enterprise_installation,
        )
        create(
          :enterprise_installation_user_account_email,
          enterprise_installation_user_account: enterprise_installation_user_account,
          email: email,
          primary: true,
        )

        refute_includes Business::LicenseAttributer.new(@business).user_ids, user.id
      end
    end

    context "bundled license assignments" do
      test "includes non-revoked bundled license assignments that are linked to users when volume licensing is enabled" do
        create(:enterprise_agreement, :visual_studio_bundle, business: @business)

        assignment = create(:licensing_bundled_license_assignment, business: @business, user: create(:user))
        _email_assignment = create(:licensing_bundled_license_assignment, business: @business, user: nil, email: "something@example.com")
        revoked_assignment = create(:licensing_bundled_license_assignment, business: @business, user: create(:user), revoked: true)

        attributer = Business::LicenseAttributer.new(@business)
        assert_includes attributer.user_ids, assignment.user_id
        refute_includes attributer.user_ids, revoked_assignment.user_id
        refute_includes attributer.user_ids, nil
      end

      test "does not include bundled license assignments when volume licensing is disabled" do
        assignment = create(:licensing_bundled_license_assignment, business: @business, user: create(:user))

        refute_includes Business::LicenseAttributer.new(@business).user_ids, assignment.user_id
      end

      test "includes bundled license assignments when volume licensing is enabled" do
        create(:enterprise_agreement, :visual_studio_bundle, business: @business)

        assignment = create(:licensing_bundled_license_assignment, business: @business, user: create(:user))

        assert_includes Business::LicenseAttributer.new(@business).user_ids, assignment.user_id
      end
    end

    context "expired invitations" do
      test "does not include user associated via an expired organization invitation" do
        invitee = create(:user)
        travel_to (GitHub.invitation_expiry_period + 1).days.ago do
          @organization.invite(invitee, inviter: @organization_admin)
        end

        refute_includes Business::LicenseAttributer.new(@business).user_ids, invitee.id
      end

      test "does not include user associated via an expired repository invitation" do
        invitee = create(:user)
        travel_to (GitHub.invitation_expiry_period + 1).days.ago do
          RepositoryInvitation.invite_to_repo invitee, @organization_admin, @private_repo
        end

        refute_includes Business::LicenseAttributer.new(@business).user_ids, invitee.id
      end
    end
  end

  context "#business_organization_member_ids" do
    test "uses Licensify on metered plan" do
      @business.customer.update(metered_plan: true)

      ::Licensify::Client.any_instance.expects(:get_licensee_ids)
         .with(Licensify::Services::V1::GetLicenseeIdsRequest.new(
           customerId: T.must(@business.customer.id),
           product: Licensify::Services::V1::Product::PRODUCT_SDLC,
           enablementReasons: [Licensify::Services::V1::EnablementReason::ENABLEMENT_REASON_ORG_MEMBERSHIP]
         ))
         .returns(Twirp::ClientResp.new(
           data: ::Licensify::Services::V1::GetLicenseeIdsResponse.new(licenseeIds: %w(123, 567)),
           error: nil,
         )).once

      assert_equal Business::LicenseAttributer.new(@business).business_organization_member_ids, [123, 567]
    end

    test "tracks the distribution time" do
      @business.customer.update(metered_plan: true)

      Business::LicenseAttributer.new(@business).business_organization_member_ids

      assert_dogstats_distribution "business_license_attributer.business_organization_member_ids.time", tags: ["gh.licensing.platform:default"]
    end
  end

  context "#consumed_enterprise_licenses" do
    test "returns count from licensify when flag licensing_server_users_from_licensify is on" do
      @business.customer.update(metered_plan: true)
      enable_feature_flag(:licensing_server_users_from_licensify, @business)

      ::Licensify::Client.any_instance.expects(:get_licensee_ids)
        .with(Licensify::Services::V1::GetLicenseeIdsRequest.new(
          customerId: T.must(@business.customer.id),
          product: Licensify::Services::V1::Product::PRODUCT_SDLC,
          enablementReasons: [
            Licensify::Services::V1::EnablementReason::ENABLEMENT_REASON_ORG_MEMBERSHIP,
            Licensify::Services::V1::EnablementReason::ENABLEMENT_REASON_REPOSITORY_COLLABORATOR,
            Licensify::Services::V1::EnablementReason::ENABLEMENT_REASON_ENTERPRISE_SERVER_USER,
          ]
        ))
        .returns(Twirp::ClientResp.new(
          data: ::Licensify::Services::V1::GetLicenseeIdsResponse.new(licenseeIds: %w(123, 567, 890)),
          error: nil,
        )).once

      assert_equal Business::LicenseAttributer.new(@business).consumed_enterprise_licenses, 3
    end
  end

  context "#business_private_outside_repo_collaborator_ids_licensify" do
    test "returns outside repo collaborator id when licensee is not a member of the repo's org" do
      @business.customer.update(metered_plan: true)

      user_id = 999
      repo_id = 1
      repo_org_id = 2
      non_repo_org_id = 3

      collaborator_license = Licensify::Services::V1::CustomerLicense.new(
        licensee: Licensify::Services::V1::Licensee.new(
          type: Licensify::Services::V1::LicenseeType::LICENSEE_TYPE_USER,
          id: user_id.to_s
        ),
        enablements: [
          Licensify::Services::V1::CustomerLicenseEnablement.new(
            reason: Licensify::Services::V1::EnablementReason::ENABLEMENT_REASON_REPOSITORY_COLLABORATOR,
            enablementIds: [repo_id.to_s] # Repository ID
          ),
          Licensify::Services::V1::CustomerLicenseEnablement.new(
            reason: Licensify::Services::V1::EnablementReason::ENABLEMENT_REASON_ORG_MEMBERSHIP,
            enablementIds: [non_repo_org_id.to_s] # Organization ID but NOT the repo's org
          )
        ]
      )

      ::Licensify::Client.any_instance.expects(:get_customer_licenses)
        .with(Licensify::Services::V1::GetCustomerLicensesRequest.new(
          customerId: T.must(@business.customer.id),
          product: Licensify::Services::V1::Product::PRODUCT_SDLC,
        ))
        .returns(Twirp::ClientResp.new(
          data: { "customerLicenses" => [collaborator_license] },
          error: nil,
        )).once

      Repository.expects(:where).with(id: [repo_id]).returns([Repository.new(id: repo_id, organization_id: repo_org_id)]).once

      assert_equal [user_id], Business::LicenseAttributer.new(@business).business_private_outside_repo_collaborator_ids_licensify_for_csv_generation_only
    end

    test "returns no outside repo collaborator id when licensee is a member of the repo's org" do
      @business.customer.update(metered_plan: true)

      user_id = 999
      repo_id = 1
      repo_org_id = 2

      collaborator_license = Licensify::Services::V1::CustomerLicense.new(
        licensee: Licensify::Services::V1::Licensee.new(
          type: Licensify::Services::V1::LicenseeType::LICENSEE_TYPE_USER,
          id: user_id.to_s
        ),
        enablements: [
          Licensify::Services::V1::CustomerLicenseEnablement.new(
            reason: Licensify::Services::V1::EnablementReason::ENABLEMENT_REASON_REPOSITORY_COLLABORATOR,
            enablementIds: [repo_id.to_s] # Repository ID
          ),
          Licensify::Services::V1::CustomerLicenseEnablement.new(
            reason: Licensify::Services::V1::EnablementReason::ENABLEMENT_REASON_ORG_MEMBERSHIP,
            enablementIds: [repo_org_id.to_s] # Organization ID
          )
        ]
      )

      ::Licensify::Client.any_instance.expects(:get_customer_licenses)
        .with(Licensify::Services::V1::GetCustomerLicensesRequest.new(
          customerId: T.must(@business.customer.id),
          product: Licensify::Services::V1::Product::PRODUCT_SDLC,
        ))
        .returns(Twirp::ClientResp.new(
          data: { "customerLicenses" => [collaborator_license] },
          error: nil,
        )).once

      Repository.expects(:where).with(id: [repo_id]).returns([Repository.new(id: repo_id, organization_id: repo_org_id)]).once

      assert_equal [], Business::LicenseAttributer.new(@business).business_private_outside_repo_collaborator_ids_licensify_for_csv_generation_only
    end
  end

  context "#business_org_member_and_private_outside_collaborator_ids" do
    test "uses Licensify on metered plan" do
      @business.customer.update(metered_plan: true)

      ::Licensify::Client.any_instance.expects(:get_licensee_ids)
        .with(Licensify::Services::V1::GetLicenseeIdsRequest.new(
          customerId: T.must(@business.customer.id),
          product: Licensify::Services::V1::Product::PRODUCT_SDLC,
          enablementReasons: [
            Licensify::Services::V1::EnablementReason::ENABLEMENT_REASON_ORG_MEMBERSHIP,
            Licensify::Services::V1::EnablementReason::ENABLEMENT_REASON_REPOSITORY_COLLABORATOR,
          ]
        ))
        .returns(Twirp::ClientResp.new(
          data: ::Licensify::Services::V1::GetLicenseeIdsResponse.new(licenseeIds: %w(123 567)),
          error: nil,
        )).once

      assert_equal Business::LicenseAttributer.new(@business).business_org_member_and_private_outside_collaborator_ids, [123, 567]
    end

    test "filters out and warns if Licensify returns a non-numeric id" do
      @business.customer.update(metered_plan: true)

      ::Licensify::Client.any_instance.expects(:get_licensee_ids)
        .with(Licensify::Services::V1::GetLicenseeIdsRequest.new(
          customerId: T.must(@business.customer.id),
          product: Licensify::Services::V1::Product::PRODUCT_SDLC,
          enablementReasons: [
            Licensify::Services::V1::EnablementReason::ENABLEMENT_REASON_ORG_MEMBERSHIP,
            Licensify::Services::V1::EnablementReason::ENABLEMENT_REASON_REPOSITORY_COLLABORATOR,
          ]
        ))
        .returns(Twirp::ClientResp.new(
          data: ::Licensify::Services::V1::GetLicenseeIdsResponse.new(licenseeIds: %w(123 abcdef)),
          error: nil,
        )).once

      GitHub.logger.expects(:warn).with(
        "Filtered out unexpected non-numeric licensee ID: \"abcdef\" (String)",
        {
          "code.namespace": "Business::LicenseAttributer",
          "code.function": :business_org_member_and_private_outside_collaborator_ids_licensify,
          "gh.business.id": @business.id,
          "gh.customer.id": @business.customer_id,
        }
      )

      assert_equal Business::LicenseAttributer.new(@business).business_org_member_and_private_outside_collaborator_ids, [123]
    end

    test "tracks the distribution time" do
      @business.customer.update(metered_plan: true)

      Business::LicenseAttributer.new(@business).business_org_member_and_private_outside_collaborator_ids

      assert_dogstats_distribution "business_license_attributer.business_org_member_and_private_outside_collaborator_ids.time", tags: ["gh.licensing.platform:default"]
    end
  end

  context "#emails" do
    test "includes emails for pending organization invitations" do
      email = "invited@example.com"
      @organization.invite(email: email, inviter: @organization_admin)

      assert_includes Business::LicenseAttributer.new(@business).emails, email
    end

    test "only includes the emails invited to private repositories" do
      private_repo_email = "private@example.com"
      RepositoryInvitation.invite_to_repo_by_email private_repo_email, @organization_admin, @private_repo
      public_repo_email = "public@example.com"
      public_repo = create(:public_repository, owner: @organization)
      RepositoryInvitation.invite_to_repo_by_email public_repo_email, @organization_admin, public_repo

      assert_includes Business::LicenseAttributer.new(@business).emails, private_repo_email
      refute_includes Business::LicenseAttributer.new(@business).emails, public_repo_email
    end

    test "includes primary enterprise installation user emails if there's not a verified user email for that email" do
      primary_email = "primary@example.com"
      secondary_email = "secondary@example.com"
      business_user_account = create(:business_user_account, business: @business, user: nil, login: "bogus-data", roles: [:server_member])
      enterprise_installation_user_account = create(
        :enterprise_installation_user_account,
        enterprise_installation: @enterprise_installation,
        business_user_account: business_user_account,
      )
      create(
        :enterprise_installation_user_account_email,
        enterprise_installation_user_account: enterprise_installation_user_account,
        email: primary_email,
        primary: true,
      )
      create(
        :enterprise_installation_user_account_email,
        enterprise_installation_user_account: enterprise_installation_user_account,
        email: secondary_email,
        primary: false,
      )
      create(:user, email: primary_email)

      assert_includes Business::LicenseAttributer.new(@business).emails, primary_email
      refute_includes Business::LicenseAttributer.new(@business).emails, secondary_email
      refute_includes Business::LicenseAttributer.new(@business).emails, business_user_account.display_login
    end

    test "includes primary enterprise installation user emails if there's a verified user email for that email, and the user that owns the email doesn't have a business user account" do
      email = "example@example.com"
      _user = create(:user, :verified, email: email)
      business_user_account = create(:business_user_account, business: @business, user: nil, roles: [:server_member])
      enterprise_installation_user_account = create(
        :enterprise_installation_user_account,
        enterprise_installation: @enterprise_installation,
        business_user_account: business_user_account,
      )
      create(
        :enterprise_installation_user_account_email,
        enterprise_installation_user_account: enterprise_installation_user_account,
        email: email,
        primary: true,
      )

      assert_includes Business::LicenseAttributer.new(@business).emails, email
    end

    test "does not include primary enterprise installation user emails if there's a verified user email for that email, but the user that owns the email has a business user account" do
      email = "example@example.com"
      user = create(:user, :verified, email: email)
      business_user_account = create(:business_user_account, business: @business, user: user, roles: [:server_member])
      enterprise_installation_user_account = create(
        :enterprise_installation_user_account,
        enterprise_installation: @enterprise_installation,
        business_user_account: business_user_account,
      )
      create(
        :enterprise_installation_user_account_email,
        enterprise_installation_user_account: enterprise_installation_user_account,
        email: email,
        primary: true,
      )

      refute_includes Business::LicenseAttributer.new(@business).emails, email
    end

    test "does not include non-primary enterprise installation user emails if there's not a verified user email for that email" do
      secondary_email = "secondary@example.com"
      business_user_account = create(:business_user_account, business: @business, user: nil, roles: [:server_member])
      enterprise_installation_user_account = create(
        :enterprise_installation_user_account,
        enterprise_installation: @enterprise_installation,
        business_user_account: business_user_account,
      )
      create(
        :enterprise_installation_user_account_email,
        enterprise_installation_user_account: enterprise_installation_user_account,
        email: secondary_email,
        primary: false,
      )

      refute_includes Business::LicenseAttributer.new(@business).emails, secondary_email
    end

    test "does not include duplicates (even if the casing is different)" do
      email = "INVITED@example.com"
      @organization.invite(email: email, inviter: @organization_admin)
      RepositoryInvitation.invite_to_repo_by_email email.titleize, @organization_admin, @private_repo

      assert_equal [email.downcase].to_set, Business::LicenseAttributer.new(@business).emails
    end

    test "does not include emails for users that are already a member of another organization under the business" do
      @organization2 = create(:organization)
      @organization2_admin = @organization2.admins.first
      @business.add_organization(@organization2)

      email = "example@example.com"
      user = create(:user, :verified, email: email)
      @organization.add_member(user)
      @organization2.invite(email: email, inviter: @organization2_admin)

      refute_includes Business::LicenseAttributer.new(@business).emails, email
    end

    test "does not include emails for pending organization invites when business has metered GHE" do
      @business.customer.update(metered_plan: true)
      email = "invited@example.com"
      @organization.invite(email: email, inviter: @organization_admin)

      refute_includes Business::LicenseAttributer.new(@business).emails, email
    end

    test "does not include emails for pending collaborator invites when business has metered GHE" do
      @business.customer.update(metered_plan: true)
      private_repo_email = "private@example.com"
      RepositoryInvitation.invite_to_repo_by_email private_repo_email, @organization_admin, @private_repo
      public_repo_email = "public@example.com"
      public_repo = create(:public_repository, owner: @organization)
      RepositoryInvitation.invite_to_repo_by_email public_repo_email, @organization_admin, public_repo

      refute_includes Business::LicenseAttributer.new(@business).emails, private_repo_email
      refute_includes Business::LicenseAttributer.new(@business).emails, public_repo_email
    end

    context "bundled license assignments" do
      test "includes non-revoked bundled license assignments that are linked to users when volume licensing is enabled" do
        create(:enterprise_agreement, :visual_studio_bundle, business: @business)

        assignment = create(:licensing_bundled_license_assignment, business: @business, user: nil, email: "assignment@example.com")
        user_assignment = create(:licensing_bundled_license_assignment, business: @business, user: create(:user), email: "user@example.com")
        revoked_assignment = create(:licensing_bundled_license_assignment, business: @business, user: nil, email: "revoked@example.com", revoked: true)

        attributer = Business::LicenseAttributer.new(@business)
        assert_includes attributer.emails, assignment.email
        refute_includes attributer.emails, user_assignment.email
        refute_includes attributer.emails, revoked_assignment.email
      end

      test "does not include bundled license assignments when volume licensing is disabled" do
        assignment = create(:licensing_bundled_license_assignment, business: @business, user: nil, email: "assignment@example.com")

        refute_includes Business::LicenseAttributer.new(@business).emails, assignment.email
      end

      test "includes bundled license assignments when volume licensing is enabled" do
        create(:enterprise_agreement, :visual_studio_bundle, business: @business)

        assignment = create(:licensing_bundled_license_assignment, business: @business, user: nil, email: "assignment@example.com")

        assert_includes Business::LicenseAttributer.new(@business).emails, assignment.email
      end
    end

    context "expired invitations" do
      test "does not include email associated via an expired organization invitation" do
        invitee_email = "invitee@example.com"
        travel_to (GitHub.invitation_expiry_period + 1).days.ago do
          @organization.invite(email: invitee_email, inviter: @organization_admin)
        end

        refute_includes Business::LicenseAttributer.new(@business).emails, invitee_email
      end

      test "does not include email associated via an expired repository invitation" do
        invitee_email = "invitee@example.com"
        travel_to (GitHub.invitation_expiry_period + 1).days.ago do
          RepositoryInvitation.invite_to_repo_by_email invitee_email, @organization_admin, @private_repo
        end

        refute_includes Business::LicenseAttributer.new(@business).emails, invitee_email
      end
    end
  end

  context "#users_with_business_access" do
    test "includes org owners consuming licenses" do
      expected = [
        @organization_admin.id,
        @other_org_admin.id
      ].to_set
      assert_equal expected, Business::LicenseAttributer.new(@business).users_with_business_access[:user_ids]
    end

    test "includes org members consuming licenses" do
      perform_enqueued_jobs(only: [BusinessUpdateLicenseUsageJob]) do
        @organization.add_member(@rando)
      end

      @business = Business.find @business.id
      assert_includes Business::LicenseAttributer.new(@business).users_with_business_access[:user_ids],
        @rando.id
    end

    test "includes collaborators consuming licenses" do
      collaborator = create :user
      perform_enqueued_jobs(only: [BusinessUpdateLicenseUsageJob]) do
        @private_repo.add_member(collaborator)
      end

      @business = Business.find @business.id
      assert_includes Business::LicenseAttributer.new(@business).users_with_business_access[:user_ids],
        collaborator.id
    end

    test "includes repository collaborators consuming licenses" do
      enable_feature_flag(:repository_collaborators_for_emu, @emu_business)
      emu_collaborator = create(:emu, business: @emu_business)

      refute_includes Business::LicenseAttributer.new(@emu_business.reload).user_ids, emu_collaborator.id
      perform_enqueued_jobs(only: [BusinessUpdateLicenseUsageJob]) do
        @emu_business_repo.add_member(emu_collaborator)
      end

      assert_includes Business::LicenseAttributer.new(@emu_business.reload).users_with_business_access[:user_ids], emu_collaborator.id
    end

    test "does not include public collaborators who do not consume a license" do
      refute_includes Business::LicenseAttributer.new(@business).users_with_business_access[:user_ids],
        @public_repo_member.id
    end

    test "does not include invitations even if they consume a license" do
      private_invitee = create :user
      RepositoryInvitation.invite_to_repo private_invitee, @organization_admin, @private_repo

      attributer = Business::LicenseAttributer.new(@business)

      # Verify the user does consume a license
      assert_includes attributer.user_ids, private_invitee.id

      # Verify this user is not included in the list of users with access consuming licenses
      refute_includes attributer.users_with_business_access[:user_ids], private_invitee.id
    end

    test "includes enterprise installation accounts without a user" do
      primary_email = "primary@example.com"
      # enterprise server user with no connected cloud account
      bua1 = create(:business_user_account, business: @business, user: nil, login: primary_email, roles: [:server_member])
      business_installation = create(:enterprise_installation, owner: @business)
      enterprise_installation_user_account = create(
        :enterprise_installation_user_account,
        enterprise_installation: business_installation,
        business_user_account: bua1,
      )
      create(
        :enterprise_installation_user_account_email,
        enterprise_installation_user_account: enterprise_installation_user_account,
        email: primary_email,
        primary: true,
      )

      assert_includes Business::LicenseAttributer.new(@business).users_with_business_access[:emails], primary_email
    end

    test "includes unidentified business user accounts" do
      business_user_account_with_blank_login_and_no_emails = create(:business_user_account, business: @business, user: nil, login: "", roles: [:server_member]).tap do |business_user_account|
        create(
          :enterprise_installation_user_account,
          enterprise_installation: @enterprise_installation,
          business_user_account: business_user_account
        )
      end
      business_user_account_with_populated_login_and_no_emails = create(:business_user_account, business: @business, user: nil, login: "nonsense", roles: [:server_member]).tap do |business_user_account|
        create(
          :enterprise_installation_user_account,
          enterprise_installation: @enterprise_installation,
          business_user_account: business_user_account
        )
      end
      user_based_business_user_account = create(:business_user_account, business: @business, user: create(:user), roles: [:server_member])

      ubua_ids = Business::LicenseAttributer.new(@business).users_with_business_access[:unidentified_business_user_account_ids]

      assert_includes ubua_ids, business_user_account_with_blank_login_and_no_emails.id
      assert_includes ubua_ids, business_user_account_with_populated_login_and_no_emails.id
      refute_includes ubua_ids, user_based_business_user_account.id
    end

    test "does not double count enterprise installation accounts without a user who match outside collaborators" do
      primary_email = "primary@example.com"
      # enterprise server user with no connected cloud account
      bua1 = create(:business_user_account, business: @business, user: nil, login: primary_email, roles: [:server_member])
      business_installation = create(:enterprise_installation, owner: @business)
      enterprise_installation_user_account = create(
        :enterprise_installation_user_account,
        enterprise_installation: business_installation,
        business_user_account: bua1,
      )
      create(
        :enterprise_installation_user_account_email,
        enterprise_installation_user_account: enterprise_installation_user_account,
        email: primary_email,
        primary: true,
      )
      collaborator = create :verified_user, email: primary_email
      perform_enqueued_jobs(only: [BusinessUpdateLicenseUsageJob]) do
        @private_repo.add_member(collaborator)
      end
      @business = Business.find @business.id

      refute_includes Business::LicenseAttributer.new(@business).users_with_business_access[:emails], primary_email
      assert_includes Business::LicenseAttributer.new(@business).users_with_business_access[:user_ids], collaborator.id
    end

    test "does not include unassigned bundled license" do
      email = "hello@visualstudio.com"
      create(:enterprise_agreement, :visual_studio_bundle, business: @business)
      create(:licensing_bundled_license_assignment, email: email, business: @business)

      refute_includes Business::LicenseAttributer.new(@business).users_with_business_access[:emails], email
    end
  end

  context "#invitations", skip_enterprise: true do
    test "counts pending member invites" do
      @organization.invite @rando, inviter: @organization_admin
      assert_includes Business::LicenseAttributer.new(@business).invitations[:user_ids], @rando.id
    end

    test "does not include invites to existing members" do
      @other_org.add_member(@rando)
      @organization.invite @rando, inviter: @organization_admin

      refute_includes Business::LicenseAttributer.new(@business).invitations[:user_ids], @rando.id
    end

    test "include pending collaborator invites" do
      RepositoryInvitation.invite_to_repo @rando, @organization_admin, @private_repo

      assert_includes Business::LicenseAttributer.new(@business).invitations[:user_ids], @rando.id
    end

    # This user is licensed by collaborator status, and not by the invite
    test "does not include collaborators who are invited to join org" do
      RepositoryInvitation.invite_to_repo_without_confirmation @rando, @organization_admin, @private_repo

      refute_includes Business::LicenseAttributer.new(@business).invitations[:user_ids], @rando.id
    end

    test "includes collaborators invited by email" do
      RepositoryInvitation.invite_to_repo_by_email @rando.email, @organization_admin, @private_repo

      assert_includes Business::LicenseAttributer.new(@business).invitations[:emails], @rando.email
    end
  end

  context "#unidentified_business_user_account_ids" do
    test "includes enterprise server users without user id or primary email" do
      _user_based_business_user_account = create(:business_user_account, business: @business, user: create(:user), roles: [:server_member])
      _email_based_business_user_account_with_blank_login = create(:business_user_account, business: @business, user: nil, login: "", roles: [:server_member]).tap do |business_user_account|
        enterprise_installation_user_account = create(
          :enterprise_installation_user_account,
          enterprise_installation: @enterprise_installation,
          business_user_account: business_user_account
        )
        create(
          :enterprise_installation_user_account_email,
          enterprise_installation_user_account: enterprise_installation_user_account,
          email: "example@example.com",
          primary: true,
        )
      end
      _email_based_business_user_account_with_populated_login = create(:business_user_account, business: @business, user: nil, login: "nonsense", roles: [:server_member]).tap do |business_user_account|
        enterprise_installation_user_account = create(
          :enterprise_installation_user_account,
          enterprise_installation: @enterprise_installation,
          business_user_account: business_user_account
        )
        create(
          :enterprise_installation_user_account_email,
          enterprise_installation_user_account: enterprise_installation_user_account,
          email: "example@example.com",
          primary: true,
        )
      end
      business_user_account_with_blank_login_and_no_emails = create(:business_user_account, business: @business, user: nil, login: "", roles: [:server_member]).tap do |business_user_account|
        create(
          :enterprise_installation_user_account,
          enterprise_installation: @enterprise_installation,
          business_user_account: business_user_account
        )
      end
      business_user_account_with_populated_login_and_no_emails = create(:business_user_account, business: @business, user: nil, login: "nonsense", roles: [:server_member]).tap do |business_user_account|
        create(
          :enterprise_installation_user_account,
          enterprise_installation: @enterprise_installation,
          business_user_account: business_user_account
        )
      end
      business_user_account_with_only_secondary_email = create(:business_user_account, business: @business, user: nil, roles: [:server_member]).tap do |business_user_account|
        enterprise_installation_user_account = create(
          :enterprise_installation_user_account,
          enterprise_installation: @enterprise_installation,
          business_user_account: business_user_account
        )
        create(
          :enterprise_installation_user_account_email,
          enterprise_installation_user_account: enterprise_installation_user_account,
          email: "example@example.com",
          primary: false
        )
      end

      attributer = Business::LicenseAttributer.new(@business)
      assert_same_elements(
        [business_user_account_with_blank_login_and_no_emails.id, business_user_account_with_populated_login_and_no_emails.id, business_user_account_with_only_secondary_email.id],
        attributer.unidentified_business_user_account_ids
      )
    end
  end

  context "#unique_count" do
    test "returns correct license count" do
      Business.destroy_all
      user1 = create(:user)
      user2 = create(:user)
      user3 = create(:user)
      user4 = create(:user)
      user5 = create(:user)
      user6 = create(:user)
      user7 = create(:user)
      user8 = create(:user)
      user9 = create(:user)
      user10 = create(:user)

      org1 = create(:organization, admins: [user1], public_members: [user2])
      org2 = create(:organization, admins: [user1], public_members: [user3])

      repo1 = create(:private_repository, owner: org1)
      repo1.add_member(user9)
      repo2 = create(:private_repository, owner: org2)
      repo2.add_member(user10)

      org1.invite(user4, inviter: user1)
      org1.invite(user5, inviter: user1)
      OrganizationInviter.new(org1, actor: user1, email: "invite1@invite.com").invite_user
      OrganizationInviter.new(org1, actor: user1, email: "invite2@invite.com").invite_user

      org2.invite(user4, inviter: user1)
      org1.invite(user6, inviter: user1)
      OrganizationInviter.new(org2, actor: user1, email: "invite1@invite.com").invite_user
      OrganizationInviter.new(org2, actor: user1, email: "invite3@invite.com").invite_user

      RepositoryInvitation.invite_to_repo(user5, user1, repo1)
      RepositoryInvitation.invite_to_repo(user7, user1, repo1)
      RepositoryInvitation.invite_to_repo_by_email("invite1@invite.com", user1, repo1)
      RepositoryInvitation.invite_to_repo_by_email("invite4@invite.com", user1, repo1)

      RepositoryInvitation.invite_to_repo(user6, user1, repo2)
      RepositoryInvitation.invite_to_repo(user8, user1, repo2)
      RepositoryInvitation.invite_to_repo_by_email("invite1@invite.com", user1, repo2)
      RepositoryInvitation.invite_to_repo_by_email("invite5@invite.com", user1, repo2)

      bus = create(:business, organizations: [org1, org2])

      primary_email = "primary@example.com"
      # enterprise server user with no connected cloud account
      bua1 = create(:business_user_account, business: bus, user: nil, login: primary_email, roles: [:server_member])
      business_installation = create(:enterprise_installation, owner: bus)
      enterprise_installation_user_account = create(
        :enterprise_installation_user_account,
        enterprise_installation: business_installation,
        business_user_account: bua1,
      )
      create(
        :enterprise_installation_user_account_email,
        enterprise_installation_user_account: enterprise_installation_user_account,
        email: primary_email,
        primary: true,
      )
      create(
        :enterprise_installation_user_account_email,
        enterprise_installation_user_account: enterprise_installation_user_account,
        email: "zzz_other_primary@example.com",
        primary: true,
      )
      # enterprise server user without email
      bua2 = create(:business_user_account, business: bus, user: nil, login: "", roles: [:server_member])

      # 5 unique email invites between organizations and repositories
      # 5 unique user invites between organizations and repositories
      # 1 non-linked server user with email
      # 1 anonymous server user
      # 3 organization members
      # 2 outside collaborators on private repositories
      attributer = Business::LicenseAttributer.new(bus.reload)
      assert_equal [user1.id, user2.id, user3.id, user4.id, user5.id, user6.id, user7.id, user8.id, user9.id, user10.id].sort, attributer.user_ids.sort
      assert_equal ["invite1@invite.com", "invite2@invite.com", "invite3@invite.com", "invite4@invite.com", "invite5@invite.com", "primary@example.com"], attributer.emails.sort
      assert_same_elements [bua2.id], attributer.unidentified_business_user_account_ids
      assert_equal 17, attributer.unique_count
    end

    test "consumes one license for users with multiple verified emails" do
      admin = create(:user)
      user1 = create(:user, :verified, email: "ladybug1@github.com")
      create(:user_email, :verified, user: user1, email: "ladybug2@github.com")
      create(:user_email, :verified, user: user1, email: "ladybug3@github.com")

      org1 = create(:organization, admins: [admin], public_members: [user1])
      business = create(:business, organizations: [org1])

      attributer = Business::LicenseAttributer.new(business.reload)

      assert_equal 2, attributer.unique_count
    end

    test "excludes pending email invitations to another org for existing enterprise members" do
      email = "ladybug@github.com"
      admin = create(:user)
      user1 = create(:user, :verified, email: email)
      org1 = create(:organization, admins: [admin], public_members: [user1])
      org2 = create(:organization, admins: [admin], public_members: [])
      business = create(:business, organizations: [org1, org2])

      OrganizationInviter.new(org2, actor: admin, email: email).invite_user
      attributer = Business::LicenseAttributer.new(business.reload)

      assert_equal 2, attributer.unique_count
    end

    test "excludes collaborator invitations in forked private repositories" do
      admin = create(:user)
      external_collaborator = create(:user)
      forker = create(:user)

      org = create(:organization, admin: admin)
      business = create(:business, :volume_licensed, owners: [admin], organizations: [org])
      repo = create(:private_repository, owner: org)
      org.add_member(forker)
      org.allow_private_repository_forking(actor: admin)

      forked_repo = create(:fork_repository, forker: forker, fork_repo: repo)
      RepositoryInvitation.invite_to_repo(external_collaborator, forker, forked_repo)
      attributer = Business::LicenseAttributer.new(business.reload)

      # licenses consumed by admin and forker
      assert_equal 2, attributer.unique_count
    end
  end

  unless GitHub.single_business_environment?
    context "emu suspension scenarios" do
      test "do not include user_id of suspended emu org member with no server account" do
        attributer = Business::LicenseAttributer.new(@emu_business.reload)
        assert_equal Set[@emu.id, @emu2.id], attributer.user_ids
        @emu2.external_identities.first.disable
        @emu2.suspend("test")
        perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)

        # clear memoized business and user ids
        @emu_business = Business.find @emu_business.id
        attributer = Business::LicenseAttributer.new(@emu_business)
        assert_equal Set[@emu.id], attributer.user_ids
      end

      test "includes user_id of suspended emu org member with active server account" do
        attributer = Business::LicenseAttributer.new(@emu_business.reload)
        assert_equal Set[@emu.id, @emu2.id], attributer.user_ids
        @emu2.external_identities.first.disable
        @emu2.suspend("test")

        enterprise_installation = create(:enterprise_installation, owner: @emu_business)
        ghes_user_act = create :enterprise_installation_user_account,
          enterprise_installation: enterprise_installation,
          site_admin: true,
          business_user_account: @emu2.business_user_account

        perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)

        # clear memoized business and user ids
        @emu_business = Business.find @emu_business.id
        attributer = Business::LicenseAttributer.new(@emu_business)
        assert_equal Set[@emu.id, @emu2.id], attributer.user_ids
      end

      test "includes user_id of emu org member with suspended server account" do
        attributer = Business::LicenseAttributer.new(@emu_business.reload)
        assert_equal Set[@emu.id, @emu2.id], attributer.user_ids

        enterprise_installation = create(:enterprise_installation, owner: @emu_business)
        ghes_user_act = create :enterprise_installation_user_account,
          enterprise_installation: enterprise_installation,
          site_admin: true,
          business_user_account: @emu2.business_user_account,
          suspended_at: Time.current

        perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)

        # clear memoized business and user ids
        @emu_business = Business.find @emu_business.id
        attributer = Business::LicenseAttributer.new(@emu_business)
        assert_equal Set[@emu.id, @emu2.id], attributer.user_ids
      end

      test "do not include user_id of emu org member with suspended server & cloud account" do
        attributer = Business::LicenseAttributer.new(@emu_business.reload)
        assert_equal Set[@emu.id, @emu2.id], attributer.user_ids
        @emu2.external_identities.first.disable
        @emu2.suspend("test")

        enterprise_installation = create(:enterprise_installation, owner: @emu_business)
        ghes_user_act = create :enterprise_installation_user_account,
          enterprise_installation: enterprise_installation,
          site_admin: true,
          business_user_account: @emu2.business_user_account,
          suspended_at: Time.current

        perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)

        # clear memoized business and user ids
        @emu_business = Business.find @emu_business.id
        attributer = Business::LicenseAttributer.new(@emu_business)
        assert_equal Set[@emu.id], attributer.user_ids
      end
    end
  end

  # For the below tests, create a new attributer instance to ensure the memoized values are cleared prior to each test
  context "query counts for public methods" do
    test "user_ids queries do not increase with more users" do
      # Volume licensed businesses have an extra query. Populating that now so the comparison will be equal later
      create(:enterprise_agreement, :visual_studio_bundle, business: @business)
      # Clear previously memoized values
      attributer = fresh_attributer(include_nonlicensed_roles: true)

      assert_query_count(8) do
        attributer.user_ids
      end

      # Add users to the business
      add_variety_of_users_to_business

      # Clear memoized values
      attributer = fresh_attributer(include_nonlicensed_roles: true)

      # Verify the query count did not change after adding more users
      assert_query_count(8) do
        attributer.user_ids
      end
    end

    test "emails queries do not increase with more users" do
      create(:enterprise_agreement, :visual_studio_bundle, business: @business)
      attributer = fresh_attributer(include_nonlicensed_roles: true)

      assert_query_count(11) do
        attributer.emails
      end

      add_variety_of_users_to_business

      attributer = fresh_attributer(include_nonlicensed_roles: true)

      assert_query_count(11) do
        attributer.emails
      end
    end

    test "unique_count queries do not increase with more users" do
      create(:enterprise_agreement, :visual_studio_bundle, business: @business)
      attributer = fresh_attributer(include_nonlicensed_roles: true)

      assert_query_count(13) do
        assert_equal attributer.unique_count, 2
      end

      add_variety_of_users_to_business

      attributer = fresh_attributer(include_nonlicensed_roles: true)

      assert_query_count(13) do
        assert_equal attributer.unique_count, 16 # Extra verification that add_variety_of_users_to_business worked
      end
    end

    test "license_usage_hash queries do not increase with more users" do
      disable_feature_flag(:business_use_organization_outside_collaborator_ids)
      disable_feature_flag(:collaborator_cache_write)
      disable_feature_flag(:collaborator_cache_read)
      # The license usage hash has additional queries for each **type** of user: invites, members, collaborators, etc.
      # Creating all user types in order to ensure those queries are executed initially
      @organization.invite(create(:user), inviter: @organization_admin)
      perform_enqueued_jobs(only: [BusinessUpdateLicenseUsageJob]) do
        create(:business_user_account, business: @business, user: nil, login: "license_hash", roles: [:server_member]).tap do |business_user_account|
          enterprise_installation_user_account = create(
            :enterprise_installation_user_account,
            enterprise_installation: @enterprise_installation,
            business_user_account: business_user_account
          )
          create(
            :enterprise_installation_user_account_email,
            enterprise_installation_user_account: enterprise_installation_user_account,
            email: "license_hash@example.com",
            primary: true,
          )
        end
      end

      create(:enterprise_agreement, :visual_studio_bundle, business: @business)
      attributer = fresh_attributer(include_nonlicensed_roles: true)

      count = 56
      count += 1 if GitHub.flipper[:unaffiliated_user_accounts].enabled?
      assert_query_count(count) do
        attributer.license_usage_hash
      end

      add_variety_of_users_to_business
      attributer = fresh_attributer(include_nonlicensed_roles: true)

      # Ideally, this would match the initial number. Documenting this behavior for now.
      assert_query_count(count + 11) do
        attributer.license_usage_hash
      end
    end

    test "users_with_business_access queries do not increase with more users" do
      create(:enterprise_agreement, :visual_studio_bundle, business: @business)
      attributer = fresh_attributer

      assert_query_count(12) do
        attributer.users_with_business_access
      end

      add_variety_of_users_to_business
      attributer = fresh_attributer

      assert_query_count(12) do
        attributer.users_with_business_access
      end
    end

    test "invitations queries do not increase with more users" do
      create(:enterprise_agreement, :visual_studio_bundle, business: @business)
      attributer = fresh_attributer

      assert_query_count(9) do
        attributer.invitations
      end

      add_variety_of_users_to_business

      attributer = fresh_attributer

      assert_query_count(9) do
        attributer.invitations
      end
    end
  end
end if GitHub.billing_enabled?

class BusinessLicenseAttributerBundleLicenseSyncStatus < GitHub::TestCase
  extend GitHub::FeatureFlagTestHelper

  fixtures do
    @business = create(:business)
    @admin = @business.owners.first
    @enterprise_installation = create(:enterprise_installation, owner: @business, server_id: 1, host_name: "foo.github.com")
  end

  test "returns empty list of servers if no enterprise installations" do
    EnterpriseInstallation.any_instance.stubs(:select).returns([])
    instance_sync_status = Business::LicenseAttributer.new(@business).enterprise_installation_sync_status
    assert_equal 0, instance_sync_status[:server_instances].count
  end

  test "returns empty list of servers if connected but license sync hasn't occurred" do
    instance_sync_status = Business::LicenseAttributer.new(@business).enterprise_installation_sync_status
    assert_equal 0, instance_sync_status[:server_instances].count
  end

  test "returns sync status for a single server upload" do
    upload_date = DateTime.new(2023, 5, 19)
    upload = create :enterprise_installation_user_accounts_upload,
      business: @business,
      enterprise_installation_id: @enterprise_installation.id,
      uploader_id: @admin.id,
      sync_state:  "success",
      updated_at: upload_date

    instance_sync_status = Business::LicenseAttributer.new(@business).enterprise_installation_sync_status

    assert_equal 1, instance_sync_status[:server_instances].count
    assert_equal @enterprise_installation.server_id, instance_sync_status[:server_instances][0][:server_id]
    assert_equal @enterprise_installation.host_name, instance_sync_status[:server_instances][0][:hostname]
    assert_equal upload_date, instance_sync_status[:server_instances][0][:last_sync][:date]
    assert_equal "success", instance_sync_status[:server_instances][0][:last_sync][:status]
    assert_empty instance_sync_status[:server_instances][0][:last_sync][:error]
  end

  test "returns latest sync status for a single server" do
    create :enterprise_installation_user_accounts_upload,
      business: @business,
      enterprise_installation_id: @enterprise_installation.id,
      uploader_id: @admin.id,
      sync_state: "success",
      updated_at: DateTime.new(2023, 5, 19) - 1.week

    upload_date = DateTime.new(2023, 5, 19)
    upload = create :enterprise_installation_user_accounts_upload,
      business: @business,
      enterprise_installation_id: @enterprise_installation.id,
      uploader_id: @admin.id,
      sync_state: "pending",
      updated_at: upload_date

    instance_sync_status = Business::LicenseAttributer.new(@business).enterprise_installation_sync_status

    assert_equal 1, instance_sync_status[:server_instances].count
    assert_equal upload_date, instance_sync_status[:server_instances][0][:last_sync][:date]
    assert_equal "pending", instance_sync_status[:server_instances][0][:last_sync][:status]
  end

  test "returns latest sync status for multiple servers" do
    enterprise_installation2 = create(:enterprise_installation, owner: @business, server_id: 2, host_name: "bar.github.com")

    upload_date = DateTime.new(2023, 5, 19) - 1.week
    upload = create :enterprise_installation_user_accounts_upload,
      business: @business,
      enterprise_installation_id: @enterprise_installation.id,
      uploader_id: @admin.id,
      sync_state: "success",
      updated_at: upload_date

    upload2_date = DateTime.new(2023, 5, 19)
    upload2 = create :enterprise_installation_user_accounts_upload,
      business: @business,
      enterprise_installation_id: enterprise_installation2.id,
      uploader_id: @admin.id,
      sync_state: "pending",
      updated_at: upload2_date

    instance_sync_status = Business::LicenseAttributer.new(@business).enterprise_installation_sync_status

    assert_equal 2, instance_sync_status[:server_instances].count

    assert one = instance_sync_status[:server_instances].find { |si| si[:server_id] == @enterprise_installation.server_id }
    assert two = instance_sync_status[:server_instances].find { |si| si[:server_id] == enterprise_installation2.server_id }

    assert_equal @enterprise_installation.host_name, one[:hostname]
    assert_equal enterprise_installation2.host_name, two[:hostname]
    assert_equal upload.sync_state, one[:last_sync][:status]
    assert_equal upload2.sync_state, two[:last_sync][:status]
    assert_equal upload_date, one[:last_sync][:date]
    assert_equal upload2_date, two[:last_sync][:date]
  end

  test "returns latest sync status for multiple servers where one has never synced" do
    enterprise_installation2 = create(:enterprise_installation, owner: @business)

    create :enterprise_installation_user_accounts_upload,
      business: @business,
      enterprise_installation_id: @enterprise_installation.id,
      uploader_id: @admin.id,
      sync_state: "success",
      updated_at: 1.day.ago

    instance_sync_status = Business::LicenseAttributer.new(@business).enterprise_installation_sync_status

    assert_equal 1, instance_sync_status[:server_instances].count

    refute_nil instance_sync_status[:server_instances][0][:last_sync][:date]
    refute_nil instance_sync_status[:server_instances][0][:last_sync][:status]
  end
end if GitHub.billing_enabled?

# We test the Business::LicenseAttributer.license_usage_hash in it's own test case
# because it requires a lot of construction for all of the types of matching tested
# and it's easier to test and maintain it all in one place free of everything else.
class BusinessLicenseAttributerLicenseUsageHash < GitHub::TestCase
  extend GitHub::FeatureFlagTestHelper

  fixtures do
    @org_admin = create(:user, :two_factor_enabled, login: "org-admin")
    @organization = create(:organization, admin: @org_admin)
    @organization2 = create(:organization, admin: @org_admin)
    @private_repo = create(:private_repository, owner: @organization)
    @business = create(:business, organizations: [@organization, @organization2])
    @enterprise_installation = create(:enterprise_installation, owner: @business)
    @enterprise_installation2 = create(:enterprise_installation, owner: @business)
  end

  test "returns a hash indicating no license usage when no users in business" do
    business = create(:business)
    hash = Business::LicenseAttributer.new(business).license_usage_hash
    assert_equal hash[:total_seats_consumed], 0
    assert_empty hash[:users]
  end

  test "returns the correct number of users for large enterprises" do
    Business::LicenseAttributer.stub_const(:MAX_USER_PROFILE_QUERIES, 3) do
      create_list(:user, 10).each { |u| @organization.add_member(u) }

      hash = Business::LicenseAttributer.new(@business).license_usage_hash
      assert_equal hash[:users].count, 11 # 10 users + 1 admin
    end
  end

  test "returns a hash for all types of users in business" do
    create(:enterprise_agreement, :visual_studio_bundle, business: @business)

    verified_org_domain = create(:verifiable_domain, owner: @organization, domain: "example.com", verified: true)
    verified_bus_domain = create(:verifiable_domain, owner: @business, domain: "xyz.lol", verified: true)
    # These should not appear anywhere in the hash
    approved_org_domain = create(:verifiable_domain, owner: @organization, domain: "org-approved.com", approved: true)
    approved_bus_domain = create(:verifiable_domain, owner: @business, domain: "bus-approved.com", approved: true)

    # Org admin - tweak profile and verify email
    create(:profile, name: "Org Admin", user: @org_admin)
    org_admin_verified_email = "org-admin@xyz.lol"
    @org_admin.add_email(org_admin_verified_email).verify!
    @org_admin.add_email("admin@org-approved.com").verify!

    # VSS user
    vss_user = create(:user, login: "vss-user")
    create(:profile, name: "VSS User", user: vss_user)
    @organization.add_member(vss_user)
    vss_user_bbla = create(:licensing_bundled_license_assignment, user: vss_user, business: @business)

    # Enterprise user that has everything:
    # - a SAML NameID,
    # - a verified org-level domain email,
    # - a business-level approved domain email,
    # - is a GHES user on multiple instances, with multiple emails on one instance,
    # - is the org's billing manager
    # - a pending org invite
    ent_user = create(:user, login: "ent-user")
    create(:profile, name: "Enterprise User", user: ent_user)
    ent_user_email = "ent-user@example.com"
    ent_user_ano_email = "ent-user@another.com"
    ent_user.add_email(ent_user_email).verify!
    ent_user.add_email("ent-user@bus-approved.com").verify!
    @organization.add_member(ent_user)
    @organization2.invite(ent_user, inviter: @org_admin)
    Organization::BillingManagement.new(@organization).add_manager(ent_user, actor: @org_admin)
    provider = create :organization_saml_provider, organization: @organization
    ent_user_nameid = "ent-user-NameID"
    saml_user_data = Platform::Provisioning::SamlUserData.new([
      { "name" => "NameID", "value" => ent_user_nameid },
    ])
    create(:external_identity, provider: provider, user: ent_user, saml_user_data: saml_user_data)

    ent_inst_user_act = create :enterprise_installation_user_account, :ghas_connect,
      enterprise_installation: @enterprise_installation,
      site_admin: true,
      business_user_account: ent_user.business_user_accounts.first,
      using_advanced_security: true

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ent_inst_user_act,
      email: ent_user_email, primary: true

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ent_inst_user_act,
      email: ent_user_ano_email, primary: false

    ent_inst_user_act2 = create :enterprise_installation_user_account, :ghas_connect,
      enterprise_installation: @enterprise_installation2,
      site_admin: true,
      business_user_account: ent_user.business_user_accounts.first,
      using_advanced_security: true

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ent_inst_user_act2,
      email: "ent-user@example.com", primary: true

    # GHES-only user with a primary email
    ghes_user_email = "ghes-user@example.com"
    ghes_user_act = create :enterprise_installation_user_account, :ghas_connect,
      enterprise_installation: @enterprise_installation,
      using_advanced_security: true

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ghes_user_act,
      email: ghes_user_email, primary: true

    create :business_user_account, business: @business, user: nil,
      enterprise_installation_user_accounts: [ghes_user_act],
      login: ghes_user_email, roles: [:server_member]

    # GHES-only user without a primary email
    noemail_ghes = create :enterprise_installation_user_account, :ghas_connect,
      enterprise_installation: @enterprise_installation,
      using_advanced_security: true

    create :business_user_account, business: @business, user: nil,
      enterprise_installation_user_accounts: [noemail_ghes],
      login: "user-#{noemail_ghes.remote_user_id}", roles: [:server_member]

    # GHES-only user with different primary email addresses on different instances
    ghes_user2_email = "ghes-user2@example.com"
    ghes_user2_email2 = "a-ghes-user2@example.com"
    ghes_user2_act = create :enterprise_installation_user_account, :ghas_connect,
      enterprise_installation: @enterprise_installation

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ghes_user2_act,
      email: ghes_user2_email, primary: true

    ghes_user2_bus_act = create :business_user_account, business: @business, user: nil,
      enterprise_installation_user_accounts: [ghes_user2_act],
      login: ghes_user2_email, roles: [:server_member]

    ghes_user2_act2 =  create :enterprise_installation_user_account, :ghas_connect,
      enterprise_installation: @enterprise_installation2,
      site_admin: true,
      business_user_account: ghes_user2_bus_act

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ghes_user2_act2,
      email: ghes_user2_email2, primary: true

    # GHES user which matches a VSS user
    ghes_vss_user_email = "ghes-vss@example.com"
    ghes_vss_user = create(:user, login: "ghes-vss-user", email: ghes_vss_user_email)
    create(:profile, name: "GHES VSS User", user: ghes_vss_user)
    @business.add_user_accounts([ghes_vss_user.id])
    ghes_vss_user_bbla = create :licensing_bundled_license_assignment,
      user: ghes_vss_user, email: ghes_vss_user_email, business: @business

    ghes_vss_user_act = create :enterprise_installation_user_account, :ghas_connect,
      enterprise_installation: @enterprise_installation,
      business_user_account: ghes_vss_user.business_user_accounts.first

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ghes_vss_user_act,
      email: ghes_vss_user_email, primary: true

    # User invited to an org with pending invitation
    org_invited_user = create(:user, login: "org-invited-user")
    create(:profile, name: "Org Invited User", user: org_invited_user)
    @organization.invite(org_invited_user, inviter: @org_admin)

    # Org invite by email without a corresponding user
    org_invite_email = "test@invite.com"
    @organization.invite(email: org_invite_email, inviter: @org_admin)

    # Private org repo with pending outside collaborator user invite
    outside_collab_user_pending = create(:user, login: "outside-collab-user-pending")
    create(:repository_invitation, repository: @private_repo, invitee: outside_collab_user_pending)

    # Private org repo with accepted outside collaborator user invite
    outside_collab_user_accepted = create(:user, login: "outside-collab-user-accepted")
    three_weeks_from_now = 3.weeks.from_now.utc
    TwoFactorRequirementMetadata.create!(user: outside_collab_user_accepted, requirement_reason: "test", required_by: three_weeks_from_now, state: User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES[:warning])
    create(:repository_invitation, repository: @private_repo, invitee: outside_collab_user_accepted).accept!

    # Org invite by and VSS assigned email address
    vss_org_invite_email = "vss-org@invite.com"
    @organization.invite(email: vss_org_invite_email, inviter: @org_admin)
    create(:licensing_bundled_license_assignment, business: @business, user: nil, email: "vss-org@invite.com")

    # GHES-only user that matches a deleted dotcom/GHEC user - this is a very rare edge case and will result in an
    # EnterpriseInstallationAccount linked to a BusinessUserAccount that no longer exists until the next license sync.
    deleted_user_email = "deleted-user@example.com"
    deleted_user = create(:user, login: "deleted-user")
    deleted_user.add_email(deleted_user_email).verify!
    del_user_act = create :enterprise_installation_user_account, :ghas_connect,
      enterprise_installation: @enterprise_installation,
      login: deleted_user.display_login
    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: del_user_act,
      email: deleted_user_email, primary: true
    create :business_user_account, business: @business, user: deleted_user,
      enterprise_installation_user_accounts: [del_user_act],
      login: deleted_user, roles: [:server_member]
    deleted_user.destroy!

    perform_enqueued_jobs(only: [BusinessUpdateLicenseUsageJob])
    @business = Business.find(@business.id)
    hash = Business::LicenseAttributer.new(@business).license_usage_hash

    assert_equal 12, hash[:total_seats_consumed]
    assert_equal 12, hash[:users].size

    expected = [{
      github_com_login: @org_admin.display_login,
      github_com_name: @org_admin.profile.name,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(@org_admin),
      github_com_member_roles:
        [@organization.name + ":Owner", @organization2.name + ":Owner"].sort,
      github_com_enterprise_roles: ["Member"],
      github_com_verified_domain_emails: [org_admin_verified_email],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: true,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      enterprise_server_advanced_security_user_ids: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    {
      github_com_login: vss_user.display_login,
      github_com_name: vss_user.profile.name,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: true,
      license_type: "Visual Studio subscription",
      github_com_profile: ViewModel::URLs.new.user_url(vss_user),
      github_com_member_roles: [@organization.name + ":Member"],
      github_com_enterprise_roles: ["Member"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      enterprise_server_advanced_security_user_ids: [],
      visual_studio_license_status: "Matched to Cloud",
      visual_studio_subscription_email: vss_user_bbla.email,
      total_user_accounts: 1
    },
    {
      github_com_login: ent_user.display_login,
      github_com_name: ent_user.profile.name,
      enterprise_server_user_ids: [
        "#{ent_inst_user_act.remote_user_id}:#{@enterprise_installation.host_name}:Owner",
        "#{ent_inst_user_act2.remote_user_id}:#{@enterprise_installation2.host_name}:Owner"
      ].sort,
      github_com_user: true,
      enterprise_server_user: true,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(ent_user),
      github_com_member_roles: [@organization.name + ":Billing manager"],
      github_com_enterprise_roles: ["Member", "Pending invitation"],
      github_com_verified_domain_emails: [ent_user_email],
      github_com_saml_name_id: ent_user_nameid,
      github_com_orgs_with_pending_invites: [@organization2.name],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [ent_user_email].sort,
      enterprise_server_advanced_security_user_ids: [
        "#{ent_inst_user_act.remote_user_id}:#{@enterprise_installation.host_name}",
        "#{ent_inst_user_act2.remote_user_id}:#{@enterprise_installation2.host_name}",
      ].sort,
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 3
    },
    {
      github_com_login: ghes_vss_user.display_login,
      github_com_name: ghes_vss_user.profile.name,
      enterprise_server_user_ids: ["#{ghes_vss_user_act.remote_user_id}:#{@enterprise_installation.host_name}:Member"],
      github_com_user: true,
      enterprise_server_user: true,
      visual_studio_subscription_user: true,
      license_type: "Visual Studio subscription",
      github_com_profile: ViewModel::URLs.new.user_url(ghes_vss_user),
      github_com_member_roles: [],
      github_com_enterprise_roles: [],
      github_com_verified_domain_emails: [ghes_vss_user_email],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [ghes_vss_user_email],
      enterprise_server_advanced_security_user_ids: [],
      visual_studio_license_status: "Matched to Cloud + Server",
      visual_studio_subscription_email: ghes_vss_user_email,
      total_user_accounts: 2
    },
    {
      github_com_login: org_invited_user.display_login,
      github_com_name: org_invited_user.profile.name,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(org_invited_user),
      github_com_member_roles: [],
      github_com_enterprise_roles: ["Pending invitation"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [@organization.name],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      enterprise_server_advanced_security_user_ids: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    {
      github_com_login: outside_collab_user_pending.display_login,
      github_com_name: nil,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(outside_collab_user_pending),
      github_com_member_roles: [],
      github_com_enterprise_roles: ["Pending outside collaborator invitation"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      enterprise_server_advanced_security_user_ids: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    {
      github_com_login: outside_collab_user_accepted.display_login,
      github_com_name: nil,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(outside_collab_user_accepted),
      github_com_member_roles: [],
      github_com_enterprise_roles: ["Outside collaborator"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: three_weeks_from_now.strftime("%Y-%m-%d"),
      enterprise_server_primary_emails: [],
      enterprise_server_advanced_security_user_ids: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1,
    },
    { # ghes-only user with different primary email addresses on different instances
      github_com_login: "",
      github_com_name: nil,
      enterprise_server_user_ids: [
        "#{ghes_user2_act.remote_user_id}:#{@enterprise_installation.host_name}:Member",
        "#{ghes_user2_act2.remote_user_id}:#{@enterprise_installation.host_name}:Owner"
      ].sort,
      github_com_user: false,
      enterprise_server_user: true,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: nil,
      github_com_member_roles: [],
      github_com_enterprise_roles: [],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: nil,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [ghes_user2_email, ghes_user2_email2].sort,
      enterprise_server_advanced_security_user_ids: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 2
    },
    { # ghes-only user with a primary email
      github_com_login: "",
      github_com_name: nil,
      enterprise_server_user_ids: ["#{ghes_user_act.remote_user_id}:#{@enterprise_installation.host_name}:Member"],
      github_com_user: false,
      enterprise_server_user: true,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: nil,
      github_com_member_roles: [],
      github_com_enterprise_roles: [],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: nil,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [ghes_user_email],
      enterprise_server_advanced_security_user_ids: ["#{ghes_user_act.remote_user_id}:#{@enterprise_installation.host_name}"],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    { # org invite by email without a corresponding user
      github_com_login: org_invite_email,
      github_com_name: nil,
      enterprise_server_user_ids: [],
      github_com_user: false,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: nil,
      github_com_member_roles: [],
      github_com_enterprise_roles: ["Pending invitation"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [@organization.name],
      github_com_two_factor_auth: nil,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      enterprise_server_advanced_security_user_ids: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 0
    },
    { # ghes-only user without a primary email
      github_com_login: "",
      github_com_name: nil,
      enterprise_server_user_ids: ["#{noemail_ghes.remote_user_id}:#{@enterprise_installation.host_name}:Member"],
      github_com_user: false,
      enterprise_server_user: true,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: nil,
      github_com_member_roles: [],
      github_com_enterprise_roles: [],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: nil,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      enterprise_server_advanced_security_user_ids: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    { # org invite by email using an allocated VSS license
      github_com_login: "vss-org@invite.com",
      github_com_name: nil,
      enterprise_server_user_ids: [],
      github_com_user: false,
      enterprise_server_user: false,
      visual_studio_subscription_user: true,
      license_type: "Visual Studio subscription",
      github_com_profile: nil,
      github_com_member_roles: [],
      github_com_enterprise_roles: ["Pending invitation"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [@organization.name],
      github_com_two_factor_auth: nil,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      enterprise_server_advanced_security_user_ids: [],
      visual_studio_license_status: "Pending Invitation",
      visual_studio_subscription_email: "vss-org@invite.com",
      total_user_accounts: 0
    }]

    0..expected.size.times do |i|
      assert_equal expected[i], hash[:users][i], "Failed to match row #{i + 1}"
    end
  end

  test "returns correct hash on pagination edge cases" do
    create(:enterprise_agreement, :visual_studio_bundle, business: @business)

    verified_org_domain = create(:verifiable_domain, owner: @organization, domain: "example.com", verified: true)
    verified_bus_domain = create(:verifiable_domain, owner: @business, domain: "xyz.lol", verified: true)

    # Org admin - tweak profile and verify email
    create(:profile, name: "Org Admin", user: @org_admin)
    org_admin_verified_email = "org-admin@xyz.lol"
    @org_admin.add_email(org_admin_verified_email).verify!

    # VSS user
    vss_user = create(:user, login: "vss-user")
    create(:profile, name: "VSS User", user: vss_user)
    @organization.add_member(vss_user)
    vss_user_bbla = create(:licensing_bundled_license_assignment, user: vss_user, business: @business)

    # Enterprise user that has everything:
    # - a SAML NameID,
    # - a verified org-level domain email,
    # - is a GHES user on multiple instances, with multiple emails on one instance,
    # - is the org's billing manager
    # - a pending org invite
    ent_user = create(:user, login: "ent-user")
    create(:profile, name: "Enterprise User", user: ent_user)
    ent_user_email = "ent-user@example.com"
    ent_user_ano_email = "ent-user@another.com"
    ent_user.add_email(ent_user_email).verify!
    @organization.add_member(ent_user)
    @organization2.invite(ent_user, inviter: @org_admin)
    Organization::BillingManagement.new(@organization).add_manager(ent_user, actor: @org_admin)
    provider = create :organization_saml_provider, organization: @organization
    ent_user_nameid = "ent-user-NameID"
    saml_user_data = Platform::Provisioning::SamlUserData.new([
      { "name" => "NameID", "value" => ent_user_nameid },
    ])
    create(:external_identity, provider: provider, user: ent_user, saml_user_data: saml_user_data)

    ent_inst_user_act = create :enterprise_installation_user_account,
      enterprise_installation: @enterprise_installation,
      site_admin: true,
      business_user_account: ent_user.business_user_accounts.first

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ent_inst_user_act,
      email: ent_user_email, primary: true

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ent_inst_user_act,
      email: ent_user_ano_email, primary: false

    ent_inst_user_act2 = create :enterprise_installation_user_account,
      enterprise_installation: @enterprise_installation2,
      site_admin: true,
      business_user_account: ent_user.business_user_accounts.first

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ent_inst_user_act2,
      email: "ent-user@example.com", primary: true

    # GHES-only user with a primary email
    ghes_user_email = "ghes-user@example.com"
    ghes_user_act = create :enterprise_installation_user_account,
      enterprise_installation: @enterprise_installation

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ghes_user_act,
      email: ghes_user_email, primary: true

    create :business_user_account, business: @business, user: nil,
      enterprise_installation_user_accounts: [ghes_user_act],
      login: ghes_user_email, roles: [:server_member]

    # GHES-only user without a primary email
    noemail_ghes = create :enterprise_installation_user_account,
      enterprise_installation: @enterprise_installation

    create :business_user_account, business: @business, user: nil,
      enterprise_installation_user_accounts: [noemail_ghes],
      login: "user-#{noemail_ghes.remote_user_id}", roles: [:server_member]

    # GHES-only user with different primary email addresses on different instances
    ghes_user2_email = "ghes-user2@example.com"
    ghes_user2_email2 = "a-ghes-user2@example.com"
    ghes_user2_act = create :enterprise_installation_user_account,
      enterprise_installation: @enterprise_installation,
      login: "a-ghes-user2"

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ghes_user2_act,
      email: ghes_user2_email, primary: true

    ghes_user2_bus_act = create :business_user_account, business: @business, user: nil,
      enterprise_installation_user_accounts: [ghes_user2_act],
      login: ghes_user2_email, roles: [:server_member]

    ghes_user2_act2 =  create :enterprise_installation_user_account,
      enterprise_installation: @enterprise_installation2,
      site_admin: true,
      business_user_account: ghes_user2_bus_act,
      login: "a-ghes-user2-site-admin"

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ghes_user2_act2,
      email: ghes_user2_email2, primary: true

    # GHES user which matches a VSS user
    ghes_vss_user_email = "ghes-vss@example.com"
    ghes_vss_user = create(:user, login: "ghes-vss-user", email: ghes_vss_user_email)
    create(:profile, name: "GHES VSS User", user: ghes_vss_user)
    @business.add_user_accounts([ghes_vss_user.id])
    ghes_vss_user_bbla = create :licensing_bundled_license_assignment,
      user: ghes_vss_user, email: ghes_vss_user_email, business: @business

    ghes_vss_user_act = create :enterprise_installation_user_account,
      enterprise_installation: @enterprise_installation,
      business_user_account: ghes_vss_user.business_user_accounts.first

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ghes_vss_user_act,
      email: ghes_vss_user_email, primary: true

    # User invited to an org with pending invitation
    org_invited_user = create(:user, login: "org-invited-user")
    create(:profile, name: "Org Invited User", user: org_invited_user)
    @organization.invite(org_invited_user, inviter: @org_admin)

    # Org invite by email without a corresponding user
    org_invite_email = "test@invite.com"
    @organization.invite(email: org_invite_email, inviter: @org_admin)

    # Private org repo with pending outside collaborator user invite
    outside_collab_user_pending = create(:user, login: "outside-collab-user-pending")
    create(:repository_invitation, repository: @private_repo, invitee: outside_collab_user_pending)

    # Private org repo with accepted outside collaborator user invite
    outside_collab_user_accepted = create(:user, login: "outside-collab-user-accepted")
    create(:repository_invitation, repository: @private_repo, invitee: outside_collab_user_accepted).accept!

    # Org invite by and VSS assigned email address
    vss_org_invite_email = "vss-org@invite.com"
    @organization.invite(email: vss_org_invite_email, inviter: @org_admin)
    create(:licensing_bundled_license_assignment, business: @business, user: nil, email: "vss-org@invite.com")

    perform_enqueued_jobs(only: [BusinessUpdateLicenseUsageJob])
    @business = Business.find(@business.id)
    hash_page_less_than_0 = Business::LicenseAttributer.new(@business).license_usage_hash(pagination: true, page: -1)
    # This should have only six pages as we have 12 elements; but we are requesting page 7
    # We should get a result without any users present.
    hash_page_beyond_last_page = Business::LicenseAttributer.new(@business).license_usage_hash(pagination: true, page: 7, per_page: 2)

    expected_full_hash = [{
      github_com_login: @org_admin.display_login,
      github_com_name: @org_admin.profile.name,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(@org_admin),
      github_com_member_roles:
        [@organization.name + ":Owner", @organization2.name + ":Owner"].sort,
      github_com_enterprise_roles: ["Member"],
      github_com_verified_domain_emails: [org_admin_verified_email],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: true,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    {
      github_com_login: vss_user.display_login,
      github_com_name: vss_user.profile.name,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: true,
      license_type: "Visual Studio subscription",
      github_com_profile: ViewModel::URLs.new.user_url(vss_user),
      github_com_member_roles: [@organization.name + ":Member"],
      github_com_enterprise_roles: ["Member"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: "Matched to Cloud",
      visual_studio_subscription_email: vss_user_bbla.email,
      total_user_accounts: 1
    },
    {
      github_com_login: ent_user.display_login,
      github_com_name: ent_user.profile.name,
      enterprise_server_user_ids: [
        "#{ent_inst_user_act.remote_user_id}:#{@enterprise_installation.host_name}:Owner",
        "#{ent_inst_user_act2.remote_user_id}:#{@enterprise_installation2.host_name}:Owner"
      ].sort,
      github_com_user: true,
      enterprise_server_user: true,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(ent_user),
      github_com_member_roles: [@organization.name + ":Billing manager"],
      github_com_enterprise_roles: ["Member", "Pending invitation"],
      github_com_verified_domain_emails: [ent_user_email],
      github_com_saml_name_id: ent_user_nameid,
      github_com_orgs_with_pending_invites: [@organization2.name],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [ent_user_email].sort,
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 3
    },
    {
      github_com_login: ghes_vss_user.display_login,
      github_com_name: ghes_vss_user.profile.name,
      enterprise_server_user_ids: ["#{ghes_vss_user_act.remote_user_id}:#{@enterprise_installation.host_name}:Member"],
      github_com_user: true,
      enterprise_server_user: true,
      visual_studio_subscription_user: true,
      license_type: "Visual Studio subscription",
      github_com_profile: ViewModel::URLs.new.user_url(ghes_vss_user),
      github_com_member_roles: [],
      github_com_enterprise_roles: [],
      github_com_verified_domain_emails: [ghes_vss_user_email],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [ghes_vss_user_email],
      visual_studio_license_status: "Matched to Cloud + Server",
      visual_studio_subscription_email: ghes_vss_user_email,
      total_user_accounts: 2
    },
    {
      github_com_login: org_invited_user.display_login,
      github_com_name: org_invited_user.profile.name,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(org_invited_user),
      github_com_member_roles: [],
      github_com_enterprise_roles: ["Pending invitation"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [@organization.name],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    {
      github_com_login: outside_collab_user_pending.display_login,
      github_com_name: nil,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(outside_collab_user_pending),
      github_com_member_roles: [],
      github_com_enterprise_roles: ["Pending outside collaborator invitation"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    {
      github_com_login: outside_collab_user_accepted.display_login,
      github_com_name: nil,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(outside_collab_user_accepted),
      github_com_member_roles: [],
      github_com_enterprise_roles: ["Outside collaborator"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    { # ghes-only user with different primary email addresses on different instances
      github_com_login: "",
      github_com_name: nil,
      enterprise_server_user_ids: [
        "#{ghes_user2_act.remote_user_id}:#{@enterprise_installation.host_name}:Member",
        "#{ghes_user2_act2.remote_user_id}:#{@enterprise_installation.host_name}:Owner"
      ].sort,
      github_com_user: false,
      enterprise_server_user: true,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: nil,
      github_com_member_roles: [],
      github_com_enterprise_roles: [],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: nil,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [ghes_user2_email, ghes_user2_email2].sort,
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 2
    },
    { # ghes-only user with a primary email
      github_com_login: "",
      github_com_name: nil,
      enterprise_server_user_ids: ["#{ghes_user_act.remote_user_id}:#{@enterprise_installation.host_name}:Member"],
      github_com_user: false,
      enterprise_server_user: true,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: nil,
      github_com_member_roles: [],
      github_com_enterprise_roles: [],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: nil,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [ghes_user_email],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    { # org invite by email without a corresponding user
      github_com_login: org_invite_email,
      github_com_name: nil,
      enterprise_server_user_ids: [],
      github_com_user: false,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: nil,
      github_com_member_roles: [],
      github_com_enterprise_roles: ["Pending invitation"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [@organization.name],
      github_com_two_factor_auth: nil,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 0
    },
    { # ghes-only user without a primary email
      github_com_login: "",
      github_com_name: nil,
      enterprise_server_user_ids: ["#{noemail_ghes.remote_user_id}:#{@enterprise_installation.host_name}:Member"],
      github_com_user: false,
      enterprise_server_user: true,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: nil,
      github_com_member_roles: [],
      github_com_enterprise_roles: [],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: nil,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    { # org invite by email using an allocated VSS license
      github_com_login: "vss-org@invite.com",
      github_com_name: nil,
      enterprise_server_user_ids: [],
      github_com_user: false,
      enterprise_server_user: false,
      visual_studio_subscription_user: true,
      license_type: "Visual Studio subscription",
      github_com_profile: nil,
      github_com_member_roles: [],
      github_com_enterprise_roles: ["Pending invitation"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [@organization.name],
      github_com_two_factor_auth: nil,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: "Pending Invitation",
      visual_studio_subscription_email: "vss-org@invite.com",
      total_user_accounts: 0,
    }]

    expected_hash_page_beyond_last_page = []

    assert_equal 12, hash_page_less_than_0[:total_seats_consumed]
    assert_equal 12, hash_page_less_than_0[:users].size
    assert_equal 12, hash_page_beyond_last_page[:total_seats_consumed]
    assert_equal 0, hash_page_beyond_last_page[:users].size

    0..expected_full_hash.size.times do |i|
      assert_equal expected_full_hash[i], hash_page_less_than_0[:users][i]
    end

    assert_equal expected_hash_page_beyond_last_page, hash_page_beyond_last_page[:users]
  end

  test "returns a hash for all types of users in business with pagination" do
    create(:enterprise_agreement, :visual_studio_bundle, business: @business)

    verified_org_domain = create(:verifiable_domain, owner: @organization, domain: "example.com", verified: true)
    verified_bus_domain = create(:verifiable_domain, owner: @business, domain: "xyz.lol", verified: true)

    # Org admin - tweak profile and verify email
    create(:profile, name: "Org Admin", user: @org_admin)
    org_admin_verified_email = "org-admin@xyz.lol"
    @org_admin.add_email(org_admin_verified_email).verify!

    # VSS user
    vss_user = create(:user, login: "vss-user")
    create(:profile, name: "VSS User", user: vss_user)
    @organization.add_member(vss_user)
    vss_user_bbla = create(:licensing_bundled_license_assignment, user: vss_user, business: @business)

    # Enterprise user that has everything:
    # - a SAML NameID,
    # - a verified org-level domain email,
    # - is a GHES user on multiple instances, with multiple emails on one instance,
    # - is the org's billing manager
    # - a pending org invite
    ent_user = create(:user, login: "ent-user")
    create(:profile, name: "Enterprise User", user: ent_user)
    ent_user_email = "ent-user@example.com"
    ent_user_ano_email = "ent-user@another.com"
    ent_user.add_email(ent_user_email).verify!
    @organization.add_member(ent_user)
    @organization2.invite(ent_user, inviter: @org_admin)
    Organization::BillingManagement.new(@organization).add_manager(ent_user, actor: @org_admin)
    provider = create :organization_saml_provider, organization: @organization
    ent_user_nameid = "ent-user-NameID"
    saml_user_data = Platform::Provisioning::SamlUserData.new([
      { "name" => "NameID", "value" => ent_user_nameid },
    ])
    create(:external_identity, provider: provider, user: ent_user, saml_user_data: saml_user_data)

    ent_inst_user_act = create :enterprise_installation_user_account,
      enterprise_installation: @enterprise_installation,
      site_admin: true,
      business_user_account: ent_user.business_user_accounts.first

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ent_inst_user_act,
      email: ent_user_email, primary: true

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ent_inst_user_act,
      email: ent_user_ano_email, primary: false

    ent_inst_user_act2 = create :enterprise_installation_user_account,
      enterprise_installation: @enterprise_installation2,
      site_admin: true,
      business_user_account: ent_user.business_user_accounts.first

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ent_inst_user_act2,
      email: "ent-user@example.com", primary: true

    # GHES-only user with a primary email
    ghes_user_email = "ghes-user@example.com"
    ghes_user_act = create :enterprise_installation_user_account,
      enterprise_installation: @enterprise_installation

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ghes_user_act,
      email: ghes_user_email, primary: true

    create :business_user_account, business: @business, user: nil,
      enterprise_installation_user_accounts: [ghes_user_act],
      login: ghes_user_email, roles: [:server_member]

    # GHES-only user without a primary email
    noemail_ghes = create :enterprise_installation_user_account,
      enterprise_installation: @enterprise_installation

    create :business_user_account, business: @business, user: nil,
      enterprise_installation_user_accounts: [noemail_ghes],
      login: "user-#{noemail_ghes.remote_user_id}", roles: [:server_member]

    # GHES-only user with different primary email addresses on different instances
    ghes_user2_email = "ghes-user2@example.com"
    ghes_user2_email2 = "a-ghes-user2@example.com"
    ghes_user2_act = create :enterprise_installation_user_account,
      enterprise_installation: @enterprise_installation,
      login: "a-ghes-user2"

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ghes_user2_act,
      email: ghes_user2_email, primary: true

    ghes_user2_bus_act = create :business_user_account, business: @business, user: nil,
      enterprise_installation_user_accounts: [ghes_user2_act],
      login: ghes_user2_email, roles: [:server_member]

    ghes_user2_act2 =  create :enterprise_installation_user_account,
      enterprise_installation: @enterprise_installation2,
      site_admin: true,
      business_user_account: ghes_user2_bus_act,
      login: "a-ghes-user2-site-admin"

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ghes_user2_act2,
      email: ghes_user2_email2, primary: true

    # GHES user which matches a VSS user
    ghes_vss_user_email = "ghes-vss@example.com"
    ghes_vss_user = create(:user, login: "ghes-vss-user", email: ghes_vss_user_email)
    create(:profile, name: "GHES VSS User", user: ghes_vss_user)
    @business.add_user_accounts([ghes_vss_user.id])
    ghes_vss_user_bbla = create :licensing_bundled_license_assignment,
      user: ghes_vss_user, email: ghes_vss_user_email, business: @business

    ghes_vss_user_act = create :enterprise_installation_user_account,
      enterprise_installation: @enterprise_installation,
      business_user_account: ghes_vss_user.business_user_accounts.first

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ghes_vss_user_act,
      email: ghes_vss_user_email, primary: true

    # User invited to an org with pending invitation
    org_invited_user = create(:user, login: "org-invited-user")
    create(:profile, name: "Org Invited User", user: org_invited_user)
    @organization.invite(org_invited_user, inviter: @org_admin)

    # Org invite by email without a corresponding user
    org_invite_email = "test@invite.com"
    @organization.invite(email: org_invite_email, inviter: @org_admin)

    # Private org repo with pending outside collaborator user invite
    outside_collab_user_pending = create(:user, login: "outside-collab-user-pending")
    create(:repository_invitation, repository: @private_repo, invitee: outside_collab_user_pending)

    # Private org repo with accepted outside collaborator user invite
    outside_collab_user_accepted = create(:user, login: "outside-collab-user-accepted")
    create(:repository_invitation, repository: @private_repo, invitee: outside_collab_user_accepted).accept!

    # Org invite by and VSS assigned email address
    vss_org_invite_email = "vss-org@invite.com"
    @organization.invite(email: vss_org_invite_email, inviter: @org_admin)
    create(:licensing_bundled_license_assignment, business: @business, user: nil, email: "vss-org@invite.com")

    perform_enqueued_jobs(only: [BusinessUpdateLicenseUsageJob])
    @business = Business.find(@business.id)

    hash_page_1 = Business::LicenseAttributer.new(@business).license_usage_hash(pagination: true, page: 1, per_page: 6)
    hash_page_2 = Business::LicenseAttributer.new(@business).license_usage_hash(pagination: true, page: 2, per_page: 6)

    expected_page_1 = [{
      github_com_login: @org_admin.display_login,
      github_com_name: @org_admin.profile.name,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(@org_admin),
      github_com_member_roles:
        [@organization.name + ":Owner", @organization2.name + ":Owner"].sort,
      github_com_enterprise_roles: ["Member"],
      github_com_verified_domain_emails: [org_admin_verified_email],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: true,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    {
      github_com_login: vss_user.display_login,
      github_com_name: vss_user.profile.name,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: true,
      license_type: "Visual Studio subscription",
      github_com_profile: ViewModel::URLs.new.user_url(vss_user),
      github_com_member_roles: [@organization.name + ":Member"],
      github_com_enterprise_roles: ["Member"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: "Matched to Cloud",
      visual_studio_subscription_email: vss_user_bbla.email,
      total_user_accounts: 1
    },
    {
      github_com_login: ent_user.display_login,
      github_com_name: ent_user.profile.name,
      enterprise_server_user_ids: [
        "#{ent_inst_user_act.remote_user_id}:#{@enterprise_installation.host_name}:Owner",
        "#{ent_inst_user_act2.remote_user_id}:#{@enterprise_installation2.host_name}:Owner"
      ].sort,
      github_com_user: true,
      enterprise_server_user: true,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(ent_user),
      github_com_member_roles: [@organization.name + ":Billing manager"],
      github_com_enterprise_roles: ["Member", "Pending invitation"],
      github_com_verified_domain_emails: [ent_user_email],
      github_com_saml_name_id: ent_user_nameid,
      github_com_orgs_with_pending_invites: [@organization2.name],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [ent_user_email].sort,
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 3
    },
    {
      github_com_login: ghes_vss_user.display_login,
      github_com_name: ghes_vss_user.profile.name,
      enterprise_server_user_ids: ["#{ghes_vss_user_act.remote_user_id}:#{@enterprise_installation.host_name}:Member"],
      github_com_user: true,
      enterprise_server_user: true,
      visual_studio_subscription_user: true,
      license_type: "Visual Studio subscription",
      github_com_profile: ViewModel::URLs.new.user_url(ghes_vss_user),
      github_com_member_roles: [],
      github_com_enterprise_roles: [],
      github_com_verified_domain_emails: [ghes_vss_user_email],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [ghes_vss_user_email],
      visual_studio_license_status: "Matched to Cloud + Server",
      visual_studio_subscription_email: ghes_vss_user_email,
      total_user_accounts: 2
    },
    {
      github_com_login: org_invited_user.display_login,
      github_com_name: org_invited_user.profile.name,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(org_invited_user),
      github_com_member_roles: [],
      github_com_enterprise_roles: ["Pending invitation"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [@organization.name],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    {
      github_com_login: outside_collab_user_pending.display_login,
      github_com_name: nil,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(outside_collab_user_pending),
      github_com_member_roles: [],
      github_com_enterprise_roles: ["Pending outside collaborator invitation"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    }]

    expected_page_2 = [{
      github_com_login: outside_collab_user_accepted.display_login,
      github_com_name: nil,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(outside_collab_user_accepted),
      github_com_member_roles: [],
      github_com_enterprise_roles: ["Outside collaborator"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    { # ghes-only user with different primary email addresses on different instances
      github_com_login: "",
      github_com_name: nil,
      enterprise_server_user_ids: [
        "#{ghes_user2_act.remote_user_id}:#{@enterprise_installation.host_name}:Member",
        "#{ghes_user2_act2.remote_user_id}:#{@enterprise_installation.host_name}:Owner"
      ].sort,
      github_com_user: false,
      enterprise_server_user: true,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: nil,
      github_com_member_roles: [],
      github_com_enterprise_roles: [],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: nil,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [ghes_user2_email, ghes_user2_email2].sort,
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 2
    },
    { # ghes-only user with a primary email
      github_com_login: "",
      github_com_name: nil,
      enterprise_server_user_ids: ["#{ghes_user_act.remote_user_id}:#{@enterprise_installation.host_name}:Member"],
      github_com_user: false,
      enterprise_server_user: true,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: nil,
      github_com_member_roles: [],
      github_com_enterprise_roles: [],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: nil,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [ghes_user_email],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    { # org invite by email without a corresponding user
      github_com_login: org_invite_email,
      github_com_name: nil,
      enterprise_server_user_ids: [],
      github_com_user: false,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: nil,
      github_com_member_roles: [],
      github_com_enterprise_roles: ["Pending invitation"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [@organization.name],
      github_com_two_factor_auth: nil,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 0,
    },
    { # ghes-only user without a primary email
      github_com_login: "",
      github_com_name: nil,
      enterprise_server_user_ids: ["#{noemail_ghes.remote_user_id}:#{@enterprise_installation.host_name}:Member"],
      github_com_user: false,
      enterprise_server_user: true,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: nil,
      github_com_member_roles: [],
      github_com_enterprise_roles: [],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: nil,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    { # org invite by email using an allocated VSS license
      github_com_login: "vss-org@invite.com",
      github_com_name: nil,
      enterprise_server_user_ids: [],
      github_com_user: false,
      enterprise_server_user: false,
      visual_studio_subscription_user: true,
      license_type: "Visual Studio subscription",
      github_com_profile: nil,
      github_com_member_roles: [],
      github_com_enterprise_roles: ["Pending invitation"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [@organization.name],
      github_com_two_factor_auth: nil,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: "Pending Invitation",
      visual_studio_subscription_email: "vss-org@invite.com",
      total_user_accounts: 0
    }]

    assert_equal 12, hash_page_1[:total_seats_consumed]
    assert_equal 6, hash_page_1[:users].size
    assert_equal 12, hash_page_2[:total_seats_consumed]
    assert_equal 6, hash_page_2[:users].size

    0..expected_page_1.size.times do |i|
      assert_equal expected_page_1[i], hash_page_1[:users][i]
    end
    0..expected_page_2.size.times do |i|
      assert_equal expected_page_2[i], hash_page_2[:users][i]
    end
  end

  context "Metered licenses enabled" do
    test "returns hash with cost center name per member" do
      @business.customer.create_billing_platform_enabled_product(copilot: true)

      member_one = create(:user)
      member_two = create(:user)
      @organization.add_member(member_one)
      @organization.add_member(member_two)

      first_cost_center = {
        costCenterKey: { customerId: @business.customer_id.to_s, targetType: :ZuoraSubscription, targetId: "", uuid: "fcb5aa21-778b-411f-90ec-2409e3713bc6" },
            name: "First Cost Center",
            resources: [
              { id: member_one.id.to_s, type: :User },
            ]
      }
      second_cost_center = {
        costCenterKey: { customerId: @business.customer_id.to_s, targetType: :ZuoraSubscription, targetId: "", uuid: "e78d46ca-2b4a-4c3f-b9e5-bc9c3db6d515" },
        name: "Second Cost Center",
        resources: [
          { id: member_two.id.to_s, type: :User }
        ]
      }
      Billing::Platform::Api::Client.any_instance
            .stubs(:get_all_cost_centers)
            .with(customer_id: @business.customer_id.to_s, use_cache: true)
            .returns({ costCenters: [
              first_cost_center,
              second_cost_center,
            ] })

      hash = Business::LicenseAttributer.new(@business).license_usage_hash
      hash[:users].each do |user|
        case user[:github_com_login]
        when member_one.login
          assert_equal first_cost_center[:name], user[:github_com_cost_center]
        when member_two.login
          assert_equal second_cost_center[:name], user[:github_com_cost_center]
        else
          assert_nil user[:github_com_cost_center]
        end
      end
    end

    test "returns hash with cost center as unavailable when api errors" do
      @business.customer.create_billing_platform_enabled_product(copilot: true)

      Billing::Platform::Api::Client.any_instance
        .stubs(:get_all_cost_centers)
        .with(customer_id: @business.customer_id.to_s, use_cache: true)
        .returns(Billing::Platform::Api::Error.new("Test error"))

      hash = Business::LicenseAttributer.new(@business).license_usage_hash
      hash[:users].each do |user|
        assert_equal user[:github_com_cost_center], "Unavailable"
      end
    end

    test "returns previously licensed users licensed at some point in the current billing period" do
      @business.customer.update(metered_plan: true)
      member_one = create(:user)

      license = Licensify::Services::V1::CustomerLicense.new(
        licensee: Licensify::Services::V1::Licensee.new(
          type: Licensify::Services::V1::LicenseeType::LICENSEE_TYPE_USER,
          id: member_one.id.to_s
        ),
        enablements: [
          Licensify::Services::V1::CustomerLicenseEnablement.new(
            reason: Licensify::Services::V1::EnablementReason::ENABLEMENT_REASON_ORG_MEMBERSHIP,
            enablementIds: ["123"]
          )
        ],
        expiresAt: Google::Protobuf::Timestamp.new(seconds: (::GitHub::Billing.today.beginning_of_month.beginning_of_day + 1.day).to_i, nanos: 0),
        licenseStatus: :LICENSE_STATUS_DEACTIVATED
      )

      ::Licensify::Client.any_instance.expects(:get_customer_licenses)
        .with(Licensify::Services::V1::GetCustomerLicensesRequest.new(
          customerId: T.must(@business.customer.id),
          product: Licensify::Services::V1::Product::PRODUCT_SDLC,
        ))
        .returns(Twirp::ClientResp.new(
          data: { "customerLicenses" => [license] },
          error: nil,
        )).once

      hash = Business::LicenseAttributer.new(@business, options: { include_users_removed_this_cycle: true }).license_usage_hash

      member_one_row = hash[:users].find { |row| row[:github_com_login] == member_one.login }
      refute_nil member_one_row
      assert_equal member_one_row[:ghe_license_active], false
    end

    test "Does not return licensed users only licensed in previous billing periods" do
      @business.customer.update(metered_plan: true)
      member_one = create(:user)

      Billing::Platform::Api::Client.any_instance
        .stubs(:get_subscribed_items)
        .returns({
          subscribedItems: [{
            subscriptionId: member_one.id,
            status: :Inactive,
            subscribedAt: (::GitHub::Billing.today.beginning_of_month.beginning_of_day - 2.days).to_i * 1000,
            lastBilledForAt: (::GitHub::Billing.today.beginning_of_month.beginning_of_day - 1.day).to_i * 1000
          }]
        })

      hash = Business::LicenseAttributer.new(@business, options: { include_users_removed_this_cycle: true }).license_usage_hash

      member_one_row = hash[:users].find { |row| row[:github_com_login] == member_one.login }
      assert_nil member_one_row
    end

    test "Does not return an end date for currently licensed users" do
      @business.customer.update(metered_plan: true)
      member_one = create(:user)

      license = Licensify::Services::V1::CustomerLicense.new(
        licensee: Licensify::Services::V1::Licensee.new(
          type: Licensify::Services::V1::LicenseeType::LICENSEE_TYPE_USER,
          id: member_one.id.to_s
        ),
        enablements: [
          Licensify::Services::V1::CustomerLicenseEnablement.new(
            reason: Licensify::Services::V1::EnablementReason::ENABLEMENT_REASON_ORG_MEMBERSHIP,
            enablementIds: ["123"]
          )
        ],
        expiresAt: Google::Protobuf::Timestamp.new(seconds: 253402300799, nanos: 0),
        licenseStatus: :LICENSE_STATUS_ACTIVE
      )

      ::Licensify::Client.any_instance.expects(:get_customer_licenses)
        .with(Licensify::Services::V1::GetCustomerLicensesRequest.new(
          customerId: T.must(@business.customer.id),
          product: Licensify::Services::V1::Product::PRODUCT_SDLC,
        ))
        .returns(Twirp::ClientResp.new(
          data: { "customerLicenses" => [license] },
          error: nil,
        )).twice

      subscription_information = Business::LicenseAttributer.new(@business, options: { include_users_removed_this_cycle: true }).recent_user_subscription_information
      assert_nil subscription_information.dig(member_one.id, :subscription_end)

      hash = Business::LicenseAttributer.new(@business, options: { include_users_removed_this_cycle: true }).license_usage_hash

      member_one_row = hash[:users].find { |row| row[:github_com_login] == member_one.login }
      refute_nil member_one_row
      assert_equal member_one_row[:ghe_license_active], true
      assert_nil member_one_row[:ghe_license_end_date]
    end
  end

  context "Metered licenses disabled" do
    test "returns hash without the cost center key" do
      hash = Business::LicenseAttributer.new(@business).license_usage_hash
      refute_includes hash[:users].first&.keys, :github_com_cost_center
    end
  end

  test "returns bundled ghas license usage of users for enterprises when enabled" do
    response = Twirp::ClientResp.new(data: ::Turboghas::Proto::GetActiveCommittersResponse.new(users: [
      ::Turboghas::Proto::GetActiveCommittersResponse::User.new(id: @org_admin.id),
    ]))

    ::Turboghas::AdvancedSecurityAPI.any_instance.stubs(:get_active_committers)
      .with(entity_id: @business.id, entity_type: GitHub::Turboghas.entity_type_for(@business), features: GitHub::Turboghas::SKU::Bundled.features)
      .returns(response)

    Business.any_instance.stubs(:advanced_security_purchased?).returns(true)
    Business.any_instance.stubs(:ghas_sku_purchased_for_entity?).returns(true)
    Business::LicenseAttributer.stub_const(:MAX_USER_PROFILE_QUERIES, 3) do
      user = create :user
      @organization.add_member(user)

      hash = Business::LicenseAttributer.new(@business).license_usage_hash

      assert_equal hash[:users].count, 2
      refute_nil hash[:users][0][:github_com_advanced_security_license_user]
      assert_equal hash[:users][0][:github_com_advanced_security_license_user], true
      assert_equal hash[:users][1][:github_com_advanced_security_license_user], false
      refute hash[:users].any? { |u| u.key?(:github_com_code_security_license_user) }
      refute hash[:users].any? { |u| u.key?(:github_com_secret_protection_license_user) }
    end
  end

  test "returns code security license usage of users for enterprises when enabled" do
    response = Twirp::ClientResp.new(data: ::Turboghas::Proto::GetActiveCommittersResponse.new(users: [
      ::Turboghas::Proto::GetActiveCommittersResponse::User.new(id: @org_admin.id),
    ]))

    ::Turboghas::AdvancedSecurityAPI.any_instance.stubs(:get_active_committers)
      .with(entity_id: @business.id, entity_type: GitHub::Turboghas.entity_type_for(@business), features: GitHub::Turboghas::SKU::CodeSecurity.features)
      .returns(response)

    Business.any_instance.stubs(:code_security_purchased?).returns(true)
    Business::LicenseAttributer.stub_const(:MAX_USER_PROFILE_QUERIES, 3) do
      user = create :user
      @organization.add_member(user)

      hash = Business::LicenseAttributer.new(@business).license_usage_hash

      assert_equal hash[:users].count, 2
      refute_nil hash[:users][0][:github_com_code_security_license_user]
      assert_equal hash[:users][0][:github_com_code_security_license_user], true
      assert_equal hash[:users][1][:github_com_code_security_license_user], false
      refute hash[:users].any? { |u| u.key?(:github_com_advanced_security_license_user) }
    end
  end

  test "returns secret protection license usage of users for enterprises when enabled" do
    response = Twirp::ClientResp.new(data: ::Turboghas::Proto::GetActiveCommittersResponse.new(users: [
      ::Turboghas::Proto::GetActiveCommittersResponse::User.new(id: @org_admin.id),
    ]))

    ::Turboghas::AdvancedSecurityAPI.any_instance.stubs(:get_active_committers)
      .with(entity_id: @business.id, entity_type: GitHub::Turboghas.entity_type_for(@business), features: GitHub::Turboghas::SKU::SecretSecurity.features)
      .returns(response)

    Business.any_instance.stubs(:secret_protection_purchased?).returns(true)
    Business::LicenseAttributer.stub_const(:MAX_USER_PROFILE_QUERIES, 3) do
      user = create :user
      @organization.add_member(user)

      hash = Business::LicenseAttributer.new(@business).license_usage_hash

      assert_equal hash[:users].count, 2
      refute_nil hash[:users][0][:github_com_secret_protection_license_user]
      assert_equal hash[:users][0][:github_com_secret_protection_license_user], true
      assert_equal hash[:users][1][:github_com_secret_protection_license_user], false
      refute hash[:users].any? { |u| u.key?(:github_com_advanced_security_license_user) }
    end
  end
end if GitHub.billing_enabled?

class EmuBusinessLicenseAttributerLicenseUsageHash < GitHub::TestCase
  include ExternalGroupHelpers
  extend GitHub::FeatureFlagTestHelper

  fixtures do
    @owner = create(:emu, :owner)
    @business = @owner.enterprise_managed_business
    @first_admin = @business.find_first_emu_owner
    @organization = create :organization, business: @business, admin: @owner
  end

  setup do
    disable_feature_flag(:disable_external_group_team_reconcile_job)
  end

  test "returns a hash indicating no license usage when no users in business" do
    owner = create(:emu, :owner)
    enterprise = owner.enterprise_managed_business
    hash = Business::LicenseAttributer.new(enterprise).license_usage_hash

    assert_equal hash[:total_seats_consumed], 0
    assert_empty hash[:users]
  end

  test "returns the correct number of users for large enterprises" do
    Business::LicenseAttributer.stub_const(:MAX_USER_PROFILE_QUERIES, 3) do
      create_list(:emu, 10, business: @business).each { |u| @organization.add_member(u) }
      hash = Business::LicenseAttributer.new(@business).license_usage_hash

      assert_equal hash[:users].count, 11 # 10 users + 1 owner
    end
  end

  test "sets Guest Collaborator value" do
    # User with a Guest Collaborator role
    guest_collaborator_org_membership = create :emu, :guest_collaborator, login: "guest-collaborator", business: @business
    external_group = create(:external_group, :with_team, business: @business).reload
    team = external_group.external_group_teams.first.team
    perform_enqueued_jobs(only: [BusinessUpdateLicenseUsageJob]) do
      team.add_member(guest_collaborator_org_membership)
      ExternalIdentityGroupMembership.create(external_group: external_group, external_identity: guest_collaborator_org_membership.external_identities.first)
      reconcile_external_group_teams(external_group: external_group)
    end
    hash = Business::LicenseAttributer.new(@business.reload).license_usage_hash

    assert_includes hash[:users][1][:github_com_enterprise_roles], "Guest Collaborator"
  end

  test "Non-licensed EMU users see a different role & status than regular users" do
    create(:enterprise_agreement, business: @business)

    # Assignment without user
    create(:licensing_bundled_license_assignment, business: @business, user: nil, email: "variety_assignment_wo_user@example.com")

    perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)
    @business = Business.find(@business.id)
    hash = Business::LicenseAttributer.new(@business, options: { include_nonlicensed_roles: true }).license_usage_hash

    assert_equal 1, hash[:total_seats_consumed]
    assert_equal 3, hash[:users].size

    hash_user = hash[:users].last
    expected = {
      github_com_login: "variety_assignment_wo_user@example.com",
      github_com_name: nil,
      enterprise_server_user_ids: [],
      github_com_user: false,
      enterprise_server_user: false,
      visual_studio_subscription_user: true,
      license_type: nil,
      github_com_profile: nil,
      github_com_member_roles: [],
      github_com_enterprise_roles: ["Unlinked Visual Studio license subscription"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: nil,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: "Not a member of any enterprise organizations",
      visual_studio_subscription_email: "variety_assignment_wo_user@example.com",
      total_user_accounts: 0
    }

    assert_equal expected, hash_user
  end

  test "Unaffiliated EMU users see a different role & status than regular users" do
    create(:enterprise_agreement, business: @business)

    emu_unaffiliated = create(:emu, business: @business)

    perform_enqueued_jobs(only: [BusinessUpdateLicenseUsageJob, BusinessUserAccountUpdateAttributesJob])
    @business = Business.find(@business.id)
    hash = Business::LicenseAttributer.new(@business, options: { include_nonlicensed_roles: true }).license_usage_hash
    assert_includes Business::LicenseAttributer.new(@business, options: { include_nonlicensed_roles: true }).nonlicensed_roles_user_ids, emu_unaffiliated.id

    assert_equal 1, hash[:total_seats_consumed]
    assert_equal 3, hash[:users].size

    hash_user = hash[:users].last
    expected = {
      github_com_login: emu_unaffiliated.login,
      github_com_name: emu_unaffiliated.profile_name,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: nil,
      github_com_profile: ViewModel::URLs.new.user_url(emu_unaffiliated),
      github_com_member_roles: [],
      github_com_enterprise_roles: ["Unaffiliated user"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    }

    assert_equal expected, hash_user
  end

  test "returns a hash for all types of users in business" do
    create(:enterprise_agreement, business: @business)

    # These should not appear anywhere in the hash
    verified_org_domain = create(:verifiable_domain, owner: @organization, domain: "example.com", verified: true)
    verified_bus_domain = create(:verifiable_domain, owner: @business, domain: "xyz.lol", verified: true)
    approved_org_domain = create(:verifiable_domain, owner: @organization, domain: "org-approved.com", approved: true)
    approved_bus_domain = create(:verifiable_domain, owner: @business, domain: "bus-approved.com", approved: true)

    # this normal EMU should consume a license because it's an explicit org member (directly added)
    member = create :emu, login: "member", business: @business
    @organization.add_member(member)

    team = create :team, organization: @organization
    external_group = create :external_group, :with_members, business: @business, number_of_members: 0
    external_group_team = ExternalGroupTeam.create(external_group: external_group, team: team)
    ExternalGroupTeamLinkJob.perform_now(external_group_team.id, caller: self.class.name)

    # this guest collaborator should consume a license because it's a derived org member (indirectly added)
    guest_collaborator_one = create(:emu, :guest_collaborator, business: @business)

    team.add_member(guest_collaborator_one)
    ExternalIdentityGroupMembership.create(external_group: external_group, external_identity: guest_collaborator_one.external_identities.first)
    reconcile_external_group_teams(external_group: external_group)

    assert @organization.member? guest_collaborator_one

    # this guest collaborator should consume a license because it's an explicit org member (directly added)
    guest_collaborator_two = create :emu, :guest_collaborator, login: "restricted-user-org-membership", business: @business
    @organization.add_member(guest_collaborator_two)

    # this guest collaborator won't show up because it shouldn't consume a license since it has no org memberships
    guest_collaborator_three = create :emu, :guest_collaborator, login: "restricted-user-no-membership", business: @business

    perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)
    @business = Business.find(@business.id)
    hash = Business::LicenseAttributer.new(@business).license_usage_hash

    assert_equal 4, hash[:total_seats_consumed]
    assert_equal 4, hash[:users].size

    expected = [{
      github_com_login: @owner.display_login,
      github_com_name: @owner.profile.name,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(@owner),
      github_com_member_roles: @owner.organizations.map { |org| "#{org.name}:Owner" },
      github_com_enterprise_roles: %w[Owner Member],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    {
      github_com_login: member.display_login,
      github_com_name: member.profile.name,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(member),
      github_com_member_roles: ["#{@organization.name}:Member"],
      github_com_enterprise_roles: ["Member"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    {
      github_com_login: guest_collaborator_one.display_login,
      github_com_name: guest_collaborator_one.profile.name,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(guest_collaborator_one),
      github_com_member_roles: guest_collaborator_one.organizations.map { |org| "#{org.name}:Member" },
      github_com_enterprise_roles: ["Member", "Guest Collaborator"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    {
      github_com_login: guest_collaborator_two.display_login,
      github_com_name: guest_collaborator_two.profile.name,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(guest_collaborator_two),
      github_com_member_roles: guest_collaborator_two.organizations.map { |org| "#{org.name}:Member" },
      github_com_enterprise_roles: ["Member", "Guest Collaborator"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    }]

    0..expected.size.times do |i|
      assert_equal T.must(expected[i])[:github_com_login], hash[:users][i][:github_com_login]
      assert_equal T.must(expected[i])[:github_com_name], hash[:users][i][:github_com_name]
      assert_equal T.must(expected[i])[:enterprise_server_user_ids], hash[:users][i][:enterprise_server_user_ids]
      assert_equal T.must(expected[i])[:github_com_user], hash[:users][i][:github_com_user]
      assert_equal T.must(expected[i])[:enterprise_server_user], hash[:users][i][:enterprise_server_user]
      assert_equal T.must(expected[i])[:license_type], hash[:users][i][:license_type]
      assert_equal T.must(expected[i])[:github_com_profile], hash[:users][i][:github_com_profile]
      assert_same_elements T.must(expected[i])[:github_com_member_roles], hash[:users][i][:github_com_member_roles]
      assert_equal T.must(expected[i])[:github_com_enterprise_roles], hash[:users][i][:github_com_enterprise_roles]
      assert_equal T.must(expected[i])[:enterprise_server_user_ids], hash[:users][i][:enterprise_server_user_ids]
      assert_nil T.must(expected[i])[:github_com_saml_name_id], hash[:users][i][:github_com_saml_name_id]
      assert_equal T.must(expected[i])[:github_com_orgs_with_pending_invites], hash[:users][i][:github_com_orgs_with_pending_invites]
      assert_equal T.must(expected[i])[:github_com_two_factor_auth], hash[:users][i][:github_com_two_factor_auth]
      assert_equal T.must(expected[i])[:enterprise_server_primary_emails], hash[:users][i][:enterprise_server_primary_emails]
      assert_nil T.must(expected[i])[:visual_studio_license_status], hash[:users][i][:visual_studio_license_status]
      assert_nil T.must(expected[i])[:visual_studio_subscription_email], hash[:users][i][:visual_studio_subscription_email]
      assert_equal T.must(expected[i])[:total_user_accounts], hash[:users][i][:total_user_accounts]
    end
  end

  test "returns a hash for all types of users in business with pagination" do
    create(:enterprise_agreement, business: @business)

    # These should not appear anywhere in the hash
    verified_org_domain = create(:verifiable_domain, owner: @organization, domain: "example.com", verified: true)
    verified_bus_domain = create(:verifiable_domain, owner: @business, domain: "xyz.lol", verified: true)
    approved_org_domain = create(:verifiable_domain, owner: @organization, domain: "org-approved.com", approved: true)
    approved_bus_domain = create(:verifiable_domain, owner: @business, domain: "bus-approved.com", approved: true)

    # this normal EMU should consume a license because it's an explicit org member (directly added)
    member = create :emu, login: "member", business: @business
    @organization.add_member(member)

    team = create :team, organization: @organization
    external_group = create :external_group, :with_members, business: @business, number_of_members: 0
    external_group_team = ExternalGroupTeam.create(external_group: external_group, team: team)
    ExternalGroupTeamLinkJob.perform_now(external_group_team.id, caller: self.class.name)

    # this guest collaborator should consume a license because it's a derived org member (indirectly added)
    guest_collaborator_one = create(:emu, :guest_collaborator, business: @business)

    team.add_member(guest_collaborator_one)
    ExternalIdentityGroupMembership.create(external_group: external_group, external_identity: guest_collaborator_one.external_identities.first)
    reconcile_external_group_teams(external_group: external_group)

    assert @organization.member? guest_collaborator_one

    # this guest collaborator should consume a license because it's an external group member with explicit org membership (directly added alongside external group team membership)
    guest_collaborator_two = create :emu, :guest_collaborator, login: "restricted-user-org-membership", business: @business
    team.add_member(guest_collaborator_two)
    ExternalIdentityGroupMembership.create(external_group: external_group, external_identity: guest_collaborator_two.external_identities.first)
    reconcile_external_group_teams(external_group: external_group)
    @organization.add_member(guest_collaborator_two)

    # this guest collaborator won't show up because it shouldn't consume a license since it has no org memberships
    guest_collaborator_three = create :emu, :guest_collaborator, login: "restricted-user-no-membership", business: @business

    perform_enqueued_jobs(only: [BusinessUpdateLicenseUsageJob])
    @business = Business.find(@business.id)

    hash_page_1 = Business::LicenseAttributer.new(@business).license_usage_hash(pagination: true, page: 1, per_page: 3)
    hash_page_2 = Business::LicenseAttributer.new(@business).license_usage_hash(pagination: true, page: 2, per_page: 3)

    assert_equal 4, hash_page_1[:total_seats_consumed]
    assert_equal 3, hash_page_1[:users].size
    assert_equal 4, hash_page_2[:total_seats_consumed]
    assert_equal 1, hash_page_2[:users].size

    expected_page_1 = [{
      github_com_login: @owner.display_login,
      github_com_name: @owner.profile.name,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(@owner),
      github_com_member_roles: @owner.organizations.map { |org| "#{org.name}:Owner" },
      github_com_enterprise_roles: %w[Owner Member],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: false,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    {
      github_com_login: member.display_login,
      github_com_name: member.profile.name,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(member),
      github_com_member_roles: ["#{@organization.name}:Member"],
      github_com_enterprise_roles: ["Member"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: false,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    {
      github_com_login: guest_collaborator_one.display_login,
      github_com_name: guest_collaborator_one.profile.name,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(guest_collaborator_one),
      github_com_member_roles: guest_collaborator_one.organizations.map { |org| "#{org.name}:Member" },
      github_com_enterprise_roles: ["Member", "Guest Collaborator"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: false,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    }]

    expected_page_2 = [{
      github_com_login: guest_collaborator_two.display_login,
      github_com_name: guest_collaborator_two.profile.name,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(guest_collaborator_two),
      github_com_member_roles: guest_collaborator_two.organizations.map { |org| "#{org.name}:Member" },
      github_com_enterprise_roles: ["Member", "Guest Collaborator"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: false,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    }]

    0..expected_page_1.size.times do |i|
      assert_equal T.must(expected_page_1[i])[:github_com_login], hash_page_1[:users][i][:github_com_login]
      assert_equal T.must(expected_page_1[i])[:github_com_name], hash_page_1[:users][i][:github_com_name]
      assert_equal T.must(expected_page_1[i])[:enterprise_server_user_ids], hash_page_1[:users][i][:enterprise_server_user_ids]
      assert_equal T.must(expected_page_1[i])[:github_com_user], hash_page_1[:users][i][:github_com_user]
      assert_equal T.must(expected_page_1[i])[:enterprise_server_user], hash_page_1[:users][i][:enterprise_server_user]
      assert_equal T.must(expected_page_1[i])[:license_type], hash_page_1[:users][i][:license_type]
      assert_equal T.must(expected_page_1[i])[:github_com_profile], hash_page_1[:users][i][:github_com_profile]
      assert_same_elements T.must(expected_page_1[i])[:github_com_member_roles], hash_page_1[:users][i][:github_com_member_roles]
      assert_equal T.must(expected_page_1[i])[:github_com_enterprise_roles], hash_page_1[:users][i][:github_com_enterprise_roles]
      assert_equal T.must(expected_page_1[i])[:enterprise_server_user_ids], hash_page_1[:users][i][:enterprise_server_user_ids]
      assert_nil T.must(expected_page_1[i])[:github_com_saml_name_id], hash_page_1[:users][i][:github_com_saml_name_id]
      assert_equal T.must(expected_page_1[i])[:github_com_orgs_with_pending_invites], hash_page_1[:users][i][:github_com_orgs_with_pending_invites]
      assert_equal T.must(expected_page_1[i])[:github_com_two_factor_auth], hash_page_1[:users][i][:github_com_two_factor_auth]
      assert_equal T.must(expected_page_1[i])[:enterprise_server_primary_emails], hash_page_1[:users][i][:enterprise_server_primary_emails]
      assert_nil T.must(expected_page_1[i])[:visual_studio_license_status], hash_page_1[:users][i][:visual_studio_license_status]
      assert_nil T.must(expected_page_1[i])[:visual_studio_subscription_email], hash_page_1[:users][i][:visual_studio_subscription_email]
      assert_equal T.must(expected_page_1[i])[:total_user_accounts], hash_page_1[:users][i][:total_user_accounts]
    end

    0..expected_page_2.size.times do |i|
      assert_equal T.must(expected_page_2[i])[:github_com_login], hash_page_2[:users][i][:github_com_login]
      assert_equal T.must(expected_page_2[i])[:github_com_name], hash_page_2[:users][i][:github_com_name]
      assert_equal T.must(expected_page_2[i])[:enterprise_server_user_ids], hash_page_2[:users][i][:enterprise_server_user_ids]
      assert_equal T.must(expected_page_2[i])[:github_com_user], hash_page_2[:users][i][:github_com_user]
      assert_equal T.must(expected_page_2[i])[:enterprise_server_user], hash_page_2[:users][i][:enterprise_server_user]
      assert_equal T.must(expected_page_2[i])[:license_type], hash_page_2[:users][i][:license_type]
      assert_equal T.must(expected_page_2[i])[:github_com_profile], hash_page_2[:users][i][:github_com_profile]
      assert_same_elements T.must(expected_page_2[i])[:github_com_member_roles], hash_page_2[:users][i][:github_com_member_roles]
      assert_equal T.must(expected_page_2[i])[:github_com_enterprise_roles], hash_page_2[:users][i][:github_com_enterprise_roles]
      assert_equal T.must(expected_page_2[i])[:enterprise_server_user_ids], hash_page_2[:users][i][:enterprise_server_user_ids]
      assert_nil T.must(expected_page_2[i])[:github_com_saml_name_id], hash_page_2[:users][i][:github_com_saml_name_id]
      assert_equal T.must(expected_page_2[i])[:github_com_orgs_with_pending_invites], hash_page_2[:users][i][:github_com_orgs_with_pending_invites]
      assert_equal T.must(expected_page_2[i])[:github_com_two_factor_auth], hash_page_2[:users][i][:github_com_two_factor_auth]
      assert_equal T.must(expected_page_2[i])[:enterprise_server_primary_emails], hash_page_2[:users][i][:enterprise_server_primary_emails]
      assert_nil T.must(expected_page_2[i])[:visual_studio_license_status], hash_page_2[:users][i][:visual_studio_license_status]
      assert_nil T.must(expected_page_2[i])[:visual_studio_subscription_email], hash_page_2[:users][i][:visual_studio_subscription_email]
      assert_equal T.must(expected_page_2[i])[:total_user_accounts], hash_page_2[:users][i][:total_user_accounts]
    end
  end
end if GitHub.billing_enabled?
