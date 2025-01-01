# typed: true
# frozen_string_literal: true

require "test_helper"

class EnterpriseInstallationUserAccountTest < GitHub::TestCase
  fixtures do
    @enterprise_installation = create :enterprise_installation
    @enterprise_installation_user_account = create :enterprise_installation_user_account,
      login: "eeeeeeeeeeeee",
      enterprise_installation: @enterprise_installation
    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: @enterprise_installation_user_account,
      email: "octocat@github.com", primary: true
    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: @enterprise_installation_user_account,
      email: "another@example.com", primary: false
  end

  context "validations" do
    test "require that enterprise installation is present" do
      user_account = build :enterprise_installation_user_account, enterprise_installation: nil
      refute_predicate user_account, :valid?
      assert_includes user_account.errors[:enterprise_installation], "can't be blank"
    end

    test "require that remote_user_id is present" do
      user_account = build :enterprise_installation_user_account, remote_user_id: nil
      refute_predicate user_account, :valid?
      assert_includes user_account.errors[:remote_user_id], "can't be blank"
    end

    test "require that remote_user_id is unique for installation" do
      installation = create :enterprise_installation
      first_account = create :enterprise_installation_user_account,
        enterprise_installation: installation,
        remote_user_id: 12345
      assert_predicate first_account, :valid?
      second_account = build :enterprise_installation_user_account,
        enterprise_installation: installation,
        remote_user_id: 12345
      refute_predicate second_account, :valid?
      assert_includes second_account.errors[:remote_user_id], "already exists on this installation"
    end

    test "require that remote_created_at is present" do
      user_account = build :enterprise_installation_user_account, remote_created_at: nil
      refute_predicate user_account, :valid?
      assert_includes user_account.errors[:remote_created_at], "can't be blank"
    end

    test "require that login is present" do
      user_account = build :enterprise_installation_user_account, login: ""
      refute_predicate user_account, :valid?
      assert_includes user_account.errors[:login], "can't be blank"
    end

    test "require that login is less than 255 characters" do
      long_login = "e" * 256
      user_account = build :enterprise_installation_user_account, login: long_login
      refute_predicate user_account, :valid?
      assert_includes user_account.errors[:login], "is too long (maximum is 255 characters)"
    end

    test "require that profile name be no longer than 255 characters" do
      long_name = "e" * 260
      user_account = build :enterprise_installation_user_account, profile_name: long_name
      refute_predicate user_account, :valid?
      assert_includes user_account.errors[:profile_name], "is too long (maximum is 255 characters)"
    end
  end

  context "#emails" do
    test "can be provided when creating an EnterpriseInstallationUserAccount" do
      email = create :enterprise_installation_user_account_email, email: "e@e.ee"
      user_account = create :enterprise_installation_user_account, emails: [email]
      assert_equal %w(e@e.ee), user_account.emails.map(&:email)
    end
  end

  context "#cleanup_business_user_account" do
    test "destroys business user account when it has no other associations" do
      business_user_account = create :business_user_account, user: nil
      @enterprise_installation_user_account.update!(business_user_account: business_user_account)
      @enterprise_installation_user_account.destroy

      refute BusinessUserAccount.where(id: business_user_account.id).exists?
    end

    test "does not destroy business user account when it has other enterprise associations" do
      business_user_account = create :business_user_account, user: nil
      create :enterprise_installation_user_account,
        enterprise_installation: @enterprise_installation,
        business_user_account: business_user_account
      @enterprise_installation_user_account.update!(business_user_account: business_user_account)
      @enterprise_installation_user_account.destroy

      assert BusinessUserAccount.where(id: business_user_account.id).exists?
    end

    test "does not destroy business user account when it has user association" do
      business_user_account = create :business_user_account
      @enterprise_installation_user_account.update!(business_user_account: business_user_account)
      @enterprise_installation_user_account.destroy

      assert BusinessUserAccount.where(id: business_user_account.id).exists?
    end
  end
end
