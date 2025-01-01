# typed: true
# frozen_string_literal: true

require "test_helper"

class UserPasswordDependencyTest < GitHub::TestCase
  include HydroTestHelpers
  include AuthenticationHelpers
  include DogstatsTestHelpers

  fixtures do
    @staffer = create(:staff_admin_user, login: "staffer", plan: "medium", email: "staffer@example.com")
    create(:compromised_password, plain: COMPROMISED_USER_PASSWORD)
    create(:compromised_password, plain: COMPROMISED_USER_PASSWORD_K_ANON)
    @super_strong_password = "7RHCc@npyfpNNaZoGbpqLt]N6HRmgDkymMVy2YoEKNwRL?fzdEVU=@FN2YHddf8d"

    oauth_user = create(:user)
    @oauth_token = make_oauth(oauth_user, [:repo]).reset_token

    unless GitHub.enterprise?
      @managed_user = create :emu, :owner
      @emu_business = @managed_user.enterprise_managed_business
      @emu_admin = @emu_business.find_first_emu_owner
      @emu_admin.update(password: GitHub.default_password, password_confirmation: GitHub.default_password)
    end
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  def create_user(options = {})
    User.create({
      login: "user-#{SecureRandom.hex(12)}",
      email: Faker::Internet.email,
      password: GitHub.default_password,
    }.merge(options))
  end

  test "should require password" do
    assert_no_difference "User.count" do
      u = create_user(password: nil)
      assert_predicate u.errors[:password], :any?
    end
  end

  test "should require password to be a non-empty string" do
    assert_no_difference "User.count" do
      u = create_user(password: "")
      assert_equal ["can't be blank"], u.errors[:password]
    end
  end

  test "should require password to be a non-empty string on update" do
    user = create(:user)
    success = user.update(password: "", password_confirmation: "")
    assert !success
    assert_equal ["can't be blank"], user.errors[:password]
  end

  test "password length should be configurable" do
    begin
      new_length = 20
      assert new_length > GitHub.password_minimum_length

      GitHub.password_minimum_length = new_length
      assert new_length > GitHub.default_password.length

      assert_no_difference "User.count" do
        create_user(password: GitHub.default_password)
      end

      added_length = new_length - GitHub.default_password.length
      new_password = GitHub.default_password + ("1" * added_length)
      assert_difference "User.count" do
        create_user(password: new_password)
      end
    ensure
      GitHub.password_minimum_length = nil
    end
  end

  test "should not require password confirmation" do
    assert_difference "User.count" do
      create_user(password_confirmation: nil)
    end
  end

  test "should require password confirmation to not be blank when present" do
    assert_no_difference "User.count" do
      u = create_user(password_confirmation: "")
      assert u.errors[:password_confirmation].any?
    end
  end

  test "password confirmation must match the password" do
    assert_no_difference "User.count" do
      u = create_user(password: GitHub.default_password, password_confirmation: "airplane")
      assert_equal ["doesn't match the password"], u.errors[:password_confirmation]
    end
  end

  test "password should be > 7 chars" do
    assert_no_difference "User.count" do
      password = "aB1c"
      u = create_user(password: password)
      assert u.errors[:password].any?
    end
  end

  test "password must have a special character" do
    begin
      assert_no_difference "User.count" do
        GitHub.password_special_character_requirement = 1
        password = "1234567Aa"
        u = create_user(password: password)
        assert_includes u.errors[:password], "needs at least 1 special character"
      end
    ensure
      GitHub.password_special_character_requirement = nil
    end
  end

  test "emoji counts as a special character" do
    begin
      assert_difference "User.count" do
        GitHub.password_special_character_requirement = 1
        password = "123456Aa😀"
        u = create_user(password: password)
        assert_empty u.errors[:password]
      end
    ensure
      GitHub.password_special_character_requirement = nil
    end
  end

  test "unicode counts as a special character" do
    begin
      assert_difference "User.count" do
        GitHub.password_special_character_requirement = 1
        password = "123456Aaø"
        u = create_user(password: password)
        assert_empty u.errors[:password]
      end
    ensure
      GitHub.password_special_character_requirement = nil
    end
  end

  test "password must have a lower case character" do
    assert_no_difference "User.count" do
      password = "1234567A!"
      u = create_user(password: password)
      assert_includes u.errors[:password], "needs at least 1 lowercase letter"
    end
  end

  test "password must have a upper case character" do
    begin
      assert_no_difference "User.count" do
        GitHub.password_uppercase_requirement = 1
        password = "1234567a!"
        u = create_user(password: password)
        assert_includes u.errors[:password], "needs at least 1 uppercase letter"
      end
    ensure
      GitHub.password_uppercase_requirement = nil
    end
  end

  test "password must have a number" do
    assert_no_difference "User.count" do
      password = "Abcdefg!"
      u = create_user(password: password)
      assert_includes u.errors[:password], "needs at least 1 number"
    end
  end

  test "password can't include the login" do
    assert_no_difference "User.count" do
      user = "user-#{SecureRandom.hex(12)}"
      password = "#{user}A1!"
      u = create_user(password: password, login: user)
      assert_includes u.errors[:password], "cannot include your login"
    end
  end

  # BCcrypt, by design, allows passwords that are up to 72 characters.
  test "password can be 72 chars" do
    assert_difference "User.count" do
      password = "a" * 72
      u = create_user(password: password)
      refute u.errors[:password].any?
    end
  end

  # BCcrypt, by design, allows passwords that are up to 72 characters.  Any
  # additional characters are ignored. So, we just prevent people from using
  # such passwords to avoid confusion.
  test "password cannot be > 72 chars" do
    assert_no_difference "User.count" do
      password = "a" * 73
      u = create_user(password: password)
      assert u.errors[:password].any?
    end
  end

  test "when password used during creating is weak, increment tracker, block creation", skip_enterprise: !GitHub.weak_password_checking_enabled? do
    assert_no_difference "User.count" do
      u = create_user(password: COMPROMISED_USER_PASSWORD)
      assert_includes u.errors[:password], User::PasswordDependency::WEAK_PASSWORD_MESSAGE
    end
  end

  test "when password used during creating is not weak increment tracker for negative case, do not block", skip_enterprise: !GitHub.weak_password_checking_enabled? do
    assert_difference "User.count" do
      u = create_user(password: "securepassword123")
      refute_predicate u.errors[:password], :any?
    end
  end

  test "password doesn't require num and downcase letter if passphrase" do
    assert_difference "User.count" do
      password = "correct horse battery staple"
      u = create_user(password: password)
      assert !u.errors[:password].any?
    end
  end

  test "password doesn't require spaces if it's long enough" do
    assert_difference "User.count" do
      password = "thislongpassword"
      u = create_user(password: password)
      assert u.errors[:password].empty?
    end
  end

  test "password needs a number if short" do
    assert_no_difference "User.count" do
      password = "abcdefgh"
      u = create_user(password: password)
      assert u.errors[:password].any?
    end
  end

  test "password needs a downcase letter if short" do
    assert_no_difference "User.count" do
      password = "12345678"
      u = create_user(password: password)
      assert u.errors[:password].any?
    end
  end

  test "password can't be your username" do
    assert_no_difference "User.count" do
      password = "quireTux1"
      u = create_user(login: password, password: password)
      assert u.errors[:password].any?
    end
  end

  context "upgrade password storage" do
    test "upgrades when hash secret changes" do
      user = create(:user)
      password_hash = user.password_hash

      assert user.authenticated_by_password?(GitHub.default_password)
      assert_equal password_hash, user.password_hash

      existing_secret = GitHub.user_password_secrets.first

      GitHub.stubs(:user_password_secrets).returns([existing_secret, "some-dummy-value"])
      assert user.authenticated_by_password?(GitHub.default_password)
      assert_equal password_hash, user.password_hash

      GitHub.stubs(:user_password_secrets).returns(["some-dummy-value", existing_secret])
      assert user.authenticated_by_password?(GitHub.default_password)
      assert password_hash != user.password_hash
    end
  end

  context "User#update password" do
    test "should change password" do
      password = "new#{GitHub.default_password}"
      user = create_user
      user.update!(password: password)
      user_from_authenticate, message = User.authenticate(user.login, password)
      assert_equal user, user_from_authenticate
    end

    test "should not write bcrypt hash if not needed" do
      GitHub.stubs(:keep_legacy_bcrypt_password?).returns(false)
      password = "new#{GitHub.default_password}"
      user = create_user
      user.update!(password: password)
      user_from_authenticate, message = User.authenticate(user.login, password)
      assert_equal user, user_from_authenticate
      assert_nil user.bcrypt_auth_token, "Bcrypt token set when not expected"
    end

    test "should write bcrypt hash if needed" do
      GitHub.stubs(:keep_legacy_bcrypt_password?).returns(true)
      password = "new#{GitHub.default_password}"
      user = create_user
      user.update!(password: password)
      user_from_authenticate, message = User.authenticate(user.login, password)
      assert_equal user, user_from_authenticate
      assert user.bcrypt_auth_token, "No bcrypt token set when expected"
      assert BCrypt::Password.new(user.bcrypt_auth_token) == password, "New password doesn't match"
    end

    test "attempted password changed with weak password and disallow", skip_enterprise: !GitHub.weak_password_checking_enabled? do
      user = create_user
      saved_successfully = user.update(password: COMPROMISED_USER_PASSWORD)
      refute saved_successfully, "expected compromised password to prevent update"

      assert_includes user.errors[:password], User::PasswordDependency::WEAK_PASSWORD_MESSAGE
    end

    test "strong passwords are not blocked" do
      password = "a80fc00ae50994dabb077881"
      user = create_user
      saved_successfully = user.update!(password: password)

      refute_predicate user.errors[:password], :any?
      assert saved_successfully, "expected strong password to update"
    end

    test "should change password after correct confirmation" do
      password = SecureRandom.hex(12)
      user = create_user
      user.update!(password: password, password_confirmation: password)
      user_from_authenticate, message = User.authenticate(user.login, password)
      assert_equal user, user_from_authenticate
    end

    test "non password update should not rehash password" do
      login = SecureRandom.hex(12)
      user = create_user
      user.update(login: login)
      user_from_authenticate, message = User.authenticate(login, GitHub.default_password)
      assert_equal user, user_from_authenticate
    end

    test "regenerates token_secret" do
      user = create_user
      old_secret = user.signed_auth_token_secret
      password = SecureRandom.hex(12)
      user.update!(password: password, password_confirmation: password)
      refute_equal old_secret, user.signed_auth_token_secret
    end
  end

  context "User#change_password" do
    test "changes password" do
      old_password = SecureRandom.hex(12)
      user = create_user(password: old_password)
      password = SecureRandom.hex(12)
      user.change_password(
        old_password: old_password,
        password: password,
        password_confirmation: password
      )
      user_from_authenticate, message = User.authenticate(user.login, password)
      assert_equal user, user_from_authenticate
    end

    test "requires old_password" do
      old_password = SecureRandom.hex(12)
      user = create_user(password: old_password)
      password = SecureRandom.hex(12)
      user.change_password(
        old_password: nil,
        password: password,
        password_confirmation: password
      )
      user_from_authenticate, message = User.authenticate(user.login, password)
      assert_nil user_from_authenticate
    end

    test "requires correct old_password" do
      old_password = SecureRandom.hex(12)
      user = create_user(password: old_password)

      # expect a limit check
      AuthenticationLimit.expects(:at_any?).with(change_password_login: user.login, increment: false).once
      # expect a limit increment as well
      AuthenticationLimit.expects(:at_any?).with(change_password_login: user.login, increment: true).once

      new_password = SecureRandom.hex(12)
      changed = user.change_password(
        old_password: "bogus",
        password: new_password,
        password_confirmation: new_password
      )
      refute changed
      assert_equal ["isn't valid"], user.errors[:old_password]

      user_from_authenticate, message = User.authenticate(user.login, new_password)
      assert_nil user_from_authenticate
    end

    test "fails when limit is reached" do
      old_password = SecureRandom.hex(12)
      user = create_user(password: old_password)

      # expect a limit check and mock that it's returning true
      AuthenticationLimit.expects(:at_any?).with(change_password_login: user.login, increment: false).once.returns(true)

      new_password = SecureRandom.hex(12)
      changed = user.change_password(
        old_password: "bogus",
        password: new_password,
        password_confirmation: new_password
      )
      refute changed
      assert_equal ["Too many failed password change attempts due to an incorrect old password. Try again later."], user.errors[:base]

      user_from_authenticate, message = User.authenticate(user.login, new_password)
      assert_nil user_from_authenticate
    end

    test "incorrect old_password hits rate limit after 5 tries" do
      now = Time.now.beginning_of_day
      old_password = SecureRandom.hex(12)
      user = create_user(password: old_password)
      Timecop.freeze(now) do
        # can try 5 times before hitting the rate limitter
        5.times do
          new_password = SecureRandom.hex(12)
          changed = user.change_password(
            old_password: "bogus",
            password: new_password,
            password_confirmation: new_password
          )
          refute changed
          assert_equal ["isn't valid"], user.errors[:old_password]
          user_from_authenticate, message = User.authenticate(user.login, new_password)
          assert_nil user_from_authenticate
          user.errors.clear
        end

        # rate limitted attempt
        new_password = SecureRandom.hex(12)
        changed = user.change_password(
          old_password: "bogus",
          password: new_password,
          password_confirmation: new_password
        )
        refute changed
        assert_equal ["Too many failed password change attempts due to an incorrect old password. Try again later."], user.errors[:base]
        user_from_authenticate, message = User.authenticate(user.login, new_password)
        assert_nil user_from_authenticate
        user.errors.clear

        # even a correct password is still blocked
        new_password = SecureRandom.hex(12)
        changed = user.change_password(
          old_password: old_password,
          password: new_password,
          password_confirmation: new_password
        )
        refute changed
        assert_equal ["Too many failed password change attempts due to an incorrect old password. Try again later."], user.errors[:base]
        user_from_authenticate, message = User.authenticate(user.login, new_password)
        assert_nil user_from_authenticate
      end
    end

    test "correct password resets limits" do
      now = Time.now.beginning_of_day
      old_password = SecureRandom.hex(12)
      user = create_user(password: old_password)
      Timecop.freeze(now) do
        # call with bad password once
        1.times do
          new_password = SecureRandom.hex(12)
          changed = user.change_password(
            old_password: "bogus",
            password: new_password,
            password_confirmation: new_password
          )
          refute changed
          assert_equal ["isn't valid"], user.errors[:old_password]
          user_from_authenticate, message = User.authenticate(user.login, new_password)
          assert_nil user_from_authenticate
          user.errors.clear
        end

        # correct password
        new_password = SecureRandom.hex(12)
        changed = user.change_password(
          old_password: old_password,
          password: new_password,
          password_confirmation: new_password
        )
        assert changed
        user_from_authenticate, message = User.authenticate(user.login, new_password)
        assert_equal user, user_from_authenticate

        # can try 5 more times with bad old password before hitting the rate limitter case
        5.times do
          new_password = SecureRandom.hex(12)
          changed = user.change_password(
            old_password: "bogus",
            password: new_password,
            password_confirmation: new_password
          )
          refute changed
          assert_equal ["isn't valid"], user.errors[:old_password]
          user_from_authenticate, message = User.authenticate(user.login, new_password)
          assert_nil user_from_authenticate
          user.errors.clear
        end
      end
    end

    test "requires password_confirmation be the same as password" do
      old_password = SecureRandom.hex(12)
      user = create_user(password: old_password)
      password = SecureRandom.hex(12)
      user.change_password(
        old_password: old_password,
        password: password,
        password_confirmation: "foo"
      )
      user_from_authenticate, message = User.authenticate(user.login, password)
      assert_nil user_from_authenticate
    end

    test "should update weak password check result after successful password change", skip_enterprise: !GitHub.weak_password_checking_enabled? do

      old_password = SecureRandom.hex(12)
      user = create_user(password: old_password)
      password = SecureRandom.hex(12)
      now = Time.now.beginning_of_day
      Timecop.freeze(now) do
        check_result = PasswordCheckMetadata.new(
          discovery_timestamp: 25.days.ago.to_i,
          compromised_password_id: 10,
          exact_email_and_password_match: 1,
        ).to_binary_s
        user.update_attribute(:weak_password_check_result, check_result)
        user.change_password(
          old_password: old_password,
          password: password,
          password_confirmation: password
        )

        user_from_authenticate, message = User.authenticate(user.login, password)
        assert_equal user, user_from_authenticate

        metadata = user.password_check_metadata

        assert_equal 0, metadata.discovery_timestamp
        assert_equal 0, metadata.exact_email_and_password_match
        assert_equal 0, metadata.compromised_password_id
      end
    end

    test "instruments change_password" do
      old_password = SecureRandom.hex(12)
      user = create_user(password: old_password)
      password = SecureRandom.hex(12)
      events = subscribe "user.change_password"

      user.change_password(old_password: old_password, password: password, password_confirmation: password)

      event = events.pop
      refute_nil event, "expected a user.change_password event"
      assert_equal "user.change_password", event.name
    end

    test "sends password changed email" do
      old_password = SecureRandom.hex(12)
      user = create_user(password: old_password)
      password = SecureRandom.hex(12)

      AccountMailer.expects(:password_changed).with(user, "changed").returns(stub(deliver_later: nil))
      user.change_password(old_password: old_password, password: password, password_confirmation: password)
    end

    test "publishes PasswordUpdate hydro message" do
      GitHub.stubs(:hydro_enabled?).returns(true)
      now = Time.now.beginning_of_day

      Timecop.freeze(now) do
        old_password = SecureRandom.hex(12)
        user = create_user(password: old_password)
        password = SecureRandom.hex(12)

        GitHub.context.push(actor_ip: "1.2.3.4")
        GitHub.context.push(user_agent: "test agent")

        user.change_password(old_password: old_password, password: password, password_confirmation: password)

        assert_hydro_published(
          {
            request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
            actor: Hydro::EntitySerializer.user(user),
            account: Hydro::EntitySerializer.user(user),
            update_type: :USER_CHANGE,
            spamurai_form_signals: Hydro::EntitySerializer.spamurai_form_signals(GitHub.context[:spamuri_form_signals]),
          },
          schema: "github.v1.PasswordUpdate",
        )
      end
    end

    test "does not revoke oauth accesses" do
      old_password = SecureRandom.hex(12)
      user = create_user(password: old_password)
      password = SecureRandom.hex(12)

      Timecop.freeze(5.minutes.ago) do
        create(:oauth_access, user: user)
      end

      assert_predicate user.reload.oauth_accesses, :any?

      perform_enqueued_jobs(only: [RevokeOauthAccessesJob]) do
        assert_no_difference("user.reload.oauth_accesses.count") do
          user.change_password(old_password: old_password, password: password, password_confirmation: password)
        end
      end
    end

    unless GitHub.enterprise?
      test "does not change password on emu user" do
        new_password = SecureRandom.hex(12)
        refute @managed_user.change_password(old_password: @random_password, password: new_password, password_confirmation: new_password)
      end

      test "does not reset password on emu user" do
        new_password = SecureRandom.hex(12)
        refute @managed_user.apply_password_reset(password: new_password, password_confirmation: new_password)
      end

      test "does change password on first enterprise owner of emu" do
        new_password = SecureRandom.hex(12)
        assert @emu_admin.change_password(old_password: GitHub.default_password, password: new_password, password_confirmation: new_password)
      end

      test "does reset password on first enterprise owner of emu" do
        new_password = SecureRandom.hex(12)
        assert @emu_admin.apply_password_reset(password: new_password, password_confirmation: new_password)
      end
    end
  end

  context "#block_deadline" do
    test "ensure block deadline is correct when feature flag is enabled and user was just blocked" do

      block_start = 3.days.from_now.beginning_of_day
      block_string = (block_start + User::PasswordDependency::TIME_ALLOWED_BEFORE_BLOCK).strftime("%B %-d, %Y")
      Timecop.freeze(block_start) do
        user = create(:user)
        assert_equal 0, user.password_check_metadata.discovery_timestamp
        assert_equal block_string, user.block_deadline
      end
    end

    test "ensure block deadline is correct when feature flag is enabled and user was blocked before" do

      block_start = 3.days.ago.beginning_of_day
      block_string = (block_start + User::PasswordDependency::TIME_ALLOWED_BEFORE_BLOCK).strftime("%B %-d, %Y")
      Timecop.freeze(block_start) do
        user = create(:user)
        user.update_weak_password_check_result(compromised_password: CompromisedPassword.first)
        assert_equal block_start.to_i, user.password_check_metadata.discovery_timestamp
        assert_equal block_string, user.block_deadline
      end
    end
  end

  context "User#set_random_password" do
    test "randomizing a password" do
      password = "flibbertigibbet foxes squeal loudly"
      user = create_user(password: password)
      assert user.authenticated_by_password?(password)

      user.set_random_password(actor: nil)

      refute user.authenticated_by_password?(password)
    end

    test "should update weak password check result after successfully setting random password", skip_enterprise: !GitHub.weak_password_checking_enabled? do

      password = "flibbertigibbet foxes squeal loudly"
      user = create_user(password: password)
      assert user.authenticated_by_password?(password)

      now = Time.now.beginning_of_day
      Timecop.freeze(now) do
        check_result = PasswordCheckMetadata.new(
          discovery_timestamp: 25.days.ago.to_i,
          compromised_password_id: 10,
          exact_email_and_password_match: 1,
        ).to_binary_s
        user.update_attribute(:weak_password_check_result, check_result)
        user.set_random_password(actor: nil)
        refute user.authenticated_by_password?(password)

        metadata = user.password_check_metadata

        assert_equal 0, metadata.discovery_timestamp
        assert_equal 0, metadata.exact_email_and_password_match
        assert_equal 0, metadata.compromised_password_id
      end
    end

    test "instruments randomize_password" do
      events = subscribe "user.randomize_password"
      user = create_user

      user.set_random_password(actor: @staffer)

      event = events.pop
      refute_nil event, "expected a user.randomize_password event"
      assert_equal "user.randomize_password", event.name
      assert_equal user.id, event.payload[:user_id]
      if GitHub.guard_audit_log_staff_actor?
        assert_equal "github-staff", event.payload[:actor]
        assert_equal @staffer.login, event.payload[:staff_actor]
        assert_equal @staffer.id, event.payload[:staff_actor_id]
      else
        assert_equal @staffer.login, event.payload[:actor]
        assert_nil event.payload[:staff_actor]
      end
    end

    test "stats device unverification as a result of randomize_password", skip_unless: :sign_in_analysis_enabled? do
      disable_feature_flag(:verified_device_enforcement_opt_out)
      user = create_user
      create(:verified_authenticated_device, user: user)
      user.set_random_password(actor: nil)
      assert_dogstats_count_value 1, "authenticated_device", tags: ["action:unverify", "reason:password_randomized"]
    end

    test "revokes active sessions" do
      user = create_user
      create_list(:user_session, 3, user: user)
      refute_empty user.reload.sessions
      user.set_random_password(actor: nil)
      assert_empty user.reload.sessions.unrevoked
    end

    test "revokes oauth accesses" do
      user = create_user

      Timecop.freeze(5.minutes.ago) do
        create(:oauth_access, user: user)
      end

      assert_predicate user.reload.oauth_accesses, :any?
      perform_enqueued_jobs(only: [RevokeOauthAccessesJob]) do
        user.set_random_password(actor: nil)
      end
      assert_predicate user.reload.oauth_accesses, :none?
    end

    test "sends password changed email by default" do
      user = create_user

      AccountMailer.expects(:password_changed).with(user, "changed").returns(stub(deliver_later: nil))
      user.set_random_password(actor: nil)
    end

    test "does not send password changed email if send_notification is false" do
      user = create_user

      AccountMailer.expects(:password_changed).never
      user.set_random_password(actor: nil, send_notification: false)
    end

    test "publishes PasswordUpdate hydro message" do
      GitHub.stubs(:hydro_enabled?).returns(true)
      now = Time.now.beginning_of_day

      Timecop.freeze(now) do
        user = create_user

        GitHub.context.push(actor_ip: "1.2.3.4")
        GitHub.context.push(user_agent: "test agent")

        user.set_random_password(actor: @staffer)

        assert_hydro_published(
          {
            request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
            actor: Hydro::EntitySerializer.user(@staffer),
            account: Hydro::EntitySerializer.user(user),
            update_type: :SET_RANDOM,
            spamurai_form_signals: Hydro::EntitySerializer.spamurai_form_signals(GitHub.context[:spamuri_form_signals]),
          },
          schema: "github.v1.PasswordUpdate",
        )
      end
    end
  end

  context ".authenticate" do
    test "should authenticate user" do
      user = create_user(password: GitHub.default_password)
      authed_user, message = User.authenticate(user.email, GitHub.default_password)
      assert_equal user, authed_user
    end

    test "User.authenticate shouldn't authenticate user via OAuth access" do
      user, message = User.authenticate(@oauth_token, "x-oauth-basic")
      assert_nil user
    end

    test "User.authenticate shouldn't authenticate user via OAuth access with empty password" do
      user, message = User.authenticate(@oauth_token, "")
      assert_nil user
    end
  end
end
