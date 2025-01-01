# typed: true
# frozen_string_literal: true

require "test_helper"

class StealthEmailTest < GitHub::TestCase
  fixtures do
    @user = create(:user, login: "rsanheim", email: "rsanheim@example.com")
  end

  test "has the stealth email" do
    stealth = StealthEmail.new(@user)
    assert_equal "#{@user.id}+rsanheim@#{GitHub.stealth_email_host_name}", stealth.email
  end

  test "uses GitHub config value for the domain" do
    original_stealth_email_host_name = GitHub.stealth_email_host_name
    stealth = StealthEmail.new(@user)
    begin
      GitHub.stealth_email_host_name = "users.enterprise.com"
      assert_equal "#{@user.id}+rsanheim@users.enterprise.com", stealth.email
    ensure
      GitHub.stealth_email_host_name = original_stealth_email_host_name
    end
  end

  test "github stealth emails? matcher works" do
    ["jdoe@users.noreply.#{GitHub.host_name}", "frank@USERS.noreply.#{GitHub.host_name}"].each do |e|
      assert StealthEmail.stealthy_email?(e), "returned false for #{e}"
    end
    assert !StealthEmail.stealthy_email?("jdoe@github.com")
    assert !StealthEmail.stealthy_email?("jdoe@yahoo.com")
  end

  if GitHub.stealth_email_enabled?
    test "cannot use stealth email when user has no verified emails" do
      refute @user.emails.first.verified?
      refute StealthEmail.new(@user).valid?
    end

    test "cannot use stealth email when user has verified emails but no primary email" do
      # This case only happens when we get data problems with emails/email_roles,
      # but good to test for it
      @user.emails.first.verify!
      assert @user.emails.first.verified?
      primary_role = @user.primary_user_email.primary_role
      primary_role.delete
      assert_nil @user.reload_primary_user_email
      refute StealthEmail.new(@user).valid?
    end

    test "can use stealth email when user has verified emails and a primary email" do
      @user.emails.first.verify!
      assert @user.emails.first.verified?
      assert @user.primary_user_email
      assert StealthEmail.new(@user).valid?
    end

    test "creates the stealth email as verified" do
      @user.emails.first.verify!

      stealth_email = StealthEmail.new(@user)
      assert stealth_email.save!
      user_email = @user.emails.find_by_email(stealth_email.email)

      assert_equal "verified", user_email.state
      refute_nil user_email.verified_at
    end

    test "newly created stealth emails are valid" do
      @user.emails.first.verify!

      stealth_email = StealthEmail.new(@user)
      assert stealth_email.save!
      user_email = @user.emails.find_by_email(stealth_email.email)
      assert_valid user_email
    end
  else
    test "stealth emails are never valid" do
      refute StealthEmail.new(@user).valid?
    end
  end

end

class EMUStealthEmailTest < GitHub::TestCase
  fixtures do
    @managed_user = create(:emu)
  end

  test "renders profile email" do
    profile = @managed_user.create_profile
    profile.email = "profile.email@github.com"
    profile.save!
    refute_nil @managed_user.profile_email

    assert_equal @managed_user.profile_email, StealthEmail.new(@managed_user).email
  end
end unless GitHub.single_business_environment?
