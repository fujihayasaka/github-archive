# typed: true
# frozen_string_literal: true

require "test_helper"

class SmsRegistrationTest < GitHub::TestCase
  extend EncryptedColumnTestHelper
  test_encrypted_column(:sms_registration, :encrypted_otp_secret)

  def new_sms_registration(user, primary: false, number: "+1 4158675310")
    reg = SmsRegistration.new(user_id: user.id)
    reg.encrypted_otp_secret = Base64.strict_encode64(OpenSSL::Random.random_bytes(32))
    reg.sms_number = number
    reg.is_primary = primary
    reg
  end

  test "primary registration can be updated" do
    user = create(:user, login: "user")

    new_sms_registration(user, primary: true, number: "+1 4158675310").save!
    reg = user.two_factor_primary_sms_registration
    reg.sms_provider = "test_two"
    assert_nothing_raised do
      reg.save!
    end
  end

  test "only one primary registration is allowed" do
    user = create(:user, login: "user")

    new_sms_registration(user, primary: true, number: "+1 4158675310").save!
    assert_raises do
      new_sms_registration(user, primary: true, number: "+1 4158675311").save!
    end
  end

  test "backup and sms must be different numbers" do
    user = create(:user, login: "user")

    new_sms_registration(user, primary: true, number: "+1 4158675310").save!
    assert_raises do
      new_sms_registration(user, number: "+1 4158675310").save!
    end
  end

  test "no more than two registrations are allowed" do
    user = create(:user, login: "user")

    new_sms_registration(user, primary: true, number: "+1 4158675310").save!
    new_sms_registration(user, number: "+1 4158675311").save!
    assert_raises do
      new_sms_registration(user, number: "+1 4158675312").save!
    end
  end

  test "validates number format" do
    user = create(:user)
    cred = SmsRegistration.new(user_id: user.id)
    cred.sms_number = "111222"
    refute_predicate cred, :valid?
    assert_includes_match /is invalid/, cred.errors[:sms_number]
  end

  if !GitHub.enterprise?
    test "cannot be create for a GitHub employee" do
      staff = create(:staff_admin_user)
      cred = SmsRegistration.new(user_id: staff.id, sms_number: "+1 4158675310", encrypted_otp_secret: Base64.strict_encode64(OpenSSL::Random.random_bytes(32)))
      refute_predicate cred, :valid?
      assert_includes_match /Cannot be created for GitHub employees/, cred.errors[:base]
    end

    test "cannot be create for an outside collaborator when org disallows sms" do
      GitHub.flipper[:two_factor_cap_enforcement].enable
      GitHub.flipper[:members_without_2fa_allowed].enable
      GitHub.flipper[:disallow_two_factor_methods].enable
      owner = create :user
      make_two_factor_credential(owner)
      org = create :organization, admin: owner
      repo = create(:private_repository, owner: org, from_example: :simple)
      collaborator = create :collaborator, repository: repo
      make_two_factor_credential(collaborator)

      perform_enqueued_jobs(only: [EnforceTwoFactorRequirementOnOrganizationJob]) do
        org.disallow_insecure_two_factor_methods actor: owner
      end

      cred = SmsRegistration.new(user_id: collaborator.id, sms_number: "+1 4158675310", encrypted_otp_secret: Base64.strict_encode64(OpenSSL::Random.random_bytes(32)))
      refute_predicate cred, :valid?
      assert_includes_match /SMS registration cannot be created for this user/, cred.errors[:base]
    end

    test "staff can destroy sms_registration that was created before they were staff" do
      user_will_be_staff = create(:user)
      cred = SmsRegistration.new(user_id: user_will_be_staff.id, sms_number: "+1 4158675310", encrypted_otp_secret: Base64.strict_encode64(OpenSSL::Random.random_bytes(32)))
      assert_predicate cred, :valid?
      cred.save!
      assert_equal 1, SmsRegistration.where(user_id: user_will_be_staff.id).size

      become_github_staff(user_will_be_staff)

      cred.destroy!
      assert_equal 0, SmsRegistration.where(user_id: user_will_be_staff.id).size
    end

    test "creation emits audit log event" do
      add_factor_events = subscribe "two_factor_authentication.add_factor"
      user = create(:user)

      new_sms_registration(user, primary: true, number: "+1 4158675310").save!

      assert add_event = add_factor_events.pop, "an event was expected"
    end

    test "deletion emits audit log event" do
      remove_factor_events = subscribe "two_factor_authentication.remove_factor"
      user = create(:user)

      reg = new_sms_registration(user, primary: true, number: "+1 4158675310")
      reg.save!
      reg.destroy!

      assert remove_event = remove_factor_events.pop, "an event was expected"
    end
  end
end
