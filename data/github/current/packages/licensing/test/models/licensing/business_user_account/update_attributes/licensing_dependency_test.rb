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
      disable_feature_flag(:licensing_server_users_from_licensify, @business)
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
        mock_licensify_sdlc_licensee_ids(@business.customer.id, [@member.id])
        update_user_account_attributes
        assert @member_bua.has_ghec_license?
        assert_equal :enterprise_license, @member_bua.ghec_license_type
      end

      test "will change license for user" do
        @business.customer.update!(metered_plan: true, billed_via_billing_platform: true)
        Billing::Platform::Api::Client.any_instance.stubs(:get_customer).with(
          equals({ customer_id: @business.customer.id })
        ).returns({ "customer": { "customerId": @business.customer.id.to_s } })
        mock_licensify_sdlc_licensee_ids(@business.customer.id, [@member.id])
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
        mock_licensify_sdlc_licensee_ids(@business.customer.id, [])
        update_user_account_attributes

        assert_equal :unlicensed, @member_bua.ghec_license_type
      end

      test "will remove license from users" do
        @business.customer.update!(metered_plan: true, billed_via_billing_platform: true)
        Billing::Platform::Api::Client.any_instance.stubs(:get_customer).with(
          equals({ customer_id: @business.customer.id })
        ).returns({ "customer": { "customerId": @business.customer.id.to_s } })
        mock_licensify_sdlc_licensee_ids(@business.customer.id, [@member.id])
        update_user_account_attributes
        assert_equal :enterprise_license, @member_bua.ghec_license_type

        mock_licensify_sdlc_licensee_ids(@business.customer.id, [])
        update_user_account_attributes
        assert_equal :unlicensed, @member_bua.ghec_license_type
      end

      test "does not update license on accounts if trial" do
        @business.customer.update!(metered_plan: true)
        @business.update_attribute(:trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now)
        mock_licensify_sdlc_licensee_ids(@business.customer.id, [@member.id])
        update_user_account_attributes

        refute @member_bua.has_ghec_license?
      end

      test "updates metered accounts after trial conversion" do
        @business.customer.update!(metered_plan: true, billed_via_billing_platform: true, billing_type: "card")
        @business.update_attribute(:trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now)
        Billing::Platform::Api::Client.any_instance.stubs(:get_customer).with(
          equals({ customer_id: @business.customer.id })
        ).returns({ "customer": { "customerId": @business.customer.id.to_s } })
        mock_licensify_sdlc_licensee_ids(@business.customer.id, [@member.id])
        update_user_account_attributes
        # Still on a trial
        refute @member_bua.has_ghec_license?

        @business.convert_trial
        BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @business.id)
        @member_bua.reload

        assert @member_bua.has_ghec_license?
        assert_equal :enterprise_license, @member_bua.ghec_license_type
      end
    end
  end
end
