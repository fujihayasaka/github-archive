# typed: true
# frozen_string_literal: true

require "test_helper"

class EnterpriseInstallationUserAccountEmailTest < GitHub::TestCase
  context "validations" do
    test "require that enterprise installation user account is present" do
      email = build :enterprise_installation_user_account_email, enterprise_installation_user_account: nil
      refute_predicate email, :valid?
      assert_includes email.errors[:enterprise_installation_user_account], "can't be blank"
    end

    test "require that email is present" do
      email = build :enterprise_installation_user_account_email, email: nil
      refute_predicate email, :valid?
      assert_includes email.errors[:email], "can't be blank"
    end

    test "require that email is unique for user account" do
      user_account = create :enterprise_installation_user_account
      email = create :enterprise_installation_user_account_email,
        enterprise_installation_user_account: user_account,
        email: "first@eeeeee.ee"
      assert_predicate email, :valid?
      second_email = build :enterprise_installation_user_account_email,
        enterprise_installation_user_account: user_account,
        email: "first@eeeeee.ee"
      refute_predicate second_email, :valid?
      assert_includes second_email.errors[:email], "already exists on this account"
    end

    test "require that email is case insensitively unique for user account" do
      user_account = create :enterprise_installation_user_account
      email = create :enterprise_installation_user_account_email,
        enterprise_installation_user_account: user_account,
        email: "first@eeeeee.ee"
      assert_predicate email, :valid?
      second_email = build :enterprise_installation_user_account_email,
        enterprise_installation_user_account: user_account,
        email: "FIRST@EEEEEE.EE"
      refute_predicate second_email, :valid?
      assert_includes second_email.errors[:email], "already exists on this account"
    end

    test "require that email is correct length" do
      long_email = "hello@#{"e" * 200}.ee"
      email = build :enterprise_installation_user_account_email, email: long_email
      refute_predicate email, :valid?
      assert_includes email.errors[:email], "is too long (maximum is 100 characters)"
    end

    test "require that email is correct format" do
      email = build :enterprise_installation_user_account_email, email: "octocatatgithubdotcom"
      refute_predicate email, :valid?
      assert_includes email.errors[:email], "does not look like an email address"
    end
  end

  context ".primary" do
    test "returns all primary emails" do
      primary1 = create :enterprise_installation_user_account_email, primary: true
      _non_primary = create :enterprise_installation_user_account_email, primary: false
      primary2 = create :enterprise_installation_user_account_email, primary: true

      assert_same_elements [primary1, primary2], EnterpriseInstallationUserAccountEmail.primary
    end
  end

  context "#primary?" do
    test "true when email is primary" do
      email = create :enterprise_installation_user_account_email, primary: true
      assert_predicate email, :primary?
    end

    test "false when email is not primary" do
      email = create :enterprise_installation_user_account_email, primary: false
      refute_predicate email, :primary?
    end
  end
end
