# typed: true
# frozen_string_literal: true

require "test_helper"

unless GitHub.single_business_environment?
  class Licensing::BusinessUserAccount::UpdateAttributes::LicensingDependencyTest < GitHub::TestCase
    fixtures do
      @org = create :organization
      @org2 = create :organization
      @private_repo_user = create :user
      @private_repo = create(:private_repository, :minimal, owner: @org)
      @private_repo_org2 = create(:private_repository, :minimal, owner: @org2)

      @public_repo_user = create :user
      @public_repo = create(:public_repository, :minimal, owner: @org)

      @member = create :user

      @business = create :business, organizations: [@org, @org2]
    end

    setup do
      perform_enqueued_jobs(only: [BusinessUserAccountCreateForOrganizationJob]) do
        @private_repo.add_member(@private_repo_user)
        @public_repo.add_member(@public_repo_user)
        @org.add_member @member
      end
      @member_bua = @business.business_user_account_for(@member)
    end

    def update_user_account_attributes(business: @business, user_account_ids: nil)
      attributes = BusinessUserAccount::UpdateAttributes.new(business: business, user_account_ids: user_account_ids)
      attributes.save!
      @member_bua.reload
    end

    context "licenses" do
      test "saves license to user" do
        @business.customer.update!(metered_plan: true, billed_via_billing_platform: true)
        Billing::Platform::Api::Client.any_instance.stubs(:get_customer).with(
          equals({ customer_id: @business.customer.id })
        ).returns({ "customer": { "customerId": @business.customer.id.to_s } })
        update_user_account_attributes
        assert @member_bua.has_ghec_license?
        assert_equal :enterprise_license, @member_bua.ghec_license_type
      end

      test "will change license for user" do
        @business.customer.update!(metered_plan: true, billed_via_billing_platform: true)
        Billing::Platform::Api::Client.any_instance.stubs(:get_customer).with(
          equals({ customer_id: @business.customer.id })
        ).returns({ "customer": { "customerId": @business.customer.id.to_s } })
        update_user_account_attributes
        assert_equal :enterprise_license, @member_bua.ghec_license_type

        create(:enterprise_agreement, :visual_studio_bundle, business: @business, seats: 1)
        create(:licensing_bundled_license_assignment, user: @member, business: @business)
        update_user_account_attributes
        assert_equal :vss_bundle_license, @member_bua.ghec_license_type
      end

      test "does not assign a license to unlicensed users" do
        @business.customer.update!(metered_plan: true, billed_via_billing_platform: true)
        Billing::Platform::Api::Client.any_instance.stubs(:get_customer).with(
          equals({ customer_id: @business.customer.id })
        ).returns({ "customer": { "customerId": @business.customer.id.to_s } })
        update_user_account_attributes
        public_repo_user_bua = @business.business_user_account_for(@public_repo_user)

        assert_equal :unlicensed, public_repo_user_bua.ghec_license_type
      end

      test "will remove license from users" do
        @business.customer.update!(metered_plan: true, billed_via_billing_platform: true)
        Billing::Platform::Api::Client.any_instance.stubs(:get_customer).with(
          equals({ customer_id: @business.customer.id })
        ).returns({ "customer": { "customerId": @business.customer.id.to_s } })
        update_user_account_attributes
        assert_equal :enterprise_license, @member_bua.ghec_license_type

        # Remove organization membership without removing from business
        Organization.any_instance.stubs(:remove_user_from_business).with(@member).returns(false)
        perform_enqueued_jobs(only: [RevokeOrgMembershipAbilitiesJob]) do
          @org.remove_member!(@member)
        end

        update_user_account_attributes
        assert_equal :unlicensed, @member_bua.ghec_license_type
      end

      test "does not update license on accounts if trial" do
        @business.customer.update!(metered_plan: true)
        @business.update_attribute(:trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now)
        update_user_account_attributes

        refute @member_bua.has_ghec_license?
      end

      test "updates metered accounts after trial conversion" do
        @business.customer.update!(metered_plan: true, billed_via_billing_platform: true, billing_type: "card")
        @business.update_attribute(:trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now)
        Billing::Platform::Api::Client.any_instance.stubs(:get_customer).with(
          equals({ customer_id: @business.customer.id })
        ).returns({ "customer": { "customerId": @business.customer.id.to_s } })
        update_user_account_attributes
        # Still on a trial
        refute @member_bua.has_ghec_license?

        @business.convert_trial
        BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @business.id)
        @member_bua.reload

        assert @member_bua.has_ghec_license?
        assert_equal :enterprise_license, @member_bua.ghec_license_type
      end

      test "stores license attributes on emu users" do
        emu_business = create(:business, :enterprise_managed)
        emu_business.customer.update!(metered_plan: true, billed_via_billing_platform: true)
        Billing::Platform::Api::Client.any_instance.stubs(:get_customer).with(
          equals({ customer_id: emu_business.customer.id })
        ).returns({ "customer": { "customerId": emu_business.customer.id.to_s } })
        emu_owner = emu_business.owners.first
        emu_org = create :enterprise_linked_organization, business: emu_business, admin: emu_owner

        emu_org_member = create(:emu, business: emu_business)
        perform_enqueued_jobs(only: [BusinessUserAccountCreateForOrganizationJob]) do
          emu_org.add_member(emu_org_member)
        end

        emu_unaffiliated = create(:emu, business: emu_business)
        emu_unaffiliated_guest_collaborator = create(:emu, :guest_collaborator, business: emu_business)

        emu_guest_collaborator = create(:emu, :guest_collaborator, business: emu_business)
        team = create :team, organization: emu_org
        team.add_member(emu_guest_collaborator)

        emu_billing_manager = create(:emu, business: emu_business)
        emu_business.billing.add_manager(emu_billing_manager, actor: emu_owner)

        emu_suspended = create(:emu, business: emu_business)
        emu_suspended.external_identities.first.disable

        attributes = BusinessUserAccount::UpdateAttributes.new(business: emu_business.reload)
        attributes.save!

        assert emu_business.business_user_account_for(emu_org_member).has_ghec_license?
        assert emu_business.business_user_account_for(emu_guest_collaborator).has_ghec_license?
        assert emu_business.business_user_account_for(emu_owner).has_ghec_license?

        refute emu_business.business_user_account_for(emu_billing_manager).has_ghec_license?
        refute emu_business.business_user_account_for(emu_unaffiliated).has_ghec_license?
        refute emu_business.business_user_account_for(emu_unaffiliated_guest_collaborator).has_ghec_license?
        refute emu_business.business_user_account_for(emu_suspended).has_ghec_license?
      end
    end

    context "license emissions" do
      test "emits license events for adding new users" do
        @business.customer.update metered_plan: true, billed_via_billing_platform: true
        # Sync job has not run, so user is unlicensed
        refute @member_bua.has_ghec_license?
        Billing::Platform::Api::Client.any_instance.stubs(:get_customer).with(
          equals({ customer_id: @business.customer.id })
        ).returns({ "customer": { "customerId": @business.customer.id.to_s } })

        BusinessUserAccount.any_instance.expects(:emit_added_license_billing_message).at_least_once.returns(true)
        update_user_account_attributes
        assert @member_bua.has_ghec_license?
      end

      test "does not emit license events when users already licensed" do
        @business.customer.update metered_plan: true, billed_via_billing_platform: true
        Billing::Platform::Api::Client.any_instance.stubs(:get_customer).with(
          equals({ customer_id: @business.customer.id })
        ).returns({ "customer": { "customerId": @business.customer.id.to_s } })
        # Run sync job to license users
        update_user_account_attributes
        assert_equal :enterprise_license, @member_bua.ghec_license_type

        # No new events should emit
        BusinessUserAccount.any_instance.expects(:emit_added_license_billing_message).never

        # Change user from enterprise to vss license
        create(:enterprise_agreement, :visual_studio_bundle, business: @business, seats: 1)
        create(:licensing_bundled_license_assignment, user: @member, business: @business)
        update_user_account_attributes
        assert_equal :vss_bundle_license, @member_bua.ghec_license_type
      end

      test "emits license for changing from unlicensed to licensed" do
        @business.customer.update metered_plan: true, billed_via_billing_platform: true
        Billing::Platform::Api::Client.any_instance.stubs(:get_customer).with(
          equals({ customer_id: @business.customer.id })
        ).returns({ "customer": { "customerId": @business.customer.id.to_s } })
        update_user_account_attributes
        public_bua = @business.business_user_account_for(@public_repo_user)
        assert_equal :unlicensed, public_bua.ghec_license_type

        BusinessUserAccount.any_instance.expects(:emit_added_license_billing_message).once

        # Outside collaborator now becoming an org member, and will be licensed
        @org.add_member(@public_repo_user)
        update_user_account_attributes
      end

      test "emits license for changing from licensed to unlicensed" do
        @business.customer.update metered_plan: true, billed_via_billing_platform: true
        Billing::Platform::Api::Client.any_instance.stubs(:get_customer).with(
          equals({ customer_id: @business.customer.id })
        ).returns({ "customer": { "customerId": @business.customer.id.to_s } })
        update_user_account_attributes
        private_bua = @business.business_user_account_for(@private_repo_user)
        assert_equal :enterprise_license, private_bua.ghec_license_type

        BusinessUserAccount.any_instance.expects(:emit_removed_license_billing_message).once

        # Private repository user is now contributing only to a public repository, and will be unlicensed
        @public_repo.add_member(@private_repo_user)
        @private_repo.remove_member(@private_repo_user)
        update_user_account_attributes
      end

      test "does not save license attribute if license was not emitted" do
        @business.customer.update metered_plan: true, billed_via_billing_platform: true
        # Sync job has not run, so user is unlicensed
        refute @member_bua.has_ghec_license?

        Billing::Platform::Api::Client.any_instance.stubs(:get_customer).with(
          equals({ customer_id: @business.customer.id })
        ).returns({ "customer": { "customerId": @business.customer.id.to_s } })

        # Something failed in the license emission process
        BusinessUserAccount.any_instance.stubs(:emit_added_license_billing_message).returns(false)

        update_user_account_attributes
        # Because something failed, the user is not considered licensed yet
        refute @member_bua.has_ghec_license?
      end

      test "emits license for metered emu users" do
        emu_business = create(:business, :enterprise_managed)
        emu_business.customer.update! metered_plan: true, billed_via_billing_platform: true
        emu_owner = emu_business.owners.first
        emu_user = create(:emu, business: emu_business)
        emu_org = create :enterprise_linked_organization, business: emu_business, admin: emu_owner

        perform_enqueued_jobs(only: [BusinessUserAccountCreateForOrganizationJob]) do
          emu_org.add_member(emu_user)
        end

        BusinessUserAccount.any_instance.expects(:emit_added_license_billing_message).once
        Billing::Platform::Api::Client.any_instance.stubs(:get_customer).with(
          equals({ customer_id: emu_business.customer.id })
        ).returns({ "customer": { "customerId": emu_business.customer.id.to_s } })

        attributes = BusinessUserAccount::UpdateAttributes.new(business: emu_business.reload)
        attributes.save!
      end

      test "does not emit license event for non-metered business" do
        refute_predicate @business, :metered_plan?
        update_user_account_attributes

        BusinessUserAccount.any_instance.expects(:emit_added_license_billing_message).never
        refute @member_bua.has_ghec_license?
      end

      test "does not emit license event for business when billing platform API client returns error" do
        @business.customer.update metered_plan: true
        Billing::Platform::Api::Client.any_instance.stubs(:get_customer).with(
          equals({ customer_id: @business.customer.id })
        ).returns(Billing::Platform::Api::Error.new("Test error"))
        update_user_account_attributes

        BusinessUserAccount.any_instance.expects(:emit_added_license_billing_message).never
        refute @member_bua.has_ghec_license?
      end

      test "does not emit license event for business not onboarded to billing vNext platform" do
        @business.customer.update metered_plan: true
        Billing::Platform::Api::Client.any_instance.stubs(:get_customer).with(
          equals({ customer_id: @business.customer.id })
        ).returns({ "customer": nil })
        update_user_account_attributes

        BusinessUserAccount.any_instance.expects(:emit_added_license_billing_message).never
        refute @member_bua.has_ghec_license?
      end

      test "includes cost center for emu users" do
        emu_business = create(:business, :enterprise_managed)
        emu_business.customer.update! metered_plan: true
        emu_owner = emu_business.owners.first
        emu_user = create(:emu, business: emu_business)
        emu_user2 = create(:emu, business: emu_business)
        emu_business.customer.create_billing_platform_enabled_product(copilot: true)

        first_cost_center = {
          costCenterKey: { customerId: emu_business.customer_id.to_s, targetType: :ZuoraSubscription, targetId: "", uuid: "fcb5aa21-778b-411f-90ec-2409e3713bc6" },
          name: "First Cost Center",
          resources: [
            { id: emu_owner.id.to_s, type: :User },
          ]
        }
        second_cost_center = {
          costCenterKey: { customerId: emu_business.customer_id.to_s, targetType: :ZuoraSubscription, targetId: "", uuid: "e78d46ca-2b4a-4c3f-b9e5-bc9c3db6d515" },
          name: "Second Cost Center",
          resources: [
            { id: emu_user.id.to_s, type: :User }
          ]
        }
        Billing::Platform::Api::Client.any_instance
          .stubs(:get_all_cost_centers)
          .with(customer_id: emu_business.customer_id.to_s)
          .returns({ costCenters: [
            first_cost_center,
            second_cost_center,
          ] })


        attributes = BusinessUserAccount::UpdateAttributes.new(business: emu_business.reload)
        attributes.save!
        emu_bua = emu_business.business_user_account_for(emu_user)
        assert_equal "e78d46ca-2b4a-4c3f-b9e5-bc9c3db6d515", emu_bua.cost_center
        emu_bua2 = emu_business.business_user_account_for(emu_user2)
        assert_nil emu_bua2.cost_center
        emu_owner_bua = emu_business.business_user_account_for(emu_owner)
        assert_equal "fcb5aa21-778b-411f-90ec-2409e3713bc6", emu_owner_bua.cost_center
      end

      test "removes cost center if it was unset" do
        emu_business = create(:business, :enterprise_managed)
        emu_business.customer.update! metered_plan: true
        emu_owner = emu_business.owners.first
        emu_user = create(:emu, business: emu_business)
        emu_business.customer.create_billing_platform_enabled_product(copilot: true)
        emu_business.business_user_account_for(emu_user).update(cost_center: "fcb5aa21-778b-411f-90ec-2409e3713bc6")

        first_cost_center = {
          costCenterKey: { customerId: emu_business.customer_id.to_s, targetType: :ZuoraSubscription, targetId: "", uuid: "fcb5aa21-778b-411f-90ec-2409e3713bc6" },
          name: "First Cost Center",
          resources: [
            { id: emu_owner.id.to_s, type: :User },
          ]
        }
        Billing::Platform::Api::Client.any_instance
          .stubs(:get_all_cost_centers)
          .with(customer_id: emu_business.customer_id.to_s)
          .returns({ costCenters: [
            first_cost_center,
          ] })


        attributes = BusinessUserAccount::UpdateAttributes.new(business: emu_business.reload)
        attributes.save!
        emu_bua = emu_business.business_user_account_for(emu_user)
        assert_nil emu_bua.cost_center
      end

      test "does not remove cost center if API call fails" do
        emu_business = create(:business, :enterprise_managed)
        emu_business.customer.update! metered_plan: true
        emu_owner = emu_business.owners.first
        emu_user = create(:emu, business: emu_business)
        emu_business.customer.create_billing_platform_enabled_product(copilot: true)
        emu_business.business_user_account_for(emu_user).update(cost_center: "fcb5aa21-778b-411f-90ec-2409e3713bc6")

        emu_business.expects(:cost_centers).returns(nil)
        attributes = BusinessUserAccount::UpdateAttributes.new(business: emu_business.reload)
        attributes.save!
        emu_bua = emu_business.business_user_account_for(emu_user)
        assert_equal "fcb5aa21-778b-411f-90ec-2409e3713bc6", emu_bua.cost_center
      end
    end
  end
end
