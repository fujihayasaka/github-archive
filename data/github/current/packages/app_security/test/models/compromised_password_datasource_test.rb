# typed: true
# frozen_string_literal: true

require "test_helper"

class CompromisedPasswordDatasourceTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @user = create(:user_with_compromised_password)
    @compromised_password = create(:compromised_password, plain: COMPROMISED_USER_PASSWORD)
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  context "validations" do
    test "name is required" do
      assert_raises(ActiveRecord::RecordInvalid) do
        create(:compromised_password_datasource, name: nil, version: "1")
      end
    end

    test "version is required" do
      assert_raises(ActiveRecord::RecordInvalid) do
        create(:compromised_password_datasource, name: "asdf", version: nil)
      end
    end

    test "version must be unique per name" do
      create(:compromised_password_datasource, name: "asdf", version: "1")
      create(:compromised_password_datasource, name: "asdf", version: "2")
      create(:compromised_password_datasource, name: "qwer", version: "1")
      assert_raises(ActiveRecord::RecordInvalid) do
        create(:compromised_password_datasource, name: "asdf", version: "1")
      end
    end
  end

  def assert_stored_compromised_passwords(expected_count, shas)
    assert_equal expected_count, CompromisedPassword.where(sha1_password: shas).count
  end

  test "creates datasource and password records" do
    passwords = shas(10)

    cpd = CompromisedPasswordDatasource.store_passwords(
      name: "foo",
      version: "1",
      sha1_passwords: passwords,
    )

    refute_predicate cpd, :new_record?
    assert_stored_compromised_passwords 10, passwords
  end

  test "can work on multiple batches" do
    n = CompromisedPasswordDatasource::LOAD_BATCH_SIZE * 2
    passwords = shas(n)

    cpd = CompromisedPasswordDatasource.store_passwords(
      name: "foo",
      version: "1",
      sha1_passwords: passwords,
    )

    refute_predicate cpd, :new_record?
    assert_stored_compromised_passwords n, passwords
  end

  test "doesn't create passwords if datasource is invalid" do
    assert_no_difference("CompromisedPasswordDatasource.count") do
      assert_no_difference("CompromisedPassword.count") do
        assert_raises(ActiveRecord::RecordInvalid) do
          CompromisedPasswordDatasource.store_passwords(
            name: "foo",
            version: nil,
            sha1_passwords: shas(10),
          )
        end
      end
    end
  end

  test "adds datasource to existing password records" do
    passwords = shas(10)

    CompromisedPasswordDatasource.store_passwords(
      name: "foo",
      version: "1",
      sha1_passwords: passwords,
    )

    assert_no_difference("CompromisedPassword.count") do
      ds = CompromisedPasswordDatasource.store_passwords(
        name: "bar",
        version: "1",
        sha1_passwords: passwords,
      )

      assert_stored_compromised_passwords 10, passwords
    end
  end

  test "updates existing datasource and does not store duplicate password hashes" do
    passwords_one = shas(10)
    passwords_two = passwords_one.last(5) + shas(5)

    CompromisedPasswordDatasource.store_passwords(
      name: "foo",
      version: "1",
      sha1_passwords: passwords_one,
    )

    ds = CompromisedPasswordDatasource.store_passwords(
      name: "foo",
      version: "1",
      sha1_passwords: passwords_two,
    )

    assert_stored_compromised_passwords 15, passwords_one + passwords_two
  end

  test "raises an error if name is empty" do
    assert_raises(ActiveRecord::RecordInvalid) do
      CompromisedPasswordDatasource.store_passwords(
        name: "",
        version: "",
        sha1_passwords: [],
      )
    end
  end

  context "#check_for_compromise" do
    test "marks user record as compromised via login" do
      CompromisedPasswordDatasource.check_for_compromise(
        compromised_records: [[@user.login, COMPROMISED_USER_PASSWORD]],
        name: "qintel",
        version: "abc",
      )

      @user.reload

      assert_equal 1, @user.password_check_metadata.exact_email_and_password_match
    end

    test "marks user record as compromised via email" do
      CompromisedPasswordDatasource.check_for_compromise(
        compromised_records: [[@user.email, COMPROMISED_USER_PASSWORD]],
        name: "qintel",
        version: "abc",
      )

      @user.reload

      assert_equal 1, @user.password_check_metadata.exact_email_and_password_match
    end

    test "doesnt mark user as exact_match compromise when only password is provided" do
      CompromisedPasswordDatasource.check_for_compromise(
        compromised_records: [["", COMPROMISED_USER_PASSWORD]],
        name: "qintel",
        version: "abc",
      )
      @user.reload
      assert_equal 0, @user.password_check_metadata&.exact_email_and_password_match
    end

    test "doesnt mark user as exact_match compromise when only login is provided" do
      CompromisedPasswordDatasource.check_for_compromise(
        compromised_records: [[@user.login, ""]],
        name: "qintel",
        version: "abc",
      )
      @user.reload
      assert_equal 0, @user.password_check_metadata.exact_email_and_password_match
    end

    test "doesnt mark user as exact_match compromise when only email is provided" do
      CompromisedPasswordDatasource.check_for_compromise(
        compromised_records: [[@user.email, ""]],
        name: "qintel",
        version: "abc",
      )
      @user.reload
      assert_equal 0, @user.password_check_metadata.exact_email_and_password_match
    end

    test "doesnt mark user as exact_match compromise when login is provided but password is different" do
      CompromisedPasswordDatasource.check_for_compromise(
        compromised_records: [[@user.login, "a_different_password"]],
        name: "qintel",
        version: "abc",
      )
      @user.reload
      assert_equal 0, @user.password_check_metadata.exact_email_and_password_match
    end

    test "sends email notification" do
      AccountMailer.expects(:username_and_password_compromised).returns(stub(deliver_later: nil))
      CompromisedPasswordDatasource.check_for_compromise(
        compromised_records: [[@user.login, COMPROMISED_USER_PASSWORD]],
        name: "qintel",
        version: "abc",
      )
    end

    test "doesn't email user if they're already compromised" do
      @user.mark_compromised_via_direct_match(password: COMPROMISED_USER_PASSWORD, name: "qintel", version: "abc")
      @user.reload
      assert_equal 1, @user.password_check_metadata.exact_email_and_password_match

      AccountMailer.expects(:username_and_password_compromised).never

      CompromisedPasswordDatasource.check_for_compromise(
        compromised_records: [[@user.email, COMPROMISED_USER_PASSWORD]],
        name: "qintel",
        version: "abc",
      )
    end

    test "skips blank usernames and passwords" do
      compromised_records = [
        # Invalid records that should be skipped
        ["", "passworD1"],
        ["not-a-real-user", ""],

        # Make sure a valid email that should be marked compromised is in the batch to confirm we don't stop on the invalid records.
        [@user.email, COMPROMISED_USER_PASSWORD]
      ]
      CompromisedPasswordDatasource.check_for_compromise(
        compromised_records: compromised_records,
        name: "qintel",
        version: "abc",
      )

      @user.reload

      assert_equal 1, @user.password_check_metadata.exact_email_and_password_match

      # Assert that we don't emit for dropped credentials
      assert_dogstats_count_value 1, "auth.compromised_password.credentials_processed", tags: [
        "datasource:qintel",
        "version:abc"
      ]
      assert_dogstats_count_value 2, "auth.compromised_password.credentials_dropped", tags: [
        "datasource:qintel",
        "version:abc"
      ]
    end

    test "filters entry and does not raise 'string contains null byte' error with compromised password entry has a null byte value and matches a bcrypt stored user password" do
      # bcrypt is the user password type that triggers the
      # "string contains null byte" errors when providing a compromised password that includes a null byte
      GitHub::Password.stubs(:default_password_type).returns(GitHub::Password::BCrypt)
      u = create(:user, password: GitHub.default_password)

      CompromisedPasswordDatasource.check_for_compromise(
        compromised_records: [
          [u.login, "some_\u0000password"], # null byte in password (\u0000)

          # Make sure a valid email that should be marked compromised is in the batch to confirm we don't stop on the invalid records.
          [u.login, GitHub.default_password]
        ],
        name: "qintel",
        version: "abc",
      )

      u.reload
      assert_equal 1, u.password_check_metadata.exact_email_and_password_match
      assert_dogstats_count_value 1, "auth.compromised_password.credentials_processed", tags: [
        "datasource:qintel",
        "version:abc"
      ]
      assert_dogstats_count_value 1, "auth.compromised_password.credentials_dropped", tags: [
        "datasource:qintel",
        "version:abc"
      ]
    end

    test "does not fail when given invalid username or email" do
      # If we don't filter out invalid values, this throws:
      #   "Illegal mix of collations (utf8_general_ci,IMPLICIT) and (utf8mb4_unicode_520_ci,COERCIBLE) for operation '='"
      compromised_records = [
        # Invalid records that should be skipped
        ["not\u{D0FDE}valid", "passworD1"],
        ["not@\u{D0FDE}valid", "passworD1"],
        ["not@\xD8\x00valid", "passworD1"],

        # Make sure a valid email that should be marked compromised is in the batch to confirm we don't stop on the invalid records.
        [@user.email, COMPROMISED_USER_PASSWORD]
      ]
      CompromisedPasswordDatasource.check_for_compromise(
        compromised_records: compromised_records,
        name: "qintel",
        version: "abc",
      )

      @user.reload

      assert_equal 1, @user.password_check_metadata.exact_email_and_password_match

      # Assert that we don't emit for dropped credentials
      assert_dogstats_count_value 1, "auth.compromised_password.credentials_processed", tags: [
        "datasource:qintel",
        "version:abc"
      ]
      assert_dogstats_count_value 3, "auth.compromised_password.credentials_dropped", tags: [
        "datasource:qintel",
        "version:abc"
      ]
    end
  end

  context "#mark_import_as_finished" do
    test "sets correct time" do
      Timecop.freeze(Time.now) do
        datasource = create(:compromised_password_datasource, name: "qintel", version: "123fe")
        assert_nil datasource.import_finished_at
        datasource.mark_import_as_finished!
        assert_equal Time.now.to_i, datasource.import_finished_at.to_i
        assert_dogstats_increment 1, "auth.compromised_password.import_finished", tags: [
          "datasource:qintel",
          "version:123fe"
        ]
      end
    end
  end

  context "#instrumentation" do
    test "instruments direct match", skip_enterprise: !GitHub.weak_password_checking_enabled? do
      events = subscribe "user.exact_email_and_password_match"
      expected_payload = {
        compromised_password: @compromised_password,
        datasource_name: "qintel",
        datasource_version: "abc",
        user: @user.login,
        user_id: @user.id,
      }

      CompromisedPasswordDatasource.check_for_compromise(
        compromised_records: [[@user.login, COMPROMISED_USER_PASSWORD]],
        name: "qintel",
        version: "abc",
      )

      @user.reload

      assert_equal 1, @user.password_check_metadata.exact_email_and_password_match
      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload

      expected_tags = [
        "spammy:false",
        "employee:false",
        "tfa_enabled:false",
        "datasource:qintel",
        "version:abc"
      ]

      assert_dogstats_increment 1, "auth.compromised_password.email_match", tags: expected_tags
      assert_dogstats_increment 1, "auth.compromised_password.exact_match", tags: expected_tags
    end

    test "doesn't increment user interaction only bucket", skip_enterprise: !GitHub.weak_password_checking_enabled? do
      CompromisedPasswordDatasource.check_for_compromise(
        compromised_records: [[@user.login, COMPROMISED_USER_PASSWORD]],
        name: "qintel",
        version: "abc",
      )

      assert_dogstats_increment 0, "auth.compromised_password"
    end

    test "stats employee status", skip_enterprise: !GitHub.weak_password_checking_enabled? do
      become_github_staff(@user)
      CompromisedPasswordDatasource.check_for_compromise(
        compromised_records: [[@user.login, COMPROMISED_USER_PASSWORD]],
        name: "qintel",
        version: "abc",
      )
      assert_dogstats_increment 1, "auth.compromised_password.email_match", tags: [
        "spammy:false",
        "employee:true",
        "tfa_enabled:false",
        "datasource:qintel",
        "version:abc"
      ]
    end

    test "stats spammy status", skip_enterprise: !GitHub.weak_password_checking_enabled? do
      @user.mark_as_spammy
      CompromisedPasswordDatasource.check_for_compromise(
        compromised_records: [[@user.login, COMPROMISED_USER_PASSWORD]],
        name: "qintel",
        version: "abc",
      )

      assert_dogstats_increment 1, "auth.compromised_password.email_match", tags: [
        "spammy:true",
        "employee:false",
        "tfa_enabled:false",
        "datasource:qintel",
        "version:abc"
      ]
    end

    test "stats 2fa status" do
      make_two_factor_credential(@user)
      CompromisedPasswordDatasource.check_for_compromise(
        compromised_records: [[@user.login, COMPROMISED_USER_PASSWORD]],
        name: "qintel",
        version: "abc",
      )
      assert_dogstats_increment 1, "auth.compromised_password.email_match", tags: [
        "spammy:false",
        "employee:false",
        "tfa_enabled:true",
        "datasource:qintel",
        "version:abc"
      ]
    end

    test "stats records processed" do
      CompromisedPasswordDatasource.check_for_compromise(
        compromised_records: [%w[a a], %w[b b], %w[c c]],
        name: "qintel",
        version: "abc",
      )
      assert_dogstats_count_value 3, "auth.compromised_password.credentials_processed", tags: [
        "datasource:qintel",
        "version:abc"
      ]
    end
  end

  def shas(n)
    n.times.map { Digest::SHA1.hexdigest(SecureRandom.bytes(5)) } # rubocop:disable GitHub/InsecureHashAlgorithm
  end
end
