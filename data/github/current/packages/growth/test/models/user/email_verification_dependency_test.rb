# typed: true
# frozen_string_literal: true

require "test_helper"

class EmailVerificationTest < GitHub::TestCase
  fixtures do
    @user        = create(:user)
    @verified    = create :verified_user
    @supportocat = create :staff_admin_user
    @old_timer   = create :user, created_at: 1.day.ago

    unless GitHub.enterprise?
      enterprise = create(:business, :enterprise_managed)
      create(:business_saml_provider, business: enterprise)
      @managed_user = User.create_with_random_password("monalisa", false,
        { "email" => "monalisa@github.com", "force_enterprise_managed" => true, "login_suffix" => "mona" })
      enterprise.add_user_accounts([@managed_user.id])
    end
  end

  if GitHub.email_verification_enabled?
    context "#should_verify_email?" do
      context "when user has no verified emails" do
        test "returns true" do
          assert @user.should_verify_email?
        end
      end

      context "when user has at least one verified email" do
        test "returns true" do
          refute @verified.should_verify_email?
        end
      end
    end

    context "#must_verify_email?" do
      context "when user has no verified emails" do
        test "returns true if mandatory email verification is enabled" do
          GitHub.stubs(:mandatory_email_verification_enabled?).returns(true)
          @user.require_email_verification!
          assert @user.must_verify_email?
        end

        test "returns true if user's visit is from a Tor node" do
          GitHub.stubs(:mandatory_email_verification_enabled?).returns(true)
          @user.has_used_anonymizing_proxy = true
          assert @user.must_verify_email?,
            "Tor user with no verified emails should be forced to verify."
        end

        test "exempt users are not required to verify" do
          GitHub.stubs(:mandatory_email_verification_enabled?).returns(true)
          @user.disable_mandatory_email_verification(actor: @supportocat)
          refute @user.must_verify_email?
        end

        test "Tor users cannot be exempt" do
          GitHub.stubs(:mandatory_email_verification_enabled?).returns(true)
          @user.has_used_anonymizing_proxy = true
          @user.disable_mandatory_email_verification(actor: @supportocat)
          assert @user.must_verify_email?
        end
      end

      context "when user has at least one verified email" do
        test "returns false" do
          @user.stubs(:content_creation_requires_email_verification?).returns(true)
          refute @verified.must_verify_email?,
            "User has a verified email address, so has met the email verification requirement."
        end

        test "returns true if user has an unverified email with +forceverify@github.com in the address" do
          email = create(:user_email, email: "jgkite+forceverify@github.com", user: @user)
          assert @user.must_verify_email?,
            "Staff override with #{email.email} didn't work."
        end

        test "returns false if user has a verified email with +forceverify@github.com in the address" do
          create(:user_email, :verified, email: "jgkite+forceverify@github.com", user: @user)
          refute @user.must_verify_email?
        end

        test "returns false if verified user has used an anonymizing proxy" do
          @verified.has_used_anonymizing_proxy = true
          refute @verified.must_verify_email?
        end
      end

      context "enterprise managed user", skip_enterprise: true do
        test "emu user does not need to verify email" do
          refute_predicate @managed_user, :must_verify_email?
        end
      end
    end

    context "#no_verified_emails?" do
      test "returns true when user has no verified emails" do
        assert @user.no_verified_emails?
      end

      test "returns false when user has at least one verified email" do
        refute @verified.no_verified_emails?
      end
    end

    context "#verified_emails?" do
      test "returns true when user has at least one verified email" do
        assert @verified.verified_emails?
      end

      test "returns false when user has no verified emails" do
        refute @user.verified_emails?
      end
    end

    context "#show_verification_reminder?" do
      test "pretends your emails are verified if it's your first day on GitHub" do
        refute @user.show_verification_reminder?
      end

      test "should show verification reminder for users who have been members more than a day" do
        assert @old_timer.show_verification_reminder?
      end
    end
  else # email verification is disabled
    context "#should_verify_email?" do
      test "returns false even if user has no verified emails" do
        refute @user.should_verify_email?
      end
    end

    context "#send_email_verification_reminder" do
      test "return true if unverified user visits site and is more than an hour old" do
        if GitHub.enterprise?
          assert_nil @old_timer.send_email_verification_reminder
        else
          assert @old_timer.send_email_verification_reminder
        end
      end
    end

    context "#send_email_verification" do
      if GitHub.enterprise?
        test "returns false if email verifciation is not enabled" do
          refute @user.send_email_verification
        end
      else
        test "sends a verification email with launch code" do
          primary_email = @user.primary_user_email
          SignupsReminderMailer.expects(:email_verification).with(primary_email).returns(stub(deliver_later: nil))

          assert @user.send_email_verification
          assert_equal UserEmail::LAUNCH_CODE_LENGTH, primary_email.reload.verification_token.length
        end

        test "returns false if user does not have primary email" do
          @user.primary_user_email.destroy!
          refute @user.send_email_verification
        end
      end
    end

    context "#must_verify_email?" do
      test "returns false even if user has no verified emails" do
        refute @user.must_verify_email?
      end
    end

    context "#no_verified_emails?" do
      test "returns true when user has no verified emails" do
        assert @user.no_verified_emails?
      end

      test "returns false when user has at least one verified email" do
        refute @verified.no_verified_emails?
      end
    end

    context "#show_verification_reminder?" do
      test "is always false" do
        refute @user.show_verification_reminder?
        refute @old_timer.show_verification_reminder?
      end
    end
  end

  context "Mandatory email verification is enabled" do
    test "new users have mandatory email verification enabled" do
      GitHub.stubs(:mandatory_email_verification_enabled?).returns(true)
      user = create(:user, require_email_verification: true)
      assert user.require_email_verification?, "email verification is not required, but should be"
    end

    test "new organizations do not have mandatory email verification enabled" do
      GitHub.stubs(:mandatory_email_verification_enabled?).returns(true)
      org = create(:organization)
      refute org.require_email_verification?, "email verification is required, but shouldn't be"
    end
  end

  context "Mandatory email verification is disabled" do
    test "new users do not have mandatory email verification enabled" do
      GitHub.stubs(:mandatory_email_verification_enabled?).returns(false)
      user = create(:user)
      refute user.require_email_verification?, "email verification is required, but shouldn't be"
    end
  end
end
