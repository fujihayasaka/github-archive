# typed: true
# frozen_string_literal: true

require "test_helper"

class UserEmailsTest < GitHub::TestCase
  fixtures do
    @staffer = create(:staff_admin_user, login: "staffer", plan: "medium", email: "staffer@example.com")
    @janedoe = create(:user, login: "janedoe", email: "janedoe@example.com")
    @johndoe = create(:user, login: "johndoe")
    @spammer = create(:user, login: "dr-evil", spammy: true)
    @user = create(:user)
  end

  test "creates user with primary email" do
    user = build(:user, email: nil)
    user.email = new_email = Sham.email
    user.save!
    user.reload
    assert_equal 1, user.emails.size
    assert_equal new_email, user.primary_user_email.to_s
    assert_equal new_email, user.email
    assert_equal new_email, user.gravatar_email
    assert_equal GitHub.generate_gravatar_id(new_email), user.gravatar_id
  end

  test "can have more than one email" do
    assert_difference "@staffer.emails.size" do
      @staffer.add_email "staffer-new@example.com"
    end
  end

  test "email_info" do
    @staffer.profile_name = "Chris Wanswardth"
    assert_equal({ "address" => "staffer@example.com", "name" => "Chris Wanswardth" },
                 @staffer.email_info)
  end

  test "email_info uses stealth email if provided" do
    user = early_access_user
    user.primary_user_email.toggle_visibility
    assert_equal "#{user.id}+#{user.login}@users.noreply.#{GitHub.host_name}", user.email_info["address"]
  end

  test "can list emails with the primary first" do
    @staffer.add_email "other-email@example.com"
    assert_equal %w( staffer@example.com other-email@example.com ), @staffer.emails.primary_first.map(&:to_s)
  end

  test "must have at least one email" do
    email1 = @staffer.primary_user_email
    email1.verify!

    @staffer.add_email "staffer-2@example.com"

    email3 = @staffer.add_email "staffer-3@example.com"
    email3.verify!

    # Cast this to an array, as we end up mutating the @staffer.emails when we
    # remove an email. As a result, iteration gets confused and ends up
    # skipping over some emails if we iterate over the emails relation
    # directly.
    @staffer.emails.to_a.each do |email|
      @staffer.remove_email email
    end

    assert_equal 1, @staffer.emails.size
  end

  test "sets an email with =" do
    assert_difference "@staffer.emails.size" do
      @staffer.update!(email: "new-email@example.com")
    end

    assert_equal "new-email@example.com", @staffer.reload.email.to_s
  end

  context "#toggle_warn_private_email" do
    test "toggles the warning" do
      refute @user.warn_private_email?
      @user.toggle_warn_private_email
      assert @user.warn_private_email?
    end

    test "sends toggle on to datadog" do
      GitHub.dogstats.expects(:increment).at_least_once
      GitHub.dogstats.expects(:increment).with("user.email.privacy.warning_toggle.on").at_least_once
      @user.toggle_warn_private_email
    end

    test "sends toggle off to datadog" do
      @user.toggle_warn_private_email
      GitHub.dogstats.expects(:increment).at_least_once
      GitHub.dogstats.expects(:increment).with("user.email.privacy.warning_toggle.off").at_least_once
      @user.toggle_warn_private_email
    end

    test "instruments event" do
      events = subscribe("user.toggle_warn_private_email")

      expected_payload = {
        warn_private_email: "enabled",
        user: @user.login,
        user_id: @user.id,
      }

      @user.toggle_warn_private_email

      assert event = events.pop
      assert_equal expected_payload, event.payload
    end
  end

  test "marks the first email saved as the primary" do
    @staffer.emails.delete_all
    assert_equal 0, @staffer.emails.size

    new_email = "staffer@example.com"

    @staffer.add_email(new_email)
    assert_equal 1, @staffer.emails.size

    @staffer.reload
    assert_equal new_email, @staffer.email
    assert_equal new_email, @staffer.primary_user_email.to_s
    assert_equal "84c802c4e93af8cb55194fff77c8dfa9", @staffer.gravatar_id
  end

  test "instruments adding new emails" do
    events = subscribe "user.add_email"
    new_email = "new@example.com"

    email = @staffer.add_email(new_email)
    assert email.valid?

    expected_payload = {
      actor: @staffer.login,
      actor_id: @staffer.id,
      user: @staffer.login,
      user_id: @staffer.id,
      email: new_email,
      note: new_email,
    }

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "does not instrument adding an invalid email" do
    events = subscribe "user.add_email"
    new_email = "invalid-email"

    email = @staffer.add_email(new_email)
    assert email.invalid?, "'#{new_email}' was expected to be an invalid email"
    assert @staffer.invalid?, "user should be invalid after adding invalid email"

    assert_empty events, "no events were expected"
  end

  test "instruments removing emails" do
    events = subscribe "user.remove_email"
    email = "new@example.com"
    added_email = @staffer.add_email(email)
    removed_email = @staffer.remove_email(email)

    expected_payload = {
      actor: @staffer.login,
      actor_id: @staffer.id,
      user: @staffer.login,
      user_id: @staffer.id,
      email: email,
      email_roles: nil,
      email_verified: false,
      note: email,
    }

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "can override the actor when adding a new email" do
    @staffer.expects(:instrument).with(:add_email,
      actor: @johndoe, email: "new-email@example.com", note: "new-email@example.com")
    email = @staffer.add_email("new-email@example.com", actor: @johndoe)
    assert email.valid?
  end

  test "doesn't save an existing email" do
    email = @staffer.add_email("janedoe@example.com")
    assert email.new_record? # i.e. it is not saved
    assert_equal ["staffer@example.com"], @staffer.reload.emails.map(&:to_s)
  end

  test "does save a fresh email" do
    assert !@staffer.add_email("brand-new@example.com").blank?
  end

  test "#gravatar_id is calculated" do
    assert_equal "84c802c4e93af8cb55194fff77c8dfa9", @staffer.gravatar_id
  end

  test "#gravatar_email is set to primary email" do
    assert_equal @staffer.email, @staffer.read_attribute(:gravatar_email)
    assert_equal @staffer.email, @staffer.gravatar_email
  end

  test "#gravatar_id correctly uses #gravatar_email" do
    @staffer.update_attribute :gravatar_email, "gravatar@example.com"
    assert_equal "0cef130e32e054dd516c99e5181d30c4", @staffer.gravatar_id
  end

  test "setting #gravatar_email updates #gravatar_id" do
    assert_equal "84c802c4e93af8cb55194fff77c8dfa9", @staffer.gravatar_id
    @staffer.update_attribute :gravatar_email, "gravatar@example.com"
    refute_equal @staffer.gravatar_email, @staffer.email
    assert_equal "0cef130e32e054dd516c99e5181d30c4", @staffer.gravatar_id
  end

  test "serialized primary_email is no longer used" do
    assert_equal "staffer@example.com", @staffer.email
    assert_nil @staffer._primary_email
    @staffer._primary_email = "foo@example.com"
    assert_equal "staffer@example.com", @staffer.email
    assert_equal "staffer@example.com", @staffer.primary_user_email.to_s
  end

  test "should set gravatar related attributes on create" do
    u = create(:user, email: "someone@example.com")
    assert_equal "someone@example.com", u.primary_user_email.to_s
    assert_equal "someone@example.com", u.email
    assert_equal "someone@example.com", u.gravatar_email
    assert_equal "someone@example.com", u.primary_user_email.to_s
    assert_equal "16d113840f999444259f73bac9ab8b10", u.gravatar_id
  end

  test "remove_email returns the deleted UserEmail" do
    u = create :user, email: "someone@example.com"
    email = u.add_email "other@example.com"
    result = u.remove_email "other@example.com"
    assert_equal email, result
  end

  context "when replacing primary after removing an email" do
    if GitHub.email_verification_enabled?
      test "does fall back to a verified address if primary is verified" do
        default = "#{SecureRandom.hex}@gmail.com"
        verified = "#{SecureRandom.hex}@gmail.com"

        u = create :user, email: default
        u.primary_user_email.verify!
        u.add_email(verified).verify!
        assert_equal default, u.email
        assert_equal 2, u.emails.count

        assert u.remove_email(default)
        assert_equal 1, u.emails.count
        assert_equal verified, u.email
        assert_equal verified, u.primary_user_email.to_s
      end

      test "doesn't fall back to an unverified address if primary is verified" do
        default = "#{SecureRandom.hex}@gmail.com"
        unverified = "#{SecureRandom.hex}@gmail.com"

        u = create :user, email: default
        u.primary_user_email.verify!
        u.add_email(unverified)
        assert_equal default, u.email
        assert_equal 2, u.emails.count

        refute u.remove_email(default)
        assert_equal 2, u.emails.count
        assert_equal default, u.email
        assert_equal default, u.primary_user_email.to_s
      end

      test "does fall back to an unverified address if primary is unverified" do
        default = "#{SecureRandom.hex}@gmail.com"
        unverified = "#{SecureRandom.hex}@gmail.com"

        u = create :user, email: default
        u.add_email(unverified)
        assert_equal default, u.email
        assert_equal 2, u.emails.count

        assert u.remove_email(default)
        assert_equal 1, u.emails.count
        assert_equal unverified, u.email
        assert_equal unverified, u.primary_user_email.to_s
      end
    else
      test "falls back to an unverified address" do
        default    = "#{SecureRandom.hex}@gmail.com"
        unverified = ["#{SecureRandom.hex}@gmail.com", "#{SecureRandom.hex}@gmail.com"]

        u = create :user, email: default
        unverified.each { |unverified| u.add_email(unverified) }

        assert_equal default, u.email
        assert_equal 3, u.emails.count
        assert u.remove_email(default)
        assert_equal 2, u.emails.count
        assert_includes unverified, u.email
        assert_includes unverified, u.primary_user_email.to_s
      end
    end

    test "sets the backup email to match the new primary email when user only wants passwords resets sent to primary" do
      default    = "#{SecureRandom.hex}@gmail.com"
      verified   = "#{SecureRandom.hex}@gmail.com"

      u = create :user, email: default
      u.add_email(verified).verify!
      u.allow_password_reset_with_primary_email_only
      assert_equal default, u.email
      assert_equal 2, u.emails.count

      assert u.remove_email(default)
      assert_equal 1, u.emails.count
      assert_equal verified, u.email
      assert_equal verified, u.primary_user_email.to_s
      assert_equal verified, u.reload_backup_user_email.to_s
    end

    if GitHub.mailchimp_enabled?
      test "updates the user's email address in Mailchimp if user has a marketing preference" do
        user = create :user, email: "someone@example.com"
        NewsletterPreference.set_to_marketing(user: user)

        new_email = user.add_email "other@example.com"
        new_email.verify!

        assert_enqueued_with job: MailchimpSubscribeJob, args: [new_email.id] do
          assert_enqueued_with job: MailchimpUnsubscribeJob, args: [user.id, "someone@example.com"] do
            user.remove_email("someone@example.com")
          end
        end
      end

      test "does not update the user's email address in Mailchimp if user has a transactional preference" do
        user = create :user, email: "someone@example.com"
        NewsletterPreference.set_to_transactional(user: user)

        new_email = user.add_email "other@example.com"
        new_email.verify!

        user.remove_email("someone@example.com")
        assert_no_enqueued_jobs only: MailchimpSubscribeJob
        assert_no_enqueued_jobs only: MailchimpUnsubscribeJob
      end
    end
  end

  test "gravatar email doesn't get changed when removing / adding emails" do
    other_email = @janedoe.add_email "other@example.com"
    other_email.verify!

    email = @janedoe.email
    @janedoe.remove_email email

    assert_equal "e1f3994f2632af3d1c8c2dcc168a10e6", @janedoe.gravatar_id
  end

  test "cannot remove email for users who have only one user-entered email" do
    @janedoe.primary_user_email.toggle_visibility
    assert_equal 2, @janedoe.emails.size
    assert_equal 1, @janedoe.emails.user_entered_emails.count

    assert_no_difference "@janedoe.emails.count" do
      refute @janedoe.remove_email(@janedoe.email)
    end
  end

  context "#billing_email_invalid" do
    test "allows apostrophes" do
      user = build :user, billing_email: "Sean.O'Shea@betfair.com"
      assert_valid user
    end

    test "can be blank" do
      user = User.new(email: nil)
      refute user.billing_email_invalid?

      user = User.new(email: "")
      refute user.billing_email_invalid?
    end

    test "allows a valid email" do
      user = User.new(email: "foo@example.com")
      refute user.billing_email_invalid?

      user = User.new(email: "john@hawthorn.email")
      refute user.billing_email_invalid?
    end

    test "rejects an invalid email" do
      user = User.new(email: "@")
      assert user.billing_email_invalid?

      user = User.new(email: "foo@")
      assert user.billing_email_invalid?

      user = User.new(email: "foo")
      assert user.billing_email_invalid?

      user = build :user, billing_email: "Sean.O'Shea@"
      assert user.billing_email_invalid?
    end
  end

  context "#set_primary_email" do
    test "sets the specific email as primary" do
      email1 = @staffer.primary_user_email
      email2 = @staffer.add_email("staffer-new-primary@example.com")
      assert_equal 2, @staffer.emails.size

      status = @staffer.set_primary_email(email2)

      assert_predicate status, :success?
      assert !email1.reload.primary_role?
      assert email2.reload.primary_role?
    end

    test "does not commit a failed transaction" do
      backup_email = @user.add_email("my-backup-email@example.com")
      @user.password = nil
      refute_equal @user.primary_user_email.email, backup_email.email

      # Make sure that the transaction will fail (since the User object is part of it, and it has
      # an invalid login).
      @user.login = "c++"
      assert_predicate @user, :changed?
      refute_predicate @user, :valid?

      status = @user.set_primary_email(backup_email)

      refute status.success?
      refute_equal backup_email.email, @user.primary_user_email.email
    end

    if GitHub.mailchimp_enabled?
      test "updates the user's email address in Mailchimp if user has marketing preference" do
        NewsletterPreference.set_to_marketing(user: @staffer)

        email1 = @staffer.primary_user_email
        email2 = @staffer.add_email("staffer-new-primary@example.com")

        assert_enqueued_with job: MailchimpSubscribeJob, args: [email2.id] do
          assert_enqueued_with job: MailchimpUnsubscribeJob, args: [@staffer.id, email1.email] do
            status = @staffer.set_primary_email(email2)
            assert_predicate status, :success?
          end
        end
        assert email2.reload.primary_role?
      end

      test "does not update the user's address in Mailchimp if the user is new" do
        user = build(:user, email: nil)
        email = build :user_email
        assert user.new_record?
        assert email.new_record?

        status = user.set_primary_email(email)

        assert_predicate status, :success?
        assert_no_enqueued_jobs only: MailchimpSubscribeJob
      end
    end
  end

  context "#set_primary_email!" do
    test "sets the specific email as primary" do
      email1 = @staffer.primary_user_email
      email2 = @staffer.add_email("staffer-new-primary@example.com")
      assert_equal 2, @staffer.emails.size

      @staffer.set_primary_email!(email2)

      assert !email1.reload.primary_role?
      assert email2.reload.primary_role?
    end

    test "raises and rolls back transaction on failure" do
      backup_email = @user.add_email("my-backup-email@example.com")
      refute_equal @user.primary_user_email.email, backup_email.email

      # Make sure that the transaction will fail (since the User object is part of it, and it has
      # an invalid login).
      @user.login = "c++"
      assert_predicate @user, :changed?
      refute_predicate @user, :valid?

      assert_raises(ActiveRecord::RecordInvalid) { @user.set_primary_email!(backup_email) }

      refute_equal @user.primary_user_email.email, backup_email.email
    end
  end

  context "#set_backup_email" do
    test "sets the specific email as backup" do
      email2 = @staffer.add_email("staffer-new-primary@example.com")
      email2.verify!
      assert_equal 2, @staffer.emails.size

      assert @staffer.set_backup_email(email2)
      assert email2.reload.backup_role?
      refute email2.reload.primary_role?
    end
  end

  if GitHub.mailchimp_enabled?
    context "#update_mailchimp_email" do
      test "enqueues a job to update the user's address in Mailchimp" do
        email1 = @staffer.primary_user_email
        refute_nil email1

        email2 = @staffer.add_email("staffer-new-primary@example.com")
        refute_equal email1.email, email2.email

        assert_enqueued_with job: MailchimpSubscribeJob, args: [email2.id] do
          assert_enqueued_with job: MailchimpUnsubscribeJob, args: [@staffer.id, email1.email] do
            @staffer.update_mailchimp_email(new_email: email2, old_email: email1)
          end
        end
      end

      test "returns nil if the old email or new email is nil" do
        refute @staffer.update_mailchimp_email(old_email: nil, new_email: @staffer.primary_user_email)
        refute @staffer.update_mailchimp_email(old_email: @staffer.primary_user_email, new_email: nil)
      end

      test "doesn't unsubscribe if the email isn't being changed" do
        email = @staffer.primary_user_email
        assert_enqueued_with job: MailchimpSubscribeJob, args: [email.id] do
          assert_enqueued_jobs 0, only: MailchimpUnsubscribeJob do
            @staffer.update_mailchimp_email(new_email: email, old_email: email)
          end
        end
      end
    end

    context "#send_signup_confirmation" do
      test "enqueues a signup confirmation job" do
        email = @staffer.primary_user_email
        assert_enqueued_with job: UserSignupConfirmationJob, args: [email.id] do
          @staffer.send_signup_confirmation(new_email: email, old_email: email)
        end
      end

      test "returns nil if the old email or new email is nil" do
        refute @staffer.send_signup_confirmation(old_email: nil, new_email: @staffer.primary_user_email)
        refute @staffer.send_signup_confirmation(old_email: @staffer.primary_user_email, new_email: nil)
      end

      test "only enqueues a job if the email addresses are the same" do
        email1 = @staffer.primary_user_email
        refute_nil email1

        email2 = @staffer.add_email("staffer-new-primary@example.com")
        refute_equal email1.email, email2.email

        @staffer.send_signup_confirmation(new_email: email2, old_email: email1)
        assert_no_enqueued_jobs only: UserSignupConfirmationJob
      end
    end
  end

  context "outbound_email" do
    test "defaults to primary email" do
      assert_equal @janedoe.email, @janedoe.outbound_email
      assert_equal @janedoe.primary_user_email.to_s, @janedoe.outbound_email
    end

    test "uses stealth email if the user wants to keep their email private" do
      user = early_access_user

      email = user.primary_user_email
      assert email.toggle_visibility
      assert_equal "#{user.id}+#{user.login}@users.noreply.#{GitHub.host_name}", user.outbound_email
    end
  end

  context "git_author_email" do
    test "defaults to primary email" do
      assert_equal @janedoe.email, @janedoe.git_author_email
      assert_equal @janedoe.primary_user_email.to_s, @janedoe.git_author_email
    end

    test "uses stealth email if the user wants to keep their email private" do
      user = early_access_user

      email = user.primary_user_email
      assert email.toggle_visibility
      assert email.reload.private?
      assert_equal "#{user.id}+#{user.login}@users.noreply.#{GitHub.host_name}", user.git_author_email
    end

    test "strips angle brackets" do
      user = create(:user)
      user.stubs(:email).returns("some<thin>g@someplace.com")

      assert_equal "something@someplace.com", user.git_author_email
    end
  end

  if GitHub.email_verification_enabled?
    context "mandatory email verification" do
      test "user can be made exempt from verification when actor is a staff member" do
        GitHub.stubs(:mandatory_email_verification_enabled?).returns(true)
        user = create(:user)
        staff = create(:staff_admin_user)
        refute user.exempt_from_mandatory_email_verification?

        user.disable_mandatory_email_verification(actor: staff)
        assert user.exempt_from_mandatory_email_verification?
      end

      test "user cannot be made exempt from verification when actor is not a staff member" do
        GitHub.stubs(:mandatory_email_verification_enabled?).returns(true)
        user = create(:user)
        non_staff = create(:user)
        refute user.exempt_from_mandatory_email_verification?

        user.disable_mandatory_email_verification(actor: non_staff)
        refute user.exempt_from_mandatory_email_verification?
      end

      test "mandatory verification can be restored when actor is a staff member" do
        user = create(:user)
        staff = create(:staff_admin_user)

        GitHub.stubs(:mandatory_email_verification_enabled?).returns(true)
        user.restore_mandatory_email_verification(actor: staff)
        refute user.exempt_from_mandatory_email_verification?
      end

      test "mandatory verification cannot be restored when actor is not a staff member" do
        user = create(:user)
        non_staff = create(:user)
        assert user.exempt_from_mandatory_email_verification?

        GitHub.stubs(:mandatory_email_verification_enabled?).returns(true)
        user.restore_mandatory_email_verification(actor: non_staff)
        assert user.exempt_from_mandatory_email_verification?
      end

      test "is instrumented when disabled" do
        GitHub.stubs(:mandatory_email_verification_enabled?).returns(true)
        @janedoe.require_email_verification!
        events = subscribe "staff.disable_mandatory_email_verification"
        expected_payload = {
          user: @janedoe.login,
          user_id: @janedoe.id,
          staff_actor: @staffer.login,
          staff_actor_id: @staffer.id,
          actor: User.staff_user.login,
          actor_id: User.staff_user.id,
        }

        @janedoe.disable_mandatory_email_verification(actor: @staffer)

        assert event = events.pop, "expected event"
        assert_equal expected_payload, event.payload
      end

      test "is instrumented when restored" do
        GitHub.stubs(:mandatory_email_verification_enabled?).returns(true)
        @janedoe.disable_mandatory_email_verification(actor: @staffer)
        events = subscribe "staff.restore_mandatory_email_verification"
        expected_payload = {
          user: @janedoe.login,
          user_id: @janedoe.id,
          staff_actor: @staffer.login,
          staff_actor_id: @staffer.id,
          actor: User.staff_user.login,
          actor_id: User.staff_user.id,
        }

        @janedoe.restore_mandatory_email_verification(actor: @staffer)

        assert event = events.pop, "expected event"
        assert_equal expected_payload, event.payload
      end
    end
  end
end
