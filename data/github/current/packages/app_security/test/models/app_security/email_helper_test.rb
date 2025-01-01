# typed: true
# frozen_string_literal: true

require "test_helper"

class AppSecurityEmailHelperTest < GitHub::TestCase
  setup do
    @helper = FakeHelper.new
    @helper.extend AppSecurity::EmailHelper

    @user = create(:user)
    @email = @user.primary_user_email
  end

  context "#unlink_from_account" do
    test "Errors if email is nil" do

      assert_equal "Email is not associated with this account", @helper.unlink_from_account(@user, nil)
    end

    test "Errors if email is not associated with user" do
      email = create(:user_email, user: create(:user))

      assert_equal "Email is not associated with this account", @helper.unlink_from_account(@user, email)
    end

    test "Errors if email is associated with a Sponsors account" do
      @email.verify!
      create(:sponsors_listing, :approved, sponsorable: @user, contact_email_id: @email.id)

      expected_err = "This email is being used as your contact email for GitHub Sponsors and cannot be unlinked. Please change the email in your GitHub Sponsors settings or application and try again."
      assert_equal expected_err, @helper.unlink_from_account(@user, @email)
    end

    context "Successes" do
      test "Removing primary email, replaces with backup" do
        backup_email = @user.add_email("#{SecureRandom.hex}@gmail.com")
        backup_email.verify!
        @user.set_backup_email(backup_email)

        assert_nil @helper.unlink_from_account(@user, @user.primary_user_email)
        assert_equal backup_email.id, @user.reload.primary_user_email.id
      end

      unless GitHub.enterprise?
        test "Removing primary email, replaces with .unlinked and disables notifications" do
          email = @user.primary_user_email.email

          @user.expects(:disable_all_notifications).once

          Timecop.freeze(Time.now.utc) do
            assert_nil @helper.unlink_from_account(@user, @user.primary_user_email)
            assert_equal "#{email}.unlinked#{Time.now.utc.strftime("%Y%m%d%H%M")}", @user.reload.primary_user_email.email
          end
        end

        test "Notifications may not be disabled if error" do
          @user.expects(:add_email).returns("Problem")
          @user.expects(:disable_all_notifications).never

          refute_nil @helper.unlink_from_account(@user, @user.primary_user_email)
        end
      end

      test "Removing non-primary email" do
        email_address = "#{SecureRandom.hex}@gmail.com"
        backup_email = @user.add_email(email_address)

        assert_nil @helper.unlink_from_account(@user, backup_email)
        assert_equal 1, @user.reload.emails.count
      end

      test "Audit log event" do
        backup_email1 = @user.add_email("#{SecureRandom.hex}@gmail.com")
        backup_email2 = @user.add_email("#{SecureRandom.hex}@gmail.com")
        staff = create(:user)

        GlobalInstrumenter.expects(:instrument).with("user.remove_email", {
          user: @user,
          actor: @user,
          primary_email: @user.primary_user_email,
          removed_email: backup_email1,
        })
        GlobalInstrumenter.expects(:instrument).with("user.remove_email", {
          user: @user,
          actor: staff,
          primary_email: @user.primary_user_email,
          removed_email: backup_email2,
        })

        reset_job_hash_locks # avoid jobs.lock-not-acquired errors for downstream jobs, not what test is about
        @helper.unlink_from_account(@user, backup_email1)
        reset_job_hash_locks # avoid jobs.lock-not-acquired errors for downstream jobs, not what test is about
        @helper.unlink_from_account(@user, backup_email2, actor: staff)
      end
    end

    context "Failures" do
      if GitHub.enterprise?
        test "Removing primary email, cannot remove final email from Enterprise account" do
          email = @user.primary_user_email

          assert_equal "Cannot remove this email from this account, please add another before deleting '#{email.email}'", @helper.unlink_from_account(@user, email)
        end
      end

      test "User.set_primary_email failure gives specific error", skip_enterprise: true do
        primary_email = @user.primary_user_email
        invalid_replacement_email = UserEmail.new(user: @user, email: "#{primary_email}.unlinked")
        error_msg = "Cannot set primary email"
        invalid_replacement_email.errors.add(:base, error_msg)
        @user.expects(:set_primary_email).returns(User::SetPrimaryEmailStatus.new(invalid_model: invalid_replacement_email))

        assert_equal error_msg, @helper.unlink_from_account(@user, @user.primary_user_email)
        assert_equal @user.reload.primary_user_email.email, primary_email.email
        assert_equal 1, @user.reload.emails.count # rolls back the addition of .unlinked email to account
      end

      # need to skip enterprise because the last remaining email cannot be unlinked
      test "Unexpected ActiveRecord error gives generic error", skip_enterprise: true do
        error = ActiveRecord::ActiveRecordError.new("This had a problem")
        @user.expects(:add_email).raises(error)
        Failbot.expects(:report).with(error).once

        assert_equal "Something went wrong while unlinking the email from the account", @helper.unlink_from_account(@user, @user.primary_user_email)
      end

      test "Unlinking an email multiple times is ok", skip_enterprise: true do
        create(:user_email, user: create(:user), email: "email@test.com.unlinked")
        create(:user_email, user: create(:user), email: "email@test.com.unlinked1")
        reusing_user = create(:user)
        primary_email = reusing_user.emails.primary.first
        primary_email.email = "email@test.com"
        primary_email.save

        Timecop.freeze(Time.now.utc) do
          assert_nil @helper.unlink_from_account(reusing_user, primary_email)
          assert_equal reusing_user.reload.emails.primary.first.email, "email@test.com.unlinked#{Time.now.utc.strftime("%Y%m%d%H%M")}"
        end
      end
    end
  end

  context "#prevent_email_unlink_message" do
    test "returns nil if no blockers" do
      assert_nil @helper.prevent_email_unlink_message(@email.email)
    end

    test "returns error string if email is used as contact email for GitHub Sponsors" do
      @email.verify!
      create(:sponsors_listing, :approved, sponsorable: @user, contact_email_id: @email.id)

      expected_err = "This email is being used as your contact email for GitHub Sponsors and cannot be unlinked. Please change the email in your GitHub Sponsors settings or application and try again."
      assert_equal expected_err, @helper.prevent_email_unlink_message(@email.email)
    end
  end
end
