# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessLicenseDependencyTest < GitHub::TestCase
  include GitHub::LoggerHelper

  fixtures do
    @admin = create :user, login: "admin1"
    @organization = create(:organization, admin: @admin)
    @user = create :user, login: "user"
    @organization.add_member(@user)
    @other_org = create(:organization, admin: @admin)
    @other_private_repo = create(:private_repository, owner: @other_org)
    @business = create(:business, organizations: [@organization, @other_org])
    @owner = @business.owners.first
    unless GitHub.single_business_environment?
      @rando = create :user, login: "rando"
      @emu = create(:emu, :owner)
      @emu_business = @emu.enterprise_managed_business
    end
    perform_enqueued_jobs only: BusinessUpdateLicenseUsageJob
  end

  setup do
    enable_cache_storage
    reset_cache
  end

  teardown do
    disable_cache_storage
  end

  context "#bundled_license_assignments", skip_enterprise: true do
    test "filters out revoked assignments" do
      non_revoked = create(:licensing_bundled_license_assignment, business: @business, revoked: false)
      _revoked = create(:licensing_bundled_license_assignment, business: @business, revoked: true)

      assert_equal [non_revoked], @business.bundled_license_assignments
    end
  end

  context "#available_volume_licenses_with_overages" do
    test "returns the number of available licenses including overages" do
      create(:enterprise_agreement, :visual_studio_bundle, business: @business, seats: 1)
      2.times { create(:licensing_bundled_license_assignment, business: @business) }

      assert_equal 2, @business.available_volume_licenses_with_overages
    end

    test "returns 0 if no licenses are available" do
      assert_equal 0, @business.available_volume_licenses_with_overages
    end
  end

  context "#volume_license_overages" do
    test "returns the number of overallocated volume licenses" do
      create(:enterprise_agreement, :visual_studio_bundle, business: @business, seats: 1)
      2.times { create(:licensing_bundled_license_assignment, business: @business) }

      assert_equal 1, @business.volume_license_overages
    end

    test "returns 0 if no licenses are available" do
      assert_equal 0, @business.volume_license_overages
    end
  end

  context "#total_purchased_licenses" do
    test "returns the sum of the standalone licenses and the licenses on active visual studio bundle enterprise agreements" do
      @business.update!(seats: 5)
      create(:enterprise_agreement, :visual_studio_bundle, business: @business, seats: 50)
      create(:enterprise_agreement, :visual_studio_bundle, business: @business, seats: 500)
      create(:enterprise_agreement, :visual_studio_bundle, :inactive, business: @business, seats: 5000)

      assert_equal 555, @business.total_purchased_licenses
    end

    test "returns the number of the standalone licenses and if there are no active visual studio bundle enterprise agreements" do
      @business.update!(seats: 5)
      create(:enterprise_agreement, :visual_studio_bundle, :inactive, business: @business, seats: 50)

      assert_equal 5, @business.total_purchased_licenses
    end
  end

  context "#total_consumed_licenses" do
    if GitHub.single_business_environment?
      test "returns the count of used seats" do
        assert_equal 3, @business.total_consumed_licenses
      end
    else
      context "when volume licensing and VSS is enabled" do
        test "returns the number of consumed licenses (including non-revoked bundled license assignments even if the email/user doesn't otherwise have a relationship to the business" do
          create(:enterprise_agreement, :visual_studio_bundle, business: @business)
          create(:licensing_bundled_license_assignment, business: @business)
          create(:licensing_bundled_license_assignment, business: @business, revoked: true)

          assert_equal 2, @business.total_consumed_licenses
        end
      end

      context "when volume licensing is not enabled" do
        test "returns the number of consumed licenses" do
          assert_equal 2, @business.total_consumed_licenses
        end
      end
    end
  end

  context "#consumed_pending_invitation_licenses", skip_enterprise: true do
    test "counts pending member invites" do
      assert_difference("@business.consumed_pending_invitation_licenses", 1) do
        @other_org.invite @rando, inviter: @admin
        perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)
        @business = Business.find(@business.id)
      end
    end

    test "does not count email invitations for existing org users" do
      assert_difference("@business.consumed_pending_invitation_licenses", 0) do
        @user.add_email("user@example.com", is_primary: true)
        @user.primary_user_email.verify!

        @other_org.invite email: @user.email, inviter: @admin
        perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)
        @business = Business.find(@business.id)
      end
    end

    test "counts pending collaborator invites" do
      assert_difference("@business.consumed_pending_invitation_licenses", 1) do
        RepositoryInvitation.invite_to_repo @rando, @admin, @other_private_repo
        perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)
        @business = Business.find(@business.id)
      end
    end

    test "counts multiple invites for single user as single license" do
      assert_difference("@business.consumed_pending_invitation_licenses", 1) do
        @other_org.invite @rando, inviter: @admin
        @organization.invite @rando, inviter: @admin
        RepositoryInvitation.invite_to_repo @rando, @admin, @other_private_repo
        perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)
        @business = Business.find(@business.id)
      end
    end

    test "counts pending collaborator email invites" do
      assert_difference("@business.consumed_pending_invitation_licenses", 1) do
        RepositoryInvitation.invite_to_repo @rando, @admin, @other_private_repo
        perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)
        @business = Business.find(@business.id)
      end
    end
  end

  context "#consumed_users_access_licenses" do
    test "counts members and owners" do
      # @admin, @user
      assert_equal 2, @business.consumed_users_access_licenses
    end

    test "counts collaborators on private repositories", skip_enterprise: true do
      assert_difference("@business.consumed_users_access_licenses", 1) do
        @other_private_repo.add_member(@rando)
        perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)
        @business = Business.find(@business.id)
      end
    end

    test "does not count public collaborators", skip_enterprise: true do
      public_repo = create(:public_repository, owner: @organization)
      assert_no_difference("@business.consumed_users_access_licenses") do
        public_repo.add_member(@rando)
        perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)
        @business = Business.find(@business.id)
      end
    end
  end

  context "#has_sufficient_licenses_for?", skip_enterprise: true do
    test "false user and email are nil when business is present" do
      org = create(:organization)
      other_org = create(:organization)
      other_org.add_member(create(:user))
      business = create(:business, seats: 3, organizations: [org, other_org])
      perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)

      refute business.has_sufficient_licenses_for?(user: nil, email: nil)
    end

    test "true if existing license for email when business is present" do
      org = create(:organization)
      other_org = create(:organization)
      business = create(:business, seats: 3, organizations: [org, other_org])
      invitee = "fox.mulder@github.com"

      inviter = OrganizationInviter.new(other_org, actor: other_org.admins.first, email: invitee.upcase)
      perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)
      assert inviter.invite_user

      # Need to load a fresh business to avoid stale memoization
      business = Business.find(business.id)
      assert business.has_sufficient_licenses_for?(email: invitee.titleize)
    end

    test "true if existing license for user when business is present" do
      org = create(:organization)
      other_org = create(:organization)
      user = create(:user)
      other_org.add_member(user)
      business = create(:business, seats: 3, organizations: [org, other_org])
      perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)

      assert business.has_sufficient_licenses_for?(user: user)
    end

    test "true if there are licenses remaining for enterprise when business is present" do
      org = create(:organization)
      other_org = create(:organization)
      business = create(:business, seats: 3, organizations: [org, other_org])
      perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)

      assert business.has_sufficient_licenses_for?(user: create(:user))
    end

    test "false if no licenses remaining for enterprise when business is present" do
      org = create(:organization)
      other_org = create(:organization)
      business = create(:business, seats: 2, organizations: [org, other_org])
      perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)

      refute business.has_sufficient_licenses_for?(user: create(:user))
    end

    test "true if the user has an existing license, even if the business is overallocated" do
      org = create(:organization)
      business = create(:business, seats: 1, organizations: [org])
      perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)
      business.update_columns(seats: business.total_consumed_licenses - 1) # force overallocation

      assert business.has_sufficient_licenses_for?(user: org.admins.first)
    end

    test "has sufficient licenses if the user is covered by a bundled license assignment" do
      business = create(:business, :volume_licensed, seats: 0)
      user = create(:user)
      create(:licensing_bundled_license_assignment, business: business, user: user)
      perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)

      assert business.has_sufficient_licenses_for?(user: user)
    end

    test "has sufficient licenses if the email is covered by a bundled license assignment" do
      business = create(:business, :volume_licensed, seats: 0)
      bundled_license_assignment = create(:licensing_bundled_license_assignment, business: business)
      perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)

      assert business.has_sufficient_licenses_for?(email: bundled_license_assignment.email)
    end

    test "has sufficient licenses if the email is an existing user's email" do
      org = create(:organization)
      business = create(:business, seats: 1, organizations: [org])

      user = create(:user)
      user.add_email("user@example.com", is_primary: true)
      user.primary_user_email.verify!
      org.add_member(user)
      perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)

      # Reload to avoid stale memoization
      business = Business.find(business.id)
      assert business.has_sufficient_licenses_for?(email: user.email)
    end

    test "does not have sufficient licenses and the user is only covered by a revoked bundled license assignment" do
      business = create(:business, :volume_licensed, seats: 0)
      user = create(:user)
      create(:licensing_bundled_license_assignment, business: business, user: user, revoked: true)
      perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)

      assert business.has_sufficient_licenses_for?(user: user)
    end

    test "does not have sufficient licenses and the email is only covered by a revoked bundled license assignment" do
      business = create(:business, :volume_licensed, seats: 0)
      bundled_license_assignment = create(:licensing_bundled_license_assignment, business: business, revoked: true)
      perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)

      assert business.has_sufficient_licenses_for?(email: bundled_license_assignment.email)
    end
  end

  context "#has_sufficient_licenses_for_users?", skip_enterprise: true do
    test "false user and email are nil when business is present" do
      org = create(:organization)
      other_org = create(:organization)
      other_org.add_member(create(:user))
      business = create(:business, seats: 4, organizations: [org, other_org])
      perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)

      refute business.has_sufficient_licenses_for_users?(user_ids: nil, emails: nil)
    end

    test "true if existing license for email when business is present" do
      org = create(:organization)
      other_org = create(:organization)
      business = create(:business, seats: 4, organizations: [org, other_org])
      invitee = "fox.mulder@github.com"

      inviter = OrganizationInviter.new(other_org, actor: other_org.admins.first, email: invitee.upcase)
      assert inviter.invite_user

      invitee2 = "fox.mulder@github.com"

      inviter = OrganizationInviter.new(other_org, actor: other_org.admins.first, email: invitee2.upcase)
      assert inviter.invite_user
      perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)

      # Need to load a fresh business to avoid stale memoization
      business = Business.find(business.id)
      assert business.has_sufficient_licenses_for_users?(emails: [invitee.titleize, invitee2.tableize])
    end

    test "true if existing license for user when business is present" do
      org = create(:organization)
      other_org = create(:organization)
      user = create(:user)
      other_org.add_member(user)
      user2 = create(:user)
      other_org.add_member(user2)
      business = create(:business, seats: 4, organizations: [org, other_org])
      perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)

      assert business.has_sufficient_licenses_for_users?(user_ids: [user, user2].map(&:id))
    end

    test "true if there are licenses remaining for enterprise when business is present" do
      org = create(:organization)
      other_org = create(:organization)
      business = create(:business, seats: 4, organizations: [org, other_org])
      perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)

      user = create(:user)
      user2 = create(:user)

      assert business.has_sufficient_licenses_for_users?(user_ids: [user, user2].map(&:id))
    end

    test "false if no licenses remaining for enterprise when business is present" do
      org = create(:organization)
      other_org = create(:organization)
      business = create(:business, seats: 2, organizations: [org, other_org])
      perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)

      refute business.has_sufficient_licenses_for_users?(user_ids: [create(:user)].map(&:id))
    end

    test "true if the user has an existing license, even if the business is overallocated" do
      org = create(:organization)
      business = create(:business, seats: 1, organizations: [org])
      perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)
      business.update_columns(seats: business.total_consumed_licenses - 1) # force overallocation

      assert business.has_sufficient_licenses_for_users?(user_ids: [org.admins.first].map(&:id))
    end

    test "has sufficient licenses if the user is covered by a bundled license assignment" do
      business = create(:business, :volume_licensed, seats: 0)
      user = create(:user)
      create(:licensing_bundled_license_assignment, business: business, user: user)
      perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)

      assert business.has_sufficient_licenses_for_users?(user_ids: [user].map(&:id))
    end

    test "has sufficient licenses if the email is covered by a bundled license assignment" do
      business = create(:business, :volume_licensed, seats: 0)
      bundled_license_assignment = create(:licensing_bundled_license_assignment, business: business)
      perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)

      assert business.has_sufficient_licenses_for_users?(emails: [bundled_license_assignment.email])
    end

    test "has sufficient licenses if the email is an existing user's email" do
      org = create(:organization)
      business = create(:business, seats: 1, organizations: [org])

      user = create(:user)
      user.add_email("user@example.com", is_primary: true)
      user.primary_user_email.verify!
      org.add_member(user)
      perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)

      # Reload to avoid stale memoization
      business = Business.find(business.id)
      assert business.has_sufficient_licenses_for_users?(emails: [user.email])
    end

    test "does not have sufficient licenses and the user is only covered by a revoked bundled license assignment" do
      business = create(:business, :volume_licensed, seats: 0)
      user = create(:user)
      create(:licensing_bundled_license_assignment, business: business, user: user, revoked: true)
      perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)

      assert business.has_sufficient_licenses_for_users?(user_ids: [user].map(&:id))
    end

    test "does not have sufficient licenses and the email is only covered by a revoked bundled license assignment" do
      business = create(:business, :volume_licensed, seats: 0)
      bundled_license_assignment = create(:licensing_bundled_license_assignment, business: business, revoked: true)
      perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)

      assert business.has_sufficient_licenses_for_users?(emails: [bundled_license_assignment.email])
    end
  end

  context "#total_invitable_purchased_licenses", skip_enterprise: true do
    test "return seats when not on enterprise agreement" do
      business = create(:business, seats: 15)

      assert_equal 15, business.total_invitable_purchased_licenses
    end

    test "returns seats without volume seats when on enterprise agreement" do
      business = create(:business, seats: 15)
      create(:enterprise_agreement, business: business, seats: 5)

      assert_equal 15, business.total_invitable_purchased_licenses
    end

    test "returns zero when seats is set to nil" do
      business = Business.new(seats: nil)

      assert_equal 0, business.total_invitable_purchased_licenses
    end
  end

  context "#available_invitable_licenses" do
    if GitHub.single_business_environment?
      test "returns the sum users on the appliance who are not suspended or the ghost user" do
        _suspended_user = create(:suspended_user)
        _other_user = create(:user)
        # @business has 100 seats and 4 are used for @admin, @user, @owner
        assert_equal 96, @business.available_invitable_licenses
      end
    else
      test "returns the available seats across the business" do
        # @business has 100 seats and 2 are used for @admin and @user
        assert_equal 98, @business.available_invitable_licenses
      end

      test "counts business admins if they've explicitly been added to an organization in the business" do
        @organization.add_member(@owner)
        perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)
        assert_equal 97, @business.available_invitable_licenses
      end

      test "returns a minimum of zero" do
        @business.update_columns(seats: 1)
        assert_equal 0, @business.available_invitable_licenses
      end

      test "considers bundled seats" do
        create(:enterprise_agreement, business: @business)
        user = create(:user)
        @organization.add_member(user)
        perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)
        assert_equal 197, @business.available_invitable_licenses
      end

      test "works for businesses without any orgs" do
        business = create :business, organizations: [], seats: 10
        perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)
        assert_equal 10, business.available_invitable_licenses
      end
    end
  end

  context "#volume_licensing_enabled?" do
    test "returns true when active visual studio bundle agreement exists" do
      @business.enterprise_agreements.create(agreement_id: "test", category: :visual_studio_bundle, status: :active)
      assert @business.volume_licensing_enabled?
    end

    test "returns false when no active visual studio bundle agreement exists" do
      @business.enterprise_agreements.create(agreement_id: "test", category: :visual_studio_bundle, status: :ended)
      refute @business.volume_licensing_enabled?
    end

    test "returns false when no agreement exists" do
      assert_equal 0, @business.enterprise_agreements.count
      refute @business.volume_licensing_enabled?
    end
  end

  context "#consumed_volume_licenses", skip_enterprise: true do
    test "returns count of all bundled license assignments for business, excluding any non-linked to user assignements" do
      create(:enterprise_agreement, :visual_studio_bundle, business: @business)
      _assignment = create(:licensing_bundled_license_assignment, business: @business, user: @user)
      _another_assignment = create(:licensing_bundled_license_assignment, business: @business, user: nil)

      revoked_user = create(:user)
      @organization.add_member(revoked_user)
      _revoked_assignment = create(:licensing_bundled_license_assignment, business: @business, user: revoked_user, revoked: true)
      perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)

      assert_equal 1, @business.reload.consumed_volume_licenses
    end

    test "returns unique count bundled license assignments duplicated for the same user in the same business" do
      create(:enterprise_agreement, :visual_studio_bundle, business: @business)
      assignment = create(:licensing_bundled_license_assignment, business: @business, user: @user)
      assignment.dup.update(subscription_id: SecureRandom.uuid)
      perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)

      assert_equal 1, @business.reload.consumed_volume_licenses
    end

    test "returns 0 if volume licensing is not enabled" do
      _assignment = create(:licensing_bundled_license_assignment, business: @business, user: @user)
      perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)

      assert_equal 0, @business.reload.consumed_volume_licenses
    end

    test "emails seen to be consuming licences that have matching bundled license assignments are included in the count" do
      email = "random@example.com"
      create(:enterprise_agreement, :visual_studio_bundle, business: @business)
      create(:licensing_bundled_license_assignment, business: @business, user: @user)
      create(:licensing_bundled_license_assignment, business: @business, email: email)

      enterprise_installation = create(:enterprise_installation, owner: @business)
      email_based_enterprise_installation_user_account = create(
        :enterprise_installation_user_account,
        enterprise_installation: enterprise_installation,
        business_user_account: create(:business_user_account, business: @business, user: nil),
      )

      create(
        :enterprise_installation_user_account_email,
        enterprise_installation_user_account: email_based_enterprise_installation_user_account,
        email: email,
        primary: true,
      )
      perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)

      assert_equal(2, @business.reload.consumed_volume_licenses)
    end

    test "returned count does not include suspended members" do
      create(:enterprise_agreement, :visual_studio_bundle, business: @emu_business)
      create(:licensing_bundled_license_assignment, business: @emu_business, user: @emu)

      suspended_emu = create(:emu, business: @emu_business)
      create(:licensing_bundled_license_assignment, business: @emu_business, user: suspended_emu)
      suspended_emu.external_identities.first.disable
      suspended_emu.suspend("test")
      perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)
      @emu_business = Business.find(@emu_business.id)

      assert_equal 1, @emu_business.consumed_volume_licenses
    end
  end

  context "#consumed_volume_licenses_per_agreement_count", skip_enterprise: true do
    test "returns count of all bundled license assignments for business, excluding any non-linked to user assignements" do
      agreement_1 = create(:enterprise_agreement, :visual_studio_bundle, business: @business, agreement_id: "agreement_1")
      agreement_2 = create(:enterprise_agreement, :visual_studio_bundle, business: @business, agreement_id: "agreement_2")
      create(:licensing_bundled_license_assignment, business: @business, user: @user, enterprise_agreement_number: agreement_1.agreement_id)
      create(:licensing_bundled_license_assignment, business: @business, user: nil, enterprise_agreement_number: agreement_2.agreement_id)

      revoked_user = create(:user)
      @organization.add_member(revoked_user)
      revoked_assignment = create(:licensing_bundled_license_assignment, business: @business, user: revoked_user, revoked: true)

      assert_equal({ "agreement_1" => 1, "agreement_2" => 0 }, @business.reload.consumed_volume_licenses_per_agreement_count)
    end

    test "returns {} if volume licensing is not enabled" do
      create(:licensing_bundled_license_assignment, business: @business, user: @user)

      assert_equal({}, @business.reload.consumed_volume_licenses_per_agreement_count)
    end

    test "emails seen to be consuming licences that have matching bundled license assignments are included in the count" do
      email = "random@example.com"
      agreement_1 = create(:enterprise_agreement, :visual_studio_bundle, business: @business, agreement_id: "agreement_1")
      agreement_2 = create(:enterprise_agreement, :visual_studio_bundle, business: @business, agreement_id: "agreement_2")
      create(:licensing_bundled_license_assignment, business: @business, user: @user, enterprise_agreement_number: agreement_1.agreement_id)
      create(:licensing_bundled_license_assignment, business: @business, email: email, enterprise_agreement_number: agreement_1.agreement_id)

      enterprise_installation = create(:enterprise_installation, owner: @business)
      email_based_enterprise_installation_user_account = create(
        :enterprise_installation_user_account,
        enterprise_installation: enterprise_installation,
        business_user_account: create(:business_user_account, business: @business, user: nil),
      )

      create(
        :enterprise_installation_user_account_email,
        enterprise_installation_user_account: email_based_enterprise_installation_user_account,
        email: email,
        primary: true,
      )

      assert_equal({ "agreement_1" => 2, "agreement_2" => 0 }, @business.reload.consumed_volume_licenses_per_agreement_count)
    end

    test "returned count does not include suspended members" do
      agreement_1 = create(:enterprise_agreement, :visual_studio_bundle, business: @emu_business, agreement_id: "agreement_1")
      agreement_2 = create(:enterprise_agreement, :visual_studio_bundle, business: @emu_business, agreement_id: "agreement_2")
      create(:licensing_bundled_license_assignment, business: @emu_business, user: @emu, enterprise_agreement_number: agreement_1.agreement_id)
      create(:licensing_bundled_license_assignment, business: @emu_business, user: nil, enterprise_agreement_number: agreement_2.agreement_id)

      suspended_emu = create(:emu, business: @emu_business)
      create(:licensing_bundled_license_assignment, business: @emu_business, user: suspended_emu)
      suspended_emu.external_identities.first.disable
      suspended_emu.suspend("test")

      assert_equal({ "agreement_1" => 1, "agreement_2" => 0 }, @emu_business.consumed_volume_licenses_per_agreement_count)
    end
  end

  context "#consumed_enterprise_licenses", skip_enterprise: true do
    test "returns unique count of all enterprise license users" do
      # @organization.admin and @user consume licenses
      assert_equal 2, @business.reload.consumed_enterprise_licenses
    end

    test "returns unique count of all enterprise license users when there are bundled_license_assignments" do
      organization = create(:organization)
      admin = organization.owner
      user1 = create :user
      user2 = create :user
      user3 = create :user
      organization.add_member(user1)
      organization.add_member(user2)
      organization.add_member(user3)
      email1 = "invite1@invite.com"
      email2 = "invite2@invite.com"
      email3 = "invite3@invite.com"
      OrganizationInviter.new(organization, actor: admin, email: email1.upcase).invite_user
      OrganizationInviter.new(organization, actor: admin, email: email2).invite_user
      OrganizationInviter.new(organization, actor: admin, email: email3).invite_user
      business = create(:business, :volume_licensed, organizations: [organization])

      _assigned_bla = create(:licensing_bundled_license_assignment, user: user1, business: business)
      _revoked_bla = create(:licensing_bundled_license_assignment, user: user2, business: business, revoked: true)

      _unassigned_unmatching_bla1 = create(:licensing_bundled_license_assignment, user: create(:user), business: business)
      _unassigned_unmatching_revoked_bla1 = create(:licensing_bundled_license_assignment, user: create(:user), business: business, revoked: true)

      _unassigned_bla = create(:licensing_bundled_license_assignment, email: email1.titleize, business: business)
      _unassigned_revoked_bla = create(:licensing_bundled_license_assignment, email: email2, business: business, revoked: true)

      _unassigned_unmatching_bla2 = create(:licensing_bundled_license_assignment, email: "invite4@invite.com", business: business)
      _unassigned_unmatching_revoked_bla2 = create(:licensing_bundled_license_assignment, email: "invite5@invite.com", business: business, revoked: true)
      business = Business.find(business.id)

      # user1 does not consume a license due to nonrevoked bla (_assigned_bla)
      # admin, user2, and user3 both consume a license
      # email1 does not consume a license due to nonrevoked bla (_unassigned_bla)
      # email2, and email3 both consume a licenses
      assert_equal 5, business.consumed_enterprise_licenses
    end

    test "counts pending member invites" do
      assert_difference("@business.consumed_enterprise_licenses", 1) do
        @other_org.invite @rando, inviter: @admin
        perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)
        @business = Business.find(@business.id) # need to clear memoization of license attributer
      end
    end

    test "does not count pending member invites for existing members" do
      assert_no_difference("@business.consumed_enterprise_licenses") do
        @other_org.invite @user, inviter: @admin
        perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)
        @business = Business.find(@business.id) # need to clear memoization of license attributer
      end
    end

    test "counts pending collaborator invites" do
      assert_difference("@business.consumed_enterprise_licenses", 1) do
        RepositoryInvitation.invite_to_repo_by_email @rando.email, @admin, @other_private_repo
        perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)
        @business = Business.find(@business.id) # need to clear memoization of license attributer
      end
    end

    test "does not counts pending collaborator invites for members" do
      assert_no_difference("@business.consumed_enterprise_licenses") do
        RepositoryInvitation.invite_to_repo @user, @admin, @other_private_repo
        perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)
        @business = Business.find(@business.id) # need to clear memoization of license attributer
      end
    end
  end

  context "#unassigned_user_bundled_license_assignments_count", skip_enterprise: true do
    test "returns count of all unassigned bundled license assignments" do
      organization = create(:organization)
      admin = organization.owner
      user1 = create :user
      organization.add_member(user1)
      email1 = "invite1@invite.com"
      OrganizationInviter.new(organization, actor: admin, email: email1.upcase).invite_user
      business = create(:business, :volume_licensed, organizations: [organization])
      _assigned_bla = create(:licensing_bundled_license_assignment, user: user1, business: business)
      _unassigned_bla1 = create(:licensing_bundled_license_assignment, email: "invite1@invite.com", business: business)
      _unassigned_bla2 = create(:licensing_bundled_license_assignment, email: "invite2@invite.com", business: business)

      assert_equal 2, business.unassigned_user_bundled_license_assignments_count
    end
  end

  context "#assigned_user_bundled_license_assignments_count", skip_enterprise: true do
    test "returns count of all assigned bundled license assignments" do
      organization = create(:organization)
      admin = organization.owner
      user1 = create :user
      organization.add_member(user1)
      email1 = "invite1@invite.com"
      OrganizationInviter.new(organization, actor: admin, email: email1.upcase).invite_user
      business = create(:business, :volume_licensed, organizations: [organization])
      _assigned_bla = create(:licensing_bundled_license_assignment, user: user1, business: business)
      _unassigned_bla1 = create(:licensing_bundled_license_assignment, email: "invite1@invite.com", business: business)
      _unassigned_bla2 = create(:licensing_bundled_license_assignment, email: "invite2@invite.com", business: business)

      assert_equal 1, business.assigned_user_bundled_license_assignments_count
    end
  end

  context "#additional_licenses_required_for_organization", skip_enterprise: true do
    test "returns the number of new licenses required on the business if the organization was to be added" do
      @business.update(seats: 3) # 2 are already consumed

      already_invited_email = "invited@example.com"
      @organization.invite(email: already_invited_email.upcase, inviter: @organization.admins.first)
      @business = Business.find(@business.id) # need to clear memoization of license attributer

      new_organization = create(:organization)
      private_repository = create(:private_repository, owner: new_organization)
      RepositoryInvitation.invite_to_repo_by_email already_invited_email.titleize, new_organization.admins.first, private_repository
      perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)

      # Just need one new license for the admin of new_organization since invited email is already associated
      assert_equal 1, @business.additional_licenses_required_for_organization(new_organization)
    end

    test "returns zero if there's already more than enough licenses available" do
      @business.update(seats: 6) # 2 are already consumed

      new_organization = create(:organization)

      # There will be sufficient room since we have 6 seats and only the organization admins that would consume licenses
      assert_equal 0, @business.additional_licenses_required_for_organization(new_organization)
    end

    test "returns zero if the organization does not require any new licenses even if the business is over-allocated" do
      @business.update_columns(seats: @business.total_consumed_licenses - 1) # force over-alloation

      new_organization = create(:organization, admins: @organization.admins)

      # No _new_ licensable users/emails would be added (even though business is already over-allocated)
      assert_equal 0, @business.additional_licenses_required_for_organization(new_organization)
    end

    test "allows the volume license pool to be considered when determining how many additional licenses are required" do
      @business.update(seats: 3) # 2 are already consumed
      create(:enterprise_agreement, business: @business, seats: 10)

      already_invited_email = "invited@example.com"
      @organization.invite(email: already_invited_email, inviter: @organization.admins.first)

      new_organization = create(:organization)
      new_organization.invite(email: already_invited_email, inviter: new_organization.admins.first)

      # There will be sufficient room since we have 1 enterprise license available and 10 volume licenses available
      assert_equal 0, @business.additional_licenses_required_for_organization(new_organization)
    end

    test "handles bundled license assignments correctly" do
      business = create(:business, :volume_licensed, seats: 0)
      business.enterprise_agreements.first.update!(seats: 2)
      organization = create(:organization)
      user = organization.admins.first
      revoked_user = create(:user)
      email = "invitee@example.com"
      revoked_email = "revoked@example.com"
      organization.add_member(revoked_user)
      organization.invite(email: email, inviter: user)
      organization.invite(email: revoked_email, inviter: user)
      create(:licensing_bundled_license_assignment, business: business, user: user)
      create(:licensing_bundled_license_assignment, business: business, user: revoked_user, revoked: true)
      create(:licensing_bundled_license_assignment, business: business, email: email)
      create(:licensing_bundled_license_assignment, business: business, email: revoked_email, revoked: true)
      business = Business.find(business.id)

      # excludes assignment not linked to user
      assert_equal 1, business.additional_licenses_required_for_organization(organization)
    end
  end

  context "#additional_licenses_consumed_by_organization", skip_enterprise: true do
    test "returns the number of new licenses that will be consumed if the organization was to be added" do
      already_invited_email = "invited@example.com"
      @organization.invite(email: already_invited_email, inviter: @organization.admins.first)
      @business = Business.find(@business.id) # need to clear memoization of license attributer

      new_organization = create(:organization, public_members: [@organization.admins.first])
      new_organization.invite(email: already_invited_email, inviter: new_organization.admins.first)
      new_organization.invite(email: "notinvited@example.com", inviter: new_organization.admins.first)

      # organization will consume 2 additional seats if added to business
      # 1 for notinvite@example.com and 1 for organization admin
      assert_equal 2, @business.additional_licenses_consumed_by_organization(new_organization)
    end

    test "returns zero if organization has no new users" do
      already_invited_email = "invited@example.com"
      @organization.invite(email: already_invited_email.upcase, inviter: @organization.admins.first)
      @business = Business.find(@business.id) # need to clear memoization of license attributer

      new_organization = create(:organization, admins: [@organization.admins.first])
      private_repository = create(:private_repository, owner: new_organization)
      RepositoryInvitation.invite_to_repo_by_email already_invited_email.titleize, new_organization.admins.first, private_repository

      # organization will consume 0 additional seats if added to business
      assert_equal 0, @business.additional_licenses_consumed_by_organization(new_organization)
    end

    test "handles bundled license assignments correctly", skip_enterprise: true do
      business = create(:business, :volume_licensed, seats: 0)
      business.enterprise_agreements.first.update!(seats: 2)
      organization = create(:organization)
      user = organization.admins.first
      revoked_user = create(:user)
      email = "invitee@example.com"
      revoked_email = "revoked@example.com"
      organization.add_member(revoked_user)
      organization.invite(email: email, inviter: user)
      organization.invite(email: revoked_email, inviter: user)
      create(:licensing_bundled_license_assignment, business: business, user: user)
      create(:licensing_bundled_license_assignment, business: business, user: revoked_user, revoked: true)
      create(:licensing_bundled_license_assignment, business: business, email: email)
      create(:licensing_bundled_license_assignment, business: business, email: revoked_email, revoked: true)
      business = Business.find(business.id)

      # we'll need a license for `revoked_user` and `revoked_email`
      assert_equal 2, business.additional_licenses_consumed_by_organization(organization)
    end

    test "accounts for users in the organization with bundled license assignments using their verified emails", skip_enterprise: true do
      business = create(:business, :volume_licensed, seats: 0)
      business.enterprise_agreements.first.update!(seats: 2)
      admin_user = create(:verified_user)
      organization = create(:organization, admin: admin_user)
      regular_user = create(:verified_user)
      organization.add_member(regular_user)
      create(:licensing_bundled_license_assignment, business: business, email: admin_user.email)
      create(:licensing_bundled_license_assignment, business: business, email: regular_user.email)

      assert_equal 0, business.additional_licenses_consumed_by_organization(organization)
    end
  end

  context "#has_sufficient_licenses_for_organization?", skip_enterprise: true do
    test "returns true if the number of new licenses required is 0" do
      @business.update!(seats: @business.consumed_invitable_licenses)
      new_organization = create(:organization, admins: [@user]) # 0 new admins
      assert @business.has_sufficient_licenses_for_organization?(new_organization)
    end

    test "returns true if the number of new licenses requried is less then available licenses" do
      @business.update!(seats: @business.consumed_invitable_licenses + 1)
      new_organization = create(:organization) # 1 new admin
      assert @business.has_sufficient_licenses_for_organization?(new_organization)
    end

    test "returns false if number of new licenses required is greater than available licenses" do
      @business.update!(seats: @business.consumed_invitable_licenses)
      new_organization = create(:organization) # 1 new admin
      refute @business.has_sufficient_licenses_for_organization?(new_organization)
    end

    test "returns true if all of the organizations licensable users are already licensed on the business, even if the business is overallocated" do
      @business.update_columns(seats: @business.total_consumed_licenses - 1) # force overallocation

      new_organization = create(:organization, admins: [@admin])

      assert @business.has_sufficient_licenses_for_organization?(new_organization)
    end

    test "returns true if all of the orgs licensable emails are already licensed on the business, even if the business is overallocated" do
      existing_org = create(:organization, admins: [@admin])
      new_org = create(:organization, admins: [@admin])
      business = create(:business, organizations: [existing_org], owners: [@admin])
      email = "invited@example.com"
      existing_org.invite(email: email, inviter: @admin)
      business.update_columns(seats: business.consumed_invitable_licenses - 1) # force overallocation
      new_org.invite(email: email, inviter: @admin)
      business = Business.find(business.id) # load the business fresh so licensing is re-calculated

      assert business.has_sufficient_licenses_for_organization?(new_org)
    end

    test "returns false if the business is overallocated and some but not all users are licensed" do
      @unlicensed_user = create(:user)
      @business.update_columns(seats: @business.total_consumed_licenses - 1) # force overallocation

      new_organization = create(:organization, admins: [@admin, @unlicensed_user])

      refute @business.has_sufficient_licenses_for_organization?(new_organization)
    end

    test "handles bundled license assignments correctly", skip_enterprise: true do
      business = create(:business, :volume_licensed, seats: 0)
      organization = create(:organization)
      user = organization.admins.first
      email = "invitee@example.com"
      organization.invite(email: email, inviter: user)
      create(:licensing_bundled_license_assignment, business: business, user: user)
      create(:licensing_bundled_license_assignment, business: business, email: email)

      assert business.has_sufficient_licenses_for_organization?(organization)
    end
  end

  context "#consumed_invitable_licenses" do
    if GitHub.single_business_environment?
      test "returns the sum of unique non-suspended, non-ghost Users on the appliance for GHE" do
        _suspended_user = create(:suspended_user)
        _other_user = create(:user)
        # @business has 4 consumed licenses for @admin, @user, @owner
        assert_equal 4, @business.consumed_invitable_licenses
      end
    else
      test "does not count random users on the system for dotcom" do
        assert_equal 2, @business.consumed_invitable_licenses
      end

      test "counts business admins if they've explicitly been added to an organization in the business" do
        @organization.add_member(@owner)
        perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)

        assert_equal 3, @business.consumed_invitable_licenses
      end

      test "returns the sum of unique users contributing to filled seats across owned orgs" do
        org_admin = create :user
        org = create :organization, admin: org_admin
        another_org = create :organization, admin: org_admin
        @business.add_organization org
        @business.add_organization another_org
        perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)

        number_of_seated_members = @business.organizations.reload.to_a.sum do |organization|
          Organization::LicenseAttributer.new(organization).unique_count
        end

        assert_equal 5, number_of_seated_members # Shows org member count, recounting duplicates across orgs
        # Need to load a fresh business to avoid stale memoization
        assert_equal 3, Business.find(@business.id).consumed_invitable_licenses # Deduplicated across orgs
      end

      test "handles pending invitations via email as unique billable users" do
        org_admin = create :user
        org = create :organization, admin: org_admin
        org.invite(email: "rando@example.org", inviter: org_admin)
        another_org = create :organization, admin: org_admin
        another_org.invite(email: "someone@example.org", inviter: org_admin)
        @business.add_organization org
        @business.add_organization another_org
        perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)

        number_of_seated_members = @business.organizations.reload.to_a.sum do |organization|
          Organization::LicenseAttributer.new(organization).unique_count
        end

        assert_equal 7, number_of_seated_members # Shows org member count, recounting duplicates across orgs
        # Need to load a fresh business to avoid stale memoization
        assert_equal 5, Business.find(@business.id).consumed_invitable_licenses # Deduplicated across orgs
      end

      test "handles pending invitations via email as unique billable users when same email is used across orgs" do
        org_admin = create :user
        org = create :organization, admin: org_admin
        org.invite(email: "rando@example.org", inviter: org_admin)
        another_org = create :organization, admin: org_admin
        another_org.invite(email: "rando@example.org", inviter: org_admin)
        @business.add_organization org
        @business.add_organization another_org
        perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)

        number_of_seated_members = @business.organizations.reload.to_a.sum do |organization|
          Organization::LicenseAttributer.new(organization).unique_count
        end

        assert_equal 7, number_of_seated_members # Shows org member count, recounting duplicates across orgs
        # Need to load a fresh business to avoid stale memoization
        assert_equal 4, Business.find(@business.id).consumed_invitable_licenses # Deduplicated across orgs
      end

      test "works for businesses without any orgs" do
        business = create :business, organizations: []
        assert_equal 0, business.consumed_invitable_licenses
      end
    end
  end

  context "#purchased_volume_licenses", skip_enterprise: true do
    test "sums the seats on active visual studio bundle enterprise agreements" do
      create(:enterprise_agreement, :visual_studio_bundle, business: @business, seats: 1)
      create(:enterprise_agreement, :visual_studio_bundle, business: @business, seats: 10)
      create(:enterprise_agreement, :visual_studio_bundle, :inactive, business: @business, seats: 100)
      create(:enterprise_agreement, :visual_studio_bundle, seats: 1000)

      assert_equal 11, @business.purchased_volume_licenses
    end

    test "zero if there are no active visual studio bundle enterprise agreements" do
      assert_equal 0, @business.purchased_volume_licenses
    end
  end

  context "#additional_licenses_required_for_repository", skip_enterprise: true do
    test "returns needed seats accounting for current and pending outside contributors" do
      existing_email = "existing@example.com"
      @organization.invite(email: existing_email, inviter: @admin)

      @business.update!(seats: @business.consumed_invitable_licenses)

      repository = create(:public_repository, owner: @organization)
      repository.add_member(create(:user))
      create :repository_invitation, repository: repository, invitee: create(:user), email: nil
      create :repository_invitation, repository: repository, invitee: nil, email: "invitee1@example.com"
      create :repository_invitation, repository: repository, invitee: nil, email: "invitee2@example.com"
      create :repository_invitation, repository: repository, invitee: nil, email: existing_email.capitalize

      assert_equal 4, @business.additional_licenses_required_for_repository(repository)
    end
  end

  context "#has_unlimited_seats", skip_enterprise: true do
    test "returns true for metered plans" do
      @business.customer.update! metered_plan: true
      assert @business.has_unlimited_seats?
    end

    test "returns false for trial metered plans" do
      @business.customer.update! metered_plan: true
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now

      refute @business.has_unlimited_seats?
    end

    test "returns false for non-metered plans" do
      refute_predicate @business, :metered_plan?
      refute @business.has_unlimited_seats?
    end

    test "returns true for metered emu businesses" do
      emu_business = create(:business, :enterprise_managed)
      emu_business.customer.update! metered_plan: true

      assert emu_business.has_unlimited_seats?
    end
  end

  context "#license_attributer_cache" do
    if GitHub.single_business_environment?
      test "passes through value in enterprise" do
        @business.license_attributer_cache.set("test", [1, 2])
        assert_equal [3], @business.license_attributer_cache.ids("test") { [3] }
      end
    else
      test "passes through value and updates cache if cached does not exist" do
        assert_nil @business.license_attributer_cache.get("test", :int)
        assert_equal [1, 2], @business.license_attributer_cache.ids("test") { [1, 2] }
        assert_equal [1, 2], @business.license_attributer_cache.get("test", :int)
      end

      test "returns cached value if cached exists" do
        assert_equal [1, 2], @business.license_attributer_cache.ids("test") { [1, 2] }
        assert_equal [1, 2], @business.license_attributer_cache.ids("test") { [3] }
      end

      test "ignores cached value and does not set cache when skip_cache" do
        assert_equal [1, 2], @business.license_attributer_cache.ids("test") { [1, 2] }
        assert_equal [3], @business.license_attributer_cache.ids("test", skip_cache: true) { [3] }
        assert_equal [1, 2], @business.license_attributer_cache.get("test", :int)
      end

      test "stores large number of values in multiple cache keys" do
        ids = (1..65000).map { |i| "#{i}00000".to_i }
        assert_equal ids, @business.license_attributer_cache.ids("test") { ids }
        assert_equal ids, @business.license_attributer_cache.get("test", :int)
      end

      test "cached results don't affect other businesses" do
        business = create(:business)
        @business.license_attributer_cache.set("test", [1, 2])
        assert_equal [3], business.license_attributer_cache.ids("test", skip_cache: true) { [3] }
      end

      test "cache is disabled is license_usage doesn't exist" do
        business = create(:business)
        business.license_usage.destroy
        business.reload
        assert business.license_attributer_cache.disabled?
        perform_enqueued_jobs only: BusinessUpdateLicenseUsageJob do
          business.update_license_usage
        end
        business = Business.find business.id
        refute business.license_attributer_cache.disabled?
      end

      test "cached results reset when license_usage is updated" do
        Timecop.freeze do
          @business.license_attributer_cache.set("test", [1, 2], :int)
          assert_equal [1, 2], @business.license_attributer_cache.get("test", :int)
          Timecop.travel(1.minute)
          @business.license_usage.update(consumed_enterprise_licenses: 100, generated_at: Time.now)
          assert_nil @business.license_attributer_cache.get("test", :int)
        end
      end
    end
  end

  context "#update_license_usage", skip_enterprise: true do
    test "enqueues BusinessUpdateLicenseUsageJob" do
      assert_enqueued_with(job: BusinessUpdateLicenseUsageJob) do
        @business.update_license_usage
      end
    end

    test "enqueues BusinessUserAccountUpdateAttributesJob" do
      assert_enqueued_with(job: BusinessUserAccountUpdateAttributesJob) do
        @business.update_license_usage
      end
    end
  end

  context "#log_license_usage_update" do
    unless GitHub.single_business_environment?
      test "logs update using GitHub::Logger" do
        expected_keys = {
          "gh.business.id": @business.id,
          "gh.business.slug": @business.slug,
          "gh.license_usage.completed": false,
          "gh.license_usage.consumed_enterprise_licenses": 2,
          "gh.license_usage.consumed_volume_licenses": 0,
          "gh.business.seats": @business.seats
        }
        assert_logged(**expected_keys) do
          @business.log_license_usage_update(completed: false)
        end
      end
    end
  end

  context "#metered_server_licenses" do
    test "returns the metered server licenses for the business" do
      ghes_license = create(:licensing_ghes_license, business: @business, seats: 10)
      ghes_license = create(:licensing_ghes_license, business: @business, seats: 20)

      metered_server_licenses = @business.metered_server_licenses

      assert_equal 2, metered_server_licenses.count
      assert_equal 20, metered_server_licenses.first["seats"]
      assert_equal 10, metered_server_licenses.second["seats"]
    end
  end

  context "#user_scoped_cost_centers?" do
    test "returns false for no user scoped, seat-based cost centers, no billing platform enabled products" do
      has_user_scoped_cost_centers = @business.user_scoped_cost_centers?

      assert_equal false, has_user_scoped_cost_centers
    end

    test "returns false for no user scoped, seat-based cost centers, with billing platform enabled products" do
      customer = create(:customer, billing_end_date: GitHub::Billing.today + 1.year)
      @business.update!(customer: customer)
      create :billing_platform_enabled_product, git_lfs: true, customer_id: customer.id

      has_user_scoped_cost_centers = @business.user_scoped_cost_centers?

      assert_equal false, has_user_scoped_cost_centers
    end

    test "returns true for billing platform enabled products with copilot" do
      customer = create(:customer, billing_end_date: GitHub::Billing.today + 1.year)
      @business.update!(customer: customer)
      create :billing_platform_enabled_product, copilot: true, customer_id: customer.id

      has_user_scoped_cost_centers = @business.user_scoped_cost_centers?

      assert_equal true, has_user_scoped_cost_centers
    end

    test "returns true for billing platform enabled products with ghec" do
      customer = create(:customer, billing_end_date: GitHub::Billing.today + 1.year)
      @business.update!(customer: customer)
      create :billing_platform_enabled_product, ghec: true, customer_id: customer.id

      has_user_scoped_cost_centers = @business.user_scoped_cost_centers?

      assert_equal true, has_user_scoped_cost_centers
    end

    test "returns true for billing platform enabled products with ghas" do
      customer = create(:customer, billing_end_date: GitHub::Billing.today + 1.year)
      @business.update!(customer: customer)
      create :billing_platform_enabled_product, ghas: true, customer_id: customer.id

      has_user_scoped_cost_centers = @business.user_scoped_cost_centers?

      assert_equal true, has_user_scoped_cost_centers
    end
  end
end
