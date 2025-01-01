# typed: true
# frozen_string_literal: true

require "test_helper"

unless GitHub.single_business_environment?
  class BusinessUserAccountGhecLicensesTest < GitHub::TestCase
    fixtures do
      @admin = create :user, login: "business-admin"
      @org1 = create :organization, admin: @admin
      @org2 = create :organization, admin: @admin
      @business = create :business, owners: [@admin], organizations: [@org1, @org2]
      @member = create :user
    end

    setup do
      perform_enqueued_jobs(only: [BusinessUserAccountCreateForOrganizationJob]) do
        @org1.add_member @member
      end
      @business_user_account = @business.business_user_account_for(@member)
    end

    context "ghec_license_type" do
      test "returns nil when license have not been defined yet" do
        assert_nil @business_user_account.ghec_license_type
      end

      test "returns unlicensed when a user has no license" do
        @business_user_account.ghec_license = :unlicensed

        assert_equal :unlicensed, @business_user_account.ghec_license_type
      end

      test "returns a license type for licensed users" do
        @business_user_account.ghec_license = :enterprise_license

        assert_equal :enterprise_license, @business_user_account.ghec_license_type
      end
    end

    context "has_ghec_license?" do
      test "returns false if license is not yet defined" do
        refute @business_user_account.has_ghec_license?
      end

      test "returns false if user is unlicensed" do
        @business_user_account.ghec_license = :unlicensed
        assert_equal :unlicensed, @business_user_account.ghec_license_type

        refute @business_user_account.has_ghec_license?
      end

      test "returns true if user is licensed" do
        @business_user_account.ghec_license = :enterprise_license
        assert_equal :enterprise_license, @business_user_account.ghec_license_type

        assert @business_user_account.has_ghec_license?
      end
    end

    context "changing_licensed_status?" do
      test "returns false if setting unlicensed from undefined state" do
        refute @business_user_account.changing_licensed_status?(:unlicensed)
      end

      test "returns true if setting a licensed status from undefined state" do
        assert @business_user_account.changing_licensed_status?(:enterprise_license)
      end

      test "returns false if going from unlicensed to unlicensed" do
        @business_user_account.ghec_license = :unlicensed
        refute @business_user_account.changing_licensed_status?(:unlicensed)
      end

      test "returns true if going from unlicensed to licensed" do
        @business_user_account.ghec_license = :unlicensed
        assert @business_user_account.changing_licensed_status?(:enterprise_license)
      end

      test "returns true if going from licensed to unlicensed" do
        @business_user_account.ghec_license = :vss_bundle_license
        assert @business_user_account.changing_licensed_status?(:unlicensed)
      end

      test "returns false if going from licensed to licensed" do
        @business_user_account.ghec_license = :vss_bundle_license
        refute @business_user_account.changing_licensed_status?(:enterprise_license)
      end
    end
  end
end
