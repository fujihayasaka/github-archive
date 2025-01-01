# typed: true
# frozen_string_literal: true

require "test_helper"

# We're now thoroughly testing the data generation in test/models/business/license_attributer_test.rb, so this test is
# just to confirm we're turning that data into a suitable CSV format.

class BusinessLicenseCsvGeneratorTest < GitHub::TestCase
  fixtures do
    @profile = create(:profile, name: "Johnny Test")
    @profile2 = create(:profile, name: "First Last")
    @user = @profile.user
    @user2 = @profile2.user
    @organization = create(:organization, admin: @user)
    @email = "test@invite.com"
    @organization.invite(email: @email, inviter: @user)
    @organization.invite(@user2, inviter: @user)
    @business = create(:business, organizations: [@organization])
    enterprise_installation = create(:enterprise_installation, owner: @business)
    @eiua = create(:enterprise_installation_user_account, enterprise_installation: enterprise_installation)
    @bua = create(:business_user_account, business: @business, user: nil, enterprise_installation_user_accounts: [@eiua], roles: [:server_member])
    @eiua2 = create(:enterprise_installation_user_account, enterprise_installation: enterprise_installation)
    @server_email = "server@example.com"
    create(:enterprise_installation_user_account_email, enterprise_installation_user_account: @eiua2, email: @server_email, primary: true)
    create(:enterprise_installation_user_account_email, enterprise_installation_user_account: @eiua2, email: "zzz-another-primary-lol@example.com", primary: true)
    @bua2 = create(:business_user_account, business: @business, user: nil, enterprise_installation_user_accounts: [@eiua2], roles: [:server_member])
  end

  context "#csv_rows" do
    test "returns csv structure of Business::LicenseAttributer#license_usage_hash" do
      rows = Business::LicenseCsvGenerator.new(@business).csv_rows

      title_row = rows.shift
      assert_equal %w[
        github_com_login
        github_com_name
        enterprise_server_user_ids

        github_com_user
        enterprise_server_user
        visual_studio_subscription_user

        license_type

        github_com_profile
        github_com_member_roles
        github_com_enterprise_roles
        github_com_verified_domain_emails
        github_com_saml_name_id
        github_com_orgs_with_pending_invites
        github_com_two_factor_auth
        github_com_two_factor_auth_required_by_date

        enterprise_server_primary_emails

        visual_studio_license_status
        visual_studio_subscription_email

        total_user_accounts
      ], title_row
      assert_equal 5, rows.length
    end

    test "returns csv structure of Business::LicenseAttributer#license_usage_hash when GHAS Connect data is available" do
      @eiua.update_attribute(:using_advanced_security, true)

      rows = Business::LicenseCsvGenerator.new(@business).csv_rows

      title_row = rows.shift
      assert_equal %w[
        github_com_login
        github_com_name
        enterprise_server_user_ids

        github_com_user
        enterprise_server_user
        visual_studio_subscription_user

        license_type

        github_com_profile
        github_com_member_roles
        github_com_enterprise_roles
        github_com_verified_domain_emails
        github_com_saml_name_id
        github_com_orgs_with_pending_invites
        github_com_two_factor_auth
        github_com_two_factor_auth_required_by_date

        enterprise_server_primary_emails
        enterprise_server_advanced_security_user_ids

        visual_studio_license_status
        visual_studio_subscription_email

        total_user_accounts
      ], title_row
      assert_equal 5, rows.length
    end
  end if GitHub.billing_enabled?
end
