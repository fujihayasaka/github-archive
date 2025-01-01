# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationProfileEmailTest < GitHub::TestCase
  include GitHub::LoggerHelper

  teardown do
    # The default state for GitHub::Logger in tests is disabled (to avoid
    # STDOUT noise).  So we should disable after every test.
  end

  fixtures do
    @org_admin = create(:user)
    @org = create(:organization, admin: @org_admin)
    @org.update(profile_email: "github@github.com")

    @second_org_admin = create(:user)
  end

  context "Email Validations" do
    test "profile_email does not allow nil values" do
      @org.update(profile_email: nil)
      refute build_org_profile_email.valid?
    end

    test "fails at database level when profile_email is nil" do
      @org.update(profile_email: nil)
      org_profile_email = build_org_profile_email

      assert_raises ActiveRecord::NotNullViolation do
        org_profile_email.save!(validate: false)
      end
    end

    test "profile_email does not allow invalid email formats" do
      ["john", "john@", "john@()", "john@   ", "@foo.com",
      "test@test.c@m", "user with spaces@foo.com",
      ".yo@foo.net", "me at here dot com", "me@test.(none)"].each do |invalid_email|
        @org.update(profile_email: invalid_email)
        org_profile_email = build_org_profile_email

        refute org_profile_email.valid?
        assert_equal ["does not look like an email address. Enter a valid email address in your organization profile."], org_profile_email.errors[:profile_email]
      end
    end

    test "profile_email does not allow email with trailing whitespaces" do
      @org.update(profile_email: "github@github.com     ")
      org_profile_email = build_org_profile_email

      refute org_profile_email.valid?
      assert_equal ["does not look like an email address. Enter a valid email address in your organization profile."], org_profile_email.errors[:profile_email]
    end

    test "profile_email does not allow email with null characters" do
      ["\0free-org@example.com",
      "\u0000free-org@example.com",
      "free-org@exam\0\0ple.com",
      "free-org@example.co\0\0m",
      "free-org@example.com\0\0"].each_with_index do |email, index|
        @org.update(profile_email: email)
        org_profile_email = build_org_profile_email
        refute org_profile_email.valid?
        assert_equal ["does not look like an email address. Enter a valid email address in your organization profile."], org_profile_email.errors[:profile_email].uniq, "email ##{index} should be invalid"
      end
    end

    test "profile_email allows valid special characters" do
      @org.update(profile_email: "tek.kub+rawr-imma$_bear@testing123.com")
      assert build_org_profile_email.valid?
    end
  end

  context "Duplicate Checks" do
    test "does not allow duplicate combination of org profile_email" do
      create_org_profile_email

      assert_raises ActiveRecord::RecordNotUnique do
        create_org_profile_email
      end
    end

    test "does not allow duplicate combination of org profile_email regardless of case sensitivity" do
      create_org_profile_email
      @org.update(profile_email: "github@GITHUB.com")

      assert_raises ActiveRecord::RecordNotUnique do
        create_org_profile_email
      end
    end

    test "allows different profile email for same org" do
      create_org_profile_email
      @org.update(profile_email: "othermail@github.com")

      assert build_org_profile_email.valid?
    end

    test "allows same profile_email for different org" do
      create_org_profile_email
      other_org = create(:organization)
      other_org.update(profile_email: @org.profile_email)
      other_org_profile_email = build(:organization_profile_email, organization: other_org)

      assert other_org_profile_email.valid?
      assert other_org_profile_email.save!
    end
  end

  context "Constraint Checks" do
    test "does not allow null initiator" do
      assert_raises ActiveRecord::NotNullViolation do
        create(:organization_profile_email, initiator: nil)
      end
    end

    test "default state is unverified" do
      org_profile_email = create_org_profile_email
      assert org_profile_email.reload.unverified?
    end

    test "returns email" do
      org_profile_email = create_org_profile_email
      assert org_profile_email.email
      assert_equal org_profile_email.profile_email, org_profile_email.email
    end
  end

  context "Request Verification" do
    context "Already Verified" do
      test "returns false" do
        org_profile_email = create(:organization_profile_email, :verified, organization: @org)

        refute org_profile_email.request_verification
      end

      test "does not send email" do
        org_profile_email = create(:organization_profile_email, :verified, organization: @org)

        AccountMailer.expects(:organization_email_verification).never
        org_profile_email.request_verification
      end
    end

    context "Invalid" do
      test "returns false" do
        @org.update(profile_email: "abc")
        org_profile_email = build_org_profile_email

        refute org_profile_email.request_verification
      end

      test "does not send email" do
        @org.update(profile_email: "abc")
        org_profile_email = build_org_profile_email

        AccountMailer.expects(:organization_email_verification).never
        org_profile_email.request_verification
      end
    end

    test "generates verification token" do
      org_profile_email = create_org_profile_email
      org_profile_email.request_verification

      assert org_profile_email.verification_token
    end

    test "sends verification email" do
      org_profile_email = create_org_profile_email
      AccountMailer.expects(:organization_email_verification).with(org_profile_email,
                                    requested_by: @org_admin,
                                    from_profile_email_verify: true).returns(stub(deliver_later: nil))
      org_profile_email.request_verification
    end

    test "returns true for successful request" do
      org_profile_email = create_org_profile_email
      assert org_profile_email.request_verification
    end

    test "instruments verification requests" do
      org_profile_email = create_org_profile_email

      events = subscribe "organization_profile_email.request_verification"
      expected_payload = {
        state: org_profile_email.state,
        note: org_profile_email.profile_email,
        organization_profile_email_id: org_profile_email.id,
        organization_profile_email: @org.profile_email,
        org: @org.login,
        org_id: @org.id,
        actor: @org_admin.login,
        actor_id: @org_admin.id,
      }

      org_profile_email.request_verification

      assert event = events.pop
      assert_equal expected_payload, event.payload
    end
  end

  context "Request Verification Resend" do
    test "regenerates verification token" do
      org_profile_email = create(:organization_profile_email, :with_verification_token, organization: @org)
      original_token = org_profile_email.verification_token

      @org.add_admin(@second_org_admin)
      org_profile_email.request_verification(initiator: @second_org_admin)

      refute_equal original_token, org_profile_email.reload.verification_token
    end

    test "updates initiator" do
      org_profile_email = create(:organization_profile_email, :with_verification_token, organization: @org)
      original_initiator = org_profile_email.initiator

      @org.add_admin(@second_org_admin)
      org_profile_email.request_verification(initiator: @second_org_admin)

      refute_equal original_initiator, org_profile_email.reload.initiator
      assert_equal @second_org_admin, org_profile_email.reload.initiator
    end

    test "resends verification email" do
      org_profile_email = create_org_profile_email
      @org.add_admin(@second_org_admin)
      AccountMailer.expects(:organization_email_verification).with(org_profile_email,
                                    requested_by: @org_admin,
                                    from_profile_email_verify: true).returns(stub(deliver_later: nil))
      AccountMailer.expects(:organization_email_verification).with(org_profile_email,
                                    requested_by: @second_org_admin,
                                    from_profile_email_verify: true).returns(stub(deliver_later: nil))
      org_profile_email.request_verification
      org_profile_email.request_verification(initiator: @second_org_admin)
    end

    test "returns true for successful resend" do
      org_profile_email = create(:organization_profile_email, :with_verification_token, organization: @org)
      @org.add_admin(@second_org_admin)
      assert org_profile_email.request_verification(initiator: @second_org_admin)
    end

    test "instruments verification request resends" do
      org_profile_email = create(:organization_profile_email, :with_verification_token, organization: @org)

      events = subscribe "organization_profile_email.request_verification_resend"
      expected_payload = {
        state: org_profile_email.state,
        note: org_profile_email.profile_email,
        organization_profile_email_id: org_profile_email.id,
        organization_profile_email: @org.profile_email,
        org: @org.login,
        org_id: @org.id,
        actor: @second_org_admin.login,
        actor_id: @second_org_admin.id,
      }

      @org.add_admin(@second_org_admin)
      org_profile_email.request_verification(initiator: @second_org_admin)

      assert event = events.pop
      assert_equal expected_payload, event.payload
    end
  end

  context "Confirm Verification" do
    context "Invalid Attempts" do
      test "rejects nil tokens" do
        org_profile_email = create(:organization_profile_email, :with_verification_token, organization: @org)
        org_profile_email.verify(nil, @org_admin)

        refute org_profile_email.reload.verified?
      end

      test "logs verification failure due to nil token" do

        org_profile_email = create(:organization_profile_email, :with_verification_token, organization: @org)

        assert_log_message(org_profile_email.id, nil, { "exception.message": "blank_token", "Body": "Email verification failed" }) do
          org_profile_email.verify(nil, @org_admin)
        end

        refute org_profile_email.reload.verified?
      end

      test "rejects if email has no verification_token" do
        org_profile_email = create(:organization_profile_email, :with_verification_token, organization: @org)
        token = org_profile_email.verification_token

        org_profile_email.clear_verification_token
        org_profile_email.save!

        org_profile_email.verify(token, @org_admin)
        refute org_profile_email.reload.verified?
      end

      test "logs verification failure due to missing verification_token" do
        org_profile_email = create(:organization_profile_email, :with_verification_token, organization: @org)
        token = org_profile_email.verification_token

        org_profile_email.clear_verification_token
        org_profile_email.save!

        assert_log_message(org_profile_email.id, nil, { "exception.message": "missing_token", "Body": "Email verification failed" }) do
          org_profile_email.verify(token, @org_admin)
        end

        refute org_profile_email.reload.verified?
      end

      test "rejects incorrect token" do
        org_profile_email = create(:organization_profile_email, :with_verification_token, organization: @org)

        result = org_profile_email.verify("xyz", @org_admin)
        refute result.success
      end

      test "logs verification failure due to incorrect token" do
        org_profile_email = create(:organization_profile_email, :with_verification_token, organization: @org)

        assert_log_message(org_profile_email.id, nil, { "exception.message": "incorrect_token", "Body": "Email verification failed" }) do
          result = org_profile_email.verify("xyz", @org_admin)
          refute result.success
        end
      end
    end

    context "Valid Attempts" do
      test "returns true" do
        org_profile_email = create(:organization_profile_email, :with_verification_token, organization: @org)

        assert org_profile_email.verify(org_profile_email.verification_token, @org_admin)
      end

      test "verifies email" do
        org_profile_email = create(:organization_profile_email, :with_verification_token, organization: @org)

        org_profile_email.verify(org_profile_email.verification_token, @org_admin)
        assert org_profile_email.reload.verified?
      end

      test "clears verification token" do
        org_profile_email = create(:organization_profile_email, :with_verification_token, organization: @org)
        refute_nil org_profile_email.verification_token

        org_profile_email.verify(org_profile_email.verification_token, @org_admin)
        assert_nil org_profile_email.reload.verification_token
      end

      test "saves verification details" do
        org_profile_email = create(:organization_profile_email, :with_verification_token, organization: @org)

        assert_nil org_profile_email.verified_at
        org_profile_email.verify(org_profile_email.verification_token, @org_admin)
        refute_nil org_profile_email.reload.verified_at
        refute_nil org_profile_email.reload.verifier
        assert_equal @org_admin, org_profile_email.reload.verifier
      end

      test "instruments email verification confirmation" do
        org_profile_email = create(:organization_profile_email, :with_verification_token, organization: @org)
        @org.add_admin(@second_org_admin)

        time = Time.zone.now.change(usec: 0)
        events = subscribe "organization_profile_email.confirm_verification"
        expected_payload = {
          state: "verified",
          note: org_profile_email.profile_email,
          verified_at: time,
          organization_profile_email_id: org_profile_email.id,
          organization_profile_email: @org.profile_email,
          org: @org.login,
          org_id: @org.id,
          actor: @second_org_admin.login,
          actor_id: @second_org_admin.id,
        }

        Timecop.freeze(time) do
          org_profile_email.verify(org_profile_email.verification_token, @second_org_admin)
        end

        assert event = events.pop
        assert_equal expected_payload, event.payload
      end
    end
  end

  private

  def build_org_profile_email
    build(:organization_profile_email, organization: @org)
  end

  def create_org_profile_email
    create(:organization_profile_email, organization: @org)
  end

  def assert_log_message(id, actor, error_context)
    log_fields = {
      "exception.type": "organization_profile_email_verification",
      "gh.organization.profile_email_id": id,
      "SeverityText": "WARN",
    }

    log_fields.merge!(error_context)

    assert_logged(**log_fields) do
      yield
    end
  end
end
