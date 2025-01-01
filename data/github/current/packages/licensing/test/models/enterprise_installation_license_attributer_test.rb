# typed: true
# frozen_string_literal: true

require "test_helper"

class EnterpriseInstallationLicenseAttributerTest < GitHub::TestCase
  setup do
    @business = create(:business)

    @enterprise_installation1 = create(:enterprise_installation, owner: @business)
    @enterprise_installation2 = create(:enterprise_installation, owner: @business)

    @user = create(:user)
    @business_user_account = create(:business_user_account, business: @business, user: @user)
    _user_based_enterprise_installation_user_account_installation1 = create(
      :enterprise_installation_user_account,
      enterprise_installation: @enterprise_installation1,
      business_user_account: @business_user_account,
    )
    _user_based_enterprise_installation_user_account_installation2 = create(
      :enterprise_installation_user_account,
      enterprise_installation: @enterprise_installation2,
      business_user_account: @business_user_account,
    )

    @email1 = "email-verified-on-random-user@example.com"
    _random_user = create(:user, :verified, email: @email1)
    @email_based_enterprise_installation_user_account1 = create(
      :enterprise_installation_user_account,
      enterprise_installation: @enterprise_installation1,
      business_user_account: create(:business_user_account, business: @business, user: nil),
    )
    create(
      :enterprise_installation_user_account_email,
      enterprise_installation_user_account: @email_based_enterprise_installation_user_account1,
      email: @email1,
      primary: true,
    )
    create(
      :enterprise_installation_user_account_email,
      enterprise_installation_user_account: @email_based_enterprise_installation_user_account1,
      email: "zzz_another_primary_lol@example.com",
      primary: true,
    )

    @email2 = "random@example.com"
    @email_based_enterprise_installation_user_account2 = create(
      :enterprise_installation_user_account,
      enterprise_installation: @enterprise_installation2,
      business_user_account: create(:business_user_account, business: @business, user: nil),
    )
    create(
      :enterprise_installation_user_account_email,
      enterprise_installation_user_account: @email_based_enterprise_installation_user_account2,
      email: @email2,
      primary: true,
    )
    create(
      :enterprise_installation_user_account_email,
      enterprise_installation_user_account: @email_based_enterprise_installation_user_account2,
      email: "secondary1@example.com",
      primary: false,
    )

    @email_based_enterprise_installation_user_account3 = create(
      :enterprise_installation_user_account,
      enterprise_installation: @enterprise_installation2,
      business_user_account: create(:business_user_account, business: @business, user: nil),
    )
    create(
      :enterprise_installation_user_account_email,
      enterprise_installation_user_account: @email_based_enterprise_installation_user_account3,
      email: @email1.capitalize,
      primary: true,
    )
    create(
      :enterprise_installation_user_account_email,
      enterprise_installation_user_account: @email_based_enterprise_installation_user_account3,
      email: "secondary1@example.com",
      primary: false,
    )

    @enterprise_installation_user_account_with_no_user_or_email = create(
      :enterprise_installation_user_account,
      enterprise_installation: @enterprise_installation2,
      business_user_account: create(:business_user_account, business: @business, user: nil),
    )
    @enterprise_installation_user_account_with_secondary_email = create(
      :enterprise_installation_user_account,
      enterprise_installation: @enterprise_installation2,
      business_user_account: create(:business_user_account, business: @business, user: nil),
    )
    create(
      :enterprise_installation_user_account_email,
      enterprise_installation_user_account: @email_based_enterprise_installation_user_account2,
      email: "secondary2@example.com",
      primary: false,
    )

  end

  test "attributes licenses from one or more enterprise installations" do
    attributer = EnterpriseInstallationLicenseAttributer.new(@business.reload.enterprise_installation_ids)

    assert_same_elements [@user.id], attributer.user_ids
    assert_same_elements [@email1, @email2], attributer.emails
    assert_same_elements(
      [
        @enterprise_installation_user_account_with_no_user_or_email.business_user_account_id,
        @enterprise_installation_user_account_with_secondary_email.business_user_account_id
      ],
      attributer.unidentified_business_user_account_ids
    )
    assert_equal 5, attributer.unique_count
  end
end
