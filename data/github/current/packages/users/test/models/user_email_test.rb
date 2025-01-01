# typed: false
# frozen_string_literal: true

require "test_helper"

class UserEmailTest < GitHub::TestCase
  include MailchimpHelper
  include StringFromBinaryTestHelper

  fixtures do
    @user = create :user, login: "free-user", email: "free-user@example.com"
    @old_user = create :user, login: "old-user", email: "old-user@example.com", created_at: 1.day.ago
    @user.profile = create :profile, email: "profile-email@example.com"
    @repo = create(:repository, owner: @user)
    @email = @user.emails.first
    @old_email = @old_user.emails.first
    @organization = create(:organization, admin: @user)
  end

  test "email is tagged as UTF-8" do
    email = create :user_email, user: @user
    assert_equal Encoding::UTF_8, email.email.encoding
  end

  test "deobfuscated_email is tagged as UTF-8" do
    email = create :user_email, user: @user
    assert_equal Encoding::UTF_8, email.deobfuscated_email.encoding
  end

  [:email, :deobfuscated_email].each do |field|
    test "supports 3-byte emojis for #{field}" do
      # these fields can only save emojis with 3-byte characters
      encoded_value = "This3Bytes✨@example.com"
      encoded_value2 = "This3Bytes\xE2\x9C\xA8@example.com"
      encoded_value3 = "This3Bytes✅@example2.com"

      if field == :deobfuscated_email
        user_email = create(:user_email, email: encoded_value, deobfuscated_email: encoded_value)
        assert_multibyte_tracked_changes(user_email, field, encoded_value, encoded_value2, encoded_value3, :email)
      else
        user_email = create(:user_email, field => encoded_value)
        assert_multibyte_tracked_changes(user_email, field, encoded_value, encoded_value2, encoded_value3)
      end
    end
  end

  test "duplicate emails are invalid" do
    email = @user.emails.build email: "free-user@example.com"
    refute email.valid?
  end

  test "fails at the database level when there are duplicate emails" do
    email = @user.emails.build(email: @email.email)
    assert_raises ActiveRecord::RecordNotUnique do
      email.save!(validate: false)
    end
  end

  test "duplicate emails are invalid regardless of trailing spaces and case sensitivity" do
    email = @user.emails.build email: "  free-user@EXAMPLE.com   "
    refute email.valid?
  end

  context "cannot_create_claimed_email validation" do
    test "is never called on deletion" do
      @user.add_email("test@test.com")
      UserEmail.any_instance.expects(:cannot_create_claimed_email).never
      @user.emails.last.destroy
    end

    if GitHub.single_or_multi_tenant_enterprise?
      test "is never called" do
        UserEmail.any_instance.expects(:cannot_create_claimed_email).never

        email = @user.emails.build email: "test@test.com"
        email.valid?
      end
    else
      test "allows stealth emails through" do
        emu = create :emu
        email = "test@users.noreply.github.com"
        emu_email = emu.emails.first
        emu_email.email = emu.add_emu_shortcode_to_emails(email)
        emu_email.claimed = true
        emu_email.save!

        user_email = @user.emails.build email: email
        refute_includes user_email.errors[:email], "is already verified by another user"
        refute_includes user_email.errors[:email], "cannot be verified by users who are not enterprise managed"
      end

      test "does not fail when email is not valid" do
        user = User.new(email: "@")
        refute user.valid? && user.errors[:emails].any?
      end

      test "normal user cannot create email that is already claimed by an EMU" do
        emu = create :emu, email: "foobar@github.com"
        emu_email = emu.emails.first
        emu_email.claimed = true
        emu_email.save!

        email = @user.emails.build email: "foobar@github.com"
        refute email.valid?
        assert_equal 1, email.errors[:email].count
        assert_equal :claimed_email, email.errors.where(:email, :claimed_email).first.type
        assert_includes email.errors[:email], "is already verified by another user"
      end

      test "normal user cannot create email already claimed by an EMU case insensitive" do
        emu = create :emu, email: "foobar@github.com"
        emu_email = emu.emails.first
        emu_email.claimed = true
        emu_email.save!

        # search with upcase and existing email is downcase
        email = @user.emails.build email: "foobar@github.com".upcase
        refute email.valid?
        assert_equal 1, email.errors[:email].count
        assert_includes email.errors[:email], "is already verified by another user"

        emu_email.reload
        emu_email.email = emu_email.email.upcase
        emu_email.save!

        # search downcase after existing email is saved as upcase
        email = @user.emails.build email: "foobar@github.com"
        refute email.valid?
        assert_equal 1, email.errors[:email].count
        assert_includes email.errors[:email], "is already verified by another user"
      end

      test "normal user can create email that exists on EMU if the EMU email is not claimed" do
        emu = create :emu, email: "foobar@github.com"
        emu_email = emu.emails.first
        refute_predicate emu_email, :claimed?

        email = @user.emails.build email: "foobar@github.com"
        assert email.valid?
      end

      test "normal user cannot mark existing email as claimed" do
        user_email = @user.emails.first
        refute_predicate user_email, :claimed?

        user_email.claimed = true

        assert_raises_with_message(ActiveRecord::RecordInvalid, "Validation failed: Email cannot be verified by users who are not enterprise managed") do
          user_email.save!
        end
      end

      test "EMU user can create unclaimed email that is already claimed by another EMU" do
        emu = create :emu, email: "foobar@github.com"
        emu_email = emu.emails.first
        emu_email.claimed = true
        emu_email.save!

        assert_predicate emu_email, :claimed?

        another_emu = create :emu, email: "foobar@github.com"
        refute_equal emu.enterprise_managed_business, another_emu.enterprise_managed_business

        another_emu_email = another_emu.emails.first

        assert another_emu_email.valid?
        refute_predicate another_emu_email, :claimed?
        assert_equal emu_email.deobfuscated_email, another_emu_email.deobfuscated_email
      end

      test "EMU user can create unclaimed email that is not already claimed by another EMU" do
        emu = create :emu, email: "foobar@github.com"
        emu_email = emu.emails.first
        refute_predicate emu_email, :claimed?

        another_emu = create :emu, email: "foobar@github.com"
        refute_equal emu.enterprise_managed_business, another_emu.enterprise_managed_business

        another_emu_email = another_emu.emails.first

        assert another_emu_email.valid?
        refute_predicate another_emu_email, :claimed
        assert_equal emu_email.deobfuscated_email, another_emu_email.deobfuscated_email
      end

      test "EMU user can create unclaimed email that already exists on normal user" do
        user = create :user, email: "foobar@github.com"
        user_email = user.emails.first

        emu = create :emu, email: "foobar@github.com"
        emu_email = emu.emails.first
        refute_predicate emu_email, :claimed?

        assert_equal emu_email.deobfuscated_email, user_email.deobfuscated_email
      end

      test "EMU user can claim an email that does not match other EMU already claimed email with a dot" do
        emu = create :emu, email: "foobar@github.com"
        emu_email = emu.emails.first
        emu_email.claimed = true
        emu_email.save!

        other_emu = create :emu, email: "foo.bar@github.com"

        emu_email = other_emu.emails.first
        emu_email.claimed = true
        assert_predicate emu_email, :valid?
      end

      test "EMU user cannot claim an email that matches other EMU already claimed email" do
        emu = create :emu, email: "foobar+ghemu@github.com"
        emu_email = emu.emails.first
        emu_email.claimed = true
        emu_email.save!

        other_emu = create :emu, email: "foobar+ghemu@github.com"

        emu_email = other_emu.emails.first
        emu_email.claimed = true
        refute_predicate emu_email, :valid?
      end

      test "EMU user cannot claim an email that is already claimed by another EMU" do
        emu = create :emu, email: "foobar@github.com"
        emu_email = emu.emails.first
        emu_email.claimed = true
        emu_email.save!

        another_emu = create :emu, email: "foobar@github.com"
        refute_equal emu.enterprise_managed_business, another_emu.enterprise_managed_business

        another_emu_email = another_emu.emails.first
        assert_equal emu_email.deobfuscated_email, another_emu_email.deobfuscated_email

        another_emu_email.claimed = true
        assert_raises_with_message(ActiveRecord::RecordInvalid, "Validation failed: Email is already verified by another user") do
          another_emu_email.save!
        end
      end

      test "EMU user cannot claim an email that is already claimed by another EMU case insensitive" do
        emu = create :emu, email: "foobar@github.com"
        emu_email = emu.emails.first
        emu_email.claimed = true
        emu_email.save!

        another_emu = create :emu, email: "foobar@github.com"
        refute_equal emu.enterprise_managed_business, another_emu.enterprise_managed_business

        another_emu_email = another_emu.emails.first
        assert_equal emu_email.deobfuscated_email, another_emu_email.deobfuscated_email

        another_emu_email.update!(email: another_emu_email.email.upcase)

        # search with upcase and existing email is downcase
        another_emu_email.claimed = true
        assert_raises_with_message(ActiveRecord::RecordInvalid, "Validation failed: Email is already verified by another user") do
          another_emu_email.save!
        end

        emu_email.reload
        emu_email.email = emu_email.email.upcase
        emu_email.save!

        another_emu_email.reload
        another_emu_email.email = another_emu_email.email.downcase
        another_emu_email.claimed = true

        # search downcase after existing email is saved as upcase
        assert_raises_with_message(ActiveRecord::RecordInvalid, "Validation failed: Email is already verified by another user") do
          another_emu_email.save!
        end
      end

      test "EMU user cannot claim an email that already exists on a normal GitHub user" do
        create :user, email: "foobar@github.com"

        emu = create :emu, email: "foobar@github.com"
        emu_email = emu.emails.first
        refute_predicate emu_email, :claimed?

        emu_email.claimed = true
        assert_raises_with_message(ActiveRecord::RecordInvalid, "Validation failed: Email is already verified by another user") do
          emu_email.save!
        end
      end

      test "when not updating the email or claimed value the number of queries is different" do
        emu = create :emu
        emu_email = emu.emails.first

        assert_query_count(6, ignore_feature_flags: true) do
          emu_email.claimed = true
          emu_email.verification_token = "123"
          emu_email.save
        end

        assert_query_count(3, ignore_feature_flags: true) do
          emu_email.verification_token = "456"
          emu_email.save
        end
      end

      test "EMU user cannot claim an email that already exists on a normal GitHub user case insensitive" do
        user = create :user, email: "foobar@github.com"
        user_email = user.emails.first

        emu = create :emu, email: "foobar@github.com"
        emu_email = emu.emails.first
        refute_predicate emu_email, :claimed?

        emu_email.update(email: emu_email.email.upcase)
        # search with downcase and existing email is upcase
        emu_email.claimed = true
        assert_raises_with_message(ActiveRecord::RecordInvalid, "Validation failed: Email is already verified by another user") do
          emu_email.save!
        end

        user_email.reload
        user_email.email = user_email.email.downcase
        user_email.save!

        emu_email.reload
        emu_email.email = emu_email.email.upcase
        emu_email.claimed = true

        # search upcase after existing email is saved as downcase
        assert_raises_with_message(ActiveRecord::RecordInvalid, "Validation failed: Email is already verified by another user") do
          emu_email.save!
        end
      end

      test "EMU user can claim an email that is not already claimed by another EMU and doesn't exist on a normal user" do
        emu = create :emu, email: "foobar@github.com"
        emu_email = emu.emails.first
        refute_predicate emu_email, :claimed?

        another_emu = create :emu, email: "foobar@github.com"
        refute_equal emu.enterprise_managed_business, another_emu.enterprise_managed_business

        another_emu_email = another_emu.emails.first
        assert_equal emu_email.deobfuscated_email, another_emu_email.deobfuscated_email

        plain_email = emu.remove_shortcode(emu_email.email)
        assert_empty UserEmail.where(email: plain_email)

        another_emu_email.claimed = true
        another_emu_email.save!
        assert another_emu_email.valid?
        assert_predicate another_emu_email, :claimed?
      end

      test "EMU can unclaim an email" do
        emu = create :emu
        emu_email = emu.emails.first
        emu_email.claimed = true
        assert emu_email.save

        emu_email.claimed = false
        assert emu_email.save
      end

      test "EMU can validate an email prior to claiming by calling method directly with `requesting` flag set to true" do
        emu = create :emu, email: "foobar@github.com"
        emu_email = emu.emails.first
        emu_email.claimed = true
        emu_email.save!

        assert_predicate emu_email, :claimed?

        another_emu = create :emu, email: "foobar@github.com"
        refute_equal emu.enterprise_managed_business, another_emu.enterprise_managed_business

        another_emu_email = another_emu.emails.first
        assert_equal emu_email.deobfuscated_email, another_emu_email.deobfuscated_email

        another_emu_email.cannot_create_claimed_email(requesting: true)
        assert_equal "Email is already verified by another user", another_emu_email.errors.full_messages.to_sentence
      end

      test "EMU validation does not take into account pre claim requests with `requesting` flag left out" do
        emu = create :emu, email: "foobar@github.com"
        emu_email = emu.emails.first
        emu_email.claimed = true
        emu_email.save!

        another_emu = create :emu, email: "foobar@github.com"
        refute_equal emu.enterprise_managed_business, another_emu.enterprise_managed_business

        another_emu_email = another_emu.emails.first
        assert_equal emu_email.deobfuscated_email, another_emu_email.deobfuscated_email

        another_emu_email.cannot_create_claimed_email
        assert_empty another_emu_email.errors
      end
    end
  end

  test "emails with abusive special characters are marked as invalid" do
    ["foo\\@bar.com",
     "foo<>@bar.com",
     "foo\"@bar.com",
     "foo;@bar.com",
     "foo:@bar.com",
     "foo()@bar.com",
    ].each do |email|
      user_email = @user.emails.build email: email
      refute_predicate user_email, :valid?
      assert_includes user_email.errors[:email], "has invalid special characters", "#{email} was marked as valid but should be invalid"
    end
  end

  test "emails with encoded abusive characters are marked as invalid" do
    [
      # Encoded null character
      "=?x?q?YOUR_PAYLOAD=40oastify.com=3e=00?=foo@github.com",
      # SMTP injection through encoded ">(" substring
      "=?x?q?xxx=40yyy.zzz=3e=28?=@github.com",
    ].each do |email|
      user_email = @user.emails.build email: email
      refute_predicate user_email, :valid?
      assert_includes user_email.errors[:email], "has invalid special characters", "#{email} was marked as valid but should be invalid"
    end
  end

  test "emails encoded but without null characters are marked as valid" do
    email = "=?x?q?YOUR_PAYLOAD=40oastify.com?=foo@github.com"
    user_email = @user.emails.build email: email
    assert_predicate user_email, :valid?
  end

  test "emails with allowed special characters are valid" do
    ["John.O'Brien,and+sons@example.com",
     "simple-ci[bot]@gmail.com",
    ].each do |email|
      user_email = @user.emails.build email: email
      assert_predicate user_email, :valid?, "#{email} was marked as invalid but should be valid"
    end
  end

  test "duplicate emails are invalid regardless of null characters" do
    ["\0free-user@example.com",
     "\u0000free-user@example.com"
    ].each_with_index do |email, index|
      user_email = @user.emails.build email: email
      refute user_email.valid?
      assert_equal ["is taken"], user_email.errors[:email].uniq, "email ##{index} should be invalid"
    end
    ["free-user@exam\0\0ple.com",
     "free-user@example.co\0\0m"
    ].each_with_index do |email, index|
      user_email = @user.emails.build email: email
      refute user_email.valid?
      assert_equal ["does not look like an email address"], user_email.errors[:email].uniq, "email ##{index} should be invalid"
    end
  end

  test "duplicate emails that are already persisted are invalid" do
    dupe_email = build(:user_email, email: "free-user@example.com")
    dupe_email.save(validate: false)
    dupe_email = UserEmail.find(dupe_email.id)
    refute_nil dupe_email
    refute_predicate dupe_email, :valid?
  end

  test "the 'other' duplicate is also invalid" do
    dupe_email = build(:user_email, email: "free-user@example.com")
    dupe_email.save(validate: false)
    dupe_email = UserEmail.find(dupe_email.id)
    refute_nil dupe_email
    refute_predicate @email, :valid?
  end

  if GitHub.enterprise?
    test "on enterprise, new emails that do not end with a top level domain are valid" do
      email = UserEmail.new user: @user, email: "user@example"
      assert_predicate email, :valid?, "#{email.email} is valid on enterprise"
    end
  end

  unless GitHub.enterprise?
    test "on dot com, new emails that do not end with a top level domain or UUID are invalid" do
      email = UserEmail.new user: @user, email: "user@example"
      refute_predicate email, :valid?, "#{email.email} should not be valid"
      errors = email.errors.messages[:email]
      assert_predicate errors, :present?
      assert_equal "does not look like an email address", errors.first
    end

    test "on dot com, new emails ending with a uuid are valid" do
      email = UserEmail.new user: @user, email: "jonmagic@09069c07-60fa-4895-8316-727242e252e4"
      assert_predicate email, :valid?, "#{email.email} should be valid"
    end

    test "on dot com, emails that have already been created without a top level domain or UUID are valid" do
      email = create :user_email
      email.update_attribute :email, "user@example"
      assert_predicate email, :valid?, "#{email.email} should be valid"
    end
  end

  test "email with no duplicates is not #duplicate?" do
    email = create :user_email, user: @user
    refute email.duplicate?
  end

  test "both the original and the duplicate are #duplicate?" do
    email = create :user_email, user: @user
    dup   = create :user_email
    dup.update_column :email, email.email
    assert email.duplicate?
    assert dup.duplicate?
  end

  test "valid emails are valid" do
    email = UserEmail.new user: @user
    ["testing@example.com", "testing@subdomain.example.com", "user@unknown.tld",
      "user.foo@gmail.com", "John.O'Brien,and+sons@example.com",
      "customer/department=shipping@example.com", "_joe@example.com",
      "email@123.123.123.123", "testing@xn--dmain-0ta.xn--c1avg",
      "testing@xn--exmple-4nf.com"].each do |valid_email|
      email.email = valid_email
      assert email.valid?, "#{valid_email} should be valid"
    end
  end

  test "completely crazy invalid emails are invalid" do
    email = UserEmail.new user: @user
    invalid = ["john", "john@", "john@()", "john@   ", "@foo.com",
      "test@test.c@m", "user with spaces@foo.com"].each do |invalid_email|
      email.email = invalid_email
      assert !email.valid?, "#{invalid_email} should be invalid"
      assert email.errors[:email].any?
    end
  end

  test "emails cannot begin with a dot" do
    email = UserEmail.create user: @user, email: ".yo@foo.net"
    refute email.valid?
  end

  test "spaces get stripped" do
    email = UserEmail.create user: @user, email: "  testing@one.two.three.com  "
    assert_equal "testing@one.two.three.com", email.email
    assert email.valid?
  end

  test "spam paranoia is not valid" do
    email = UserEmail.create user: @user, email: "me at here dot com"
    assert !email.valid?
  end

  test "crazy chars not valid" do
    email = UserEmail.create user: @user, email: "me@test.(none)"
    assert !email.valid?
  end

  test "some chars are valid" do
    email = UserEmail.create user: @user, email: "tek.kub+rawr-imma$_bear@testing123.com"
    assert email.valid?
  end

  test "must be unicode 3" do
    funny_character = [0x1F514].pack("U")
    funny_address   = "#{funny_character}blah@example.com"

    email = UserEmail.create user: @user, email: funny_address

    assert !email.valid?
    assert_includes email.errors[:email], "doesn't accept 4-byte Unicode"
  end

  test "email validations are case insensitive" do
    email = UserEmail.create user: @user, email: @user.email.upcase
    assert !email.valid?
  end

  test "users cannot add GitHub stealth emails themselves" do
    email = UserEmail.new(email: "free-user@#{GitHub.stealth_email_host_name}", user: @user)
    assert !email.valid?
    assert_equal ["cannot add #{email} - use private email address toggle"], email.errors[:email]
    refute email.errors.where(:email, :sanctioned_email).any?
  end

  test "GitHub can add stealth emails for users with marker variable" do
    email = UserEmail.new(email: "free-user@#{GitHub.stealth_email_host_name}", user: @user, allow_stealth: true)
    assert email.save
    assert email.valid?
  end

  test "users cannot add emails with sanctioned domains" do
    ["test-user@sample.gov.ir", "test-user@justice.ir"].each do |sanctioned_email|
      email = UserEmail.new(user: @user, email: sanctioned_email)
      assert !email.valid?
      assert_equal 1, email.errors[:email].count
      assert_includes email.errors.where(:email, :sanctioned_email).first.message, "may be for an entity restricted under U.S. trade controls"
    end
  end

  test "users cannot update their valid email to sanctioned email" do
    email = UserEmail.new(user: @user, email: "user@example.com")
    assert email.valid?
    email.update_attribute(:email, "test-user@sanctioned.gov.ir")
    assert !email.valid?
    assert_equal 1, email.errors[:email].count
    assert_includes email.errors.where(:email, :sanctioned_email).first.message, "may be for an entity restricted under U.S. trade controls"
  end

  test "users cannot create new disposable emails" do
    GitHub.stubs(prevent_disposable_email_verification?: true) # Make sure test also works for enterprise
    email = UserEmail.new(user: @user, email: "email@mailinator.com")
    refute email.valid?
    assert_equal 1, email.errors[:email].count
    assert_equal email.errors.where(:email, :disposable_email).first.message, "domain could not be verified"
  end

  test "users can still update to disposable emails (if they were added before)" do
    email = UserEmail.new(user: @user, email: "user@example.com")
    assert email.valid?
    email.save
    email.email = "test-user@mailinator.com"
    assert email.valid?
    assert_equal 0, email.errors[:email].count
  end

  test "users can add emails from reserved domains, given flag" do
    enable_feature_flag(:reserved_domain)
    email = UserEmail.new(user: @user, email: "user@toyota.com", skip_reserved_domain: true)
    assert_equal true, email.valid?
  end

  if GitHub.enterprise?
    test "users can add emails from reserved domains, in enterprises" do
      enable_feature_flag(:reserved_domain)
      email = UserEmail.new(user: @user, email: "user@toyota.com")
      assert_equal true, email.valid?
    end
  else
    test "users can't add emails from reserved domains" do
      enable_feature_flag(:reserved_domain)
      email = UserEmail.new(user: @user, email: "user@toyota.com")
      assert_equal false, email.valid?
      assert_equal 1, email.errors[:email].count
      reserved_email_error = email.errors[:email]

      assert_equal reserved_email_error, [UserEmail::ReservedEmailDomainDependency::RESERVED_DOMAIN_NEW_EMAIL_MESSAGE]
    end
  end

  test "primary emails have the primary role" do
    non_primary = create(:user_email, email: "something@bestemaildomain.com", user: @user)
    create(:email_role, email_id: non_primary.id, role: "stealth")

    assert UserEmail.primary.include?(@email)
    refute UserEmail.primary.include?(non_primary)
  end

  test "backup emails have the backup role" do
    backup = @user.add_email("backup-email@example.com")
    backup.verify!
    @user.set_backup_email(backup)

    assert UserEmail.backup.include?(backup)
    refute UserEmail.backup.include?(@user.primary_user_email)
  end

  test "with a backup email set, password reset emails consist of the primary and backup" do
    backup = @user.add_email("backup-email@example.com")
    backup.verify!
    @user.set_backup_email(backup)
    @user.add_email("email2@example.com") # add an unverified email to ensure it's not returned

    expected_password_reset_emails = [@email, backup]
    assert_same_elements expected_password_reset_emails, @user.password_reset_emails
  end

  test "without a backup email set, password reset emails consist of the primary and all notifiable emails" do
    verified = @user.add_email("email1@example.com")
    verified.verify!
    verified2 = @user.add_email("email2@example.com")
    verified2.verify!
    @user.add_email("email2@example.com") # add an unverified email to ensure it's not returned

    expected_password_reset_emails = [@email, verified, verified2]
    assert_same_elements expected_password_reset_emails, @user.password_reset_emails
  end

  test "without a backup email set, password reset emails consist of the primary and all emails if none are verified" do
    unverified = @user.add_email("email1@example.com")
    unverified2 = @user.add_email("email2@example.com")

    expected_password_reset_emails = [@email, unverified, unverified2]
    assert_same_elements expected_password_reset_emails, @user.password_reset_emails
  end

  test "when opting out of using a backup email, password reset emails consist of just the primary" do
    verified = @user.add_email("email1@example.com")
    verified.verify!
    verified2 = @user.add_email("email2@example.com")
    verified2.verify!

    @user.allow_password_reset_with_primary_email_only
    @user.add_email("email2@example.com") # add an unverified email to ensure it's not returned
    assert_same_elements [@email], @user.password_reset_emails
  end

  test "with no verified emails, any email address can be used for password reset" do
    @email.unverify!
    another_unverified = @user.add_email("email1@example.com")
    assert_same_elements [@email, another_unverified], @user.password_reset_emails
  end

  test "enterprise managed user email cannot be set as bouncing", skip_enterprise: true do
    business = create :business, :enterprise_managed
    user = create :emu, business: business
    email = user.emails.first

    email.mark_as_bouncing!
    refute email.role?("hard_bounce")
  end

  test "can be marked as bouncing" do
    @email.mark_as_bouncing!
    assert @email.role?("hard_bounce")
  end

  test "mark_as_bouncing! is idempotent" do
    @email.mark_as_bouncing!
    @email.mark_as_bouncing!
    assert @email.role?("hard_bounce")
    assert_equal 1, @email.email_roles.to_a.count { |r| r.role == "hard_bounce" }
  end

  test "hard bounce clears verified state" do
    @email.verify!
    assert @email.verified?
    @email.mark_as_bouncing!
    refute @email.verified?
  end

  test "hard bounce clears verified_at timestamp" do
    @email.verify!
    refute_nil @email.verified_at

    @email.mark_as_bouncing!
    assert_nil @email.verified_at
  end

  test "hard bounce instruments a hard bounce log entry" do
    @email.verify!
    log = subscribe "user_email.hard_bounce"
    expected_payload = {
      state: "verified",
      note: @email.email,
      email_id: @email.id,
      email: @email.email,
      user: @email.user.login,
      user_id: @email.user_id,
      actor: @email.user.login,
      actor_id: @email.user_id,
      reason: "User does not exist",
      status: "5.5.0",
      source: "local",
    }

    @email.mark_as_bouncing!(source: "local", status: "5.5.0", reason: "User does not exist")
    assert (event = log.pop), "no hard_bounce audit log"
    assert_equal expected_payload, event.payload
  end

  test "hard bounce instruments an unverify audit log entry" do
    @email.verify!
    log = subscribe "user_email.unverify"
    expected_payload = {
      state: "unverified",
      note: @email.email,
      email_id: @email.id,
      email: @email.email,
      user: @email.user.login,
      user_id: @email.user_id,
      actor: @email.user.login,
      actor_id: @email.user_id,
    }

    @email.mark_as_bouncing!
    assert (event = log.pop), "unverify! event didn't occur"
    assert_equal expected_payload, event.payload
  end

  context "primary_first scope" do
    test "lists the primary email first" do
      primary_email = @user.primary_user_email
      secondary_email = @user.emails.create!(email: "secondary@example.com")
      suppressed_email = @user.emails.create!(email: "suppressed@example.com")
      suppressed_email.mark_as_suppressed!

      assert_equal primary_email, @user.emails.primary_first.first
    end

    test "lists the primary email first even if it's marked as stealthy" do
      primary_email = @user.primary_user_email
      assert primary_email.toggle_visibility
      secondary_email = @user.emails.create!(email: "secondary@example.com")
      suppressed_email = @user.emails.create!(email: "suppressed@example.com")
      suppressed_email.mark_as_suppressed!

      assert_equal primary_email, @user.emails.primary_first.first
    end
  end

  test "visible emails does not include emails marked as private" do
    @user.primary_user_email.toggle_visibility
    email2 = @user.emails.create!(email: "second@example.com")
    assert !@email.public?, "primary email should not be public"
    stealth_email = @user.emails.with_role("stealth")
    refute_nil stealth_email
    assert_equal [stealth_email, email2].to_set, @user.emails.visible.to_set
  end

  test "user_entered_emails only includes emails the user has actually input (excludes things like Stealth email)" do
    email2 = @user.emails.create!(email: "second@example.com")
    assert @user.primary_user_email.toggle_visibility

    assert_equal 3, @user.emails.count # ensure we have 2 normal + 1 stealth email
    assert_equal [@email, email2].to_set, @user.emails.user_entered_emails.to_set
  end

  test "verified emails only includes verified non-stealth emails" do
    email2 = @user.emails.create!(email: "second@example.com")
    email2.verify!
    assert @user.primary_user_email.toggle_visibility

    assert_equal 3, @user.emails.count
    assert_equal [email2].to_set, @user.emails.verified.to_set
  end

  test "removing an email removes it from user profile" do
    user = create(:user)
    email = user.emails.create!(email: "peter.murphy@bauhaus.com")
    Profile.create(user: user, email: email.email)
    email.destroy
    assert_nil user.profile.reload.email
  end

  context "#mark_as_suppressed!" do
    test "creates a suppressed email role for the email" do
      @email.mark_as_suppressed!
      assert @email.role?("suppressed")
    end

    test "is idempotent" do
      @email.mark_as_suppressed!
      @email.mark_as_suppressed!
      assert @email.role?("suppressed")
      assert_equal 1, @email.email_roles.to_a.count { |r| r.role == "suppressed" }
    end

    if GitHub.mailchimp_enabled?
      test "unsubscribes the email from our Mailchimp list" do
        assert_enqueued_with job: MailchimpUnsubscribeJob, args: [@user.id, @email.email] do
          @email.mark_as_suppressed!
        end
      end
    else
      test "does not unsubscribe the email from our Mailchimp list" do
        @email.mark_as_suppressed!
        assert_no_enqueued_jobs only: MailchimpUnsubscribeJob
      end
    end

    test "doesn't queue unsubscribes for stealth email addresses" do
      @user.primary_user_email.toggle_visibility
      email = @user.emails.find { |e| e.role?("stealth") }

      email.mark_as_suppressed!
      assert_no_enqueued_jobs only: MailchimpUnsubscribeJob
    end
  end

  context "#suppressed?" do
    test "true if the email is suppressed" do
      @email.mark_as_suppressed!
      assert @email.suppressed?
    end

    test "false otherwise" do
      refute @email.role?("suppressed")
      refute @email.suppressed?
    end

    context "user is already on Suppression List" do
      test "suppresses new email addresses" do
        SuppressionList.add_user(@user)
        assert SuppressionList.includes_user?(@user)

        new_email = @user.add_email("second_address@example.com")
        assert new_email.suppressed?
      end
    end
  end

  context "#stealth?" do
    test "true if the email has the stealth role" do
      @user.primary_user_email.toggle_visibility
      email = @user.emails.find { |e| e.role?("stealth") }

      assert email.stealth?
    end

    test "false otherwise" do
      refute @email.role?("stealth")
      refute @email.stealth?
    end
  end

  context "#remove_email" do
    test "removing removing email address sends a notification" do
      ActionMailer::Base.deliveries.clear
      new_email = "some-new-email@example.com"
      added = @user.add_email(new_email)
      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        @user.remove_email(new_email)
      end

      assert_equal "[GitHub] An email address was removed from your account.", ActionMailer::Base.deliveries.last.subject
    end

    test "does not notify user of email address is removed by staff" do
      staff = create(:staff_admin_user)
      @user.add_email("some-new-email@example.com")

      assert_no_difference "ActionMailer::Base.deliveries.count" do
        @user.remove_email("some-new-email@example.com", actor: staff)
      end
    end
  end

  context "#add_email" do
    setup do # rubocop:disable GitHub/NestedSetupTeardown
      @log = subscribe "user.add_email"
    end

    test "instruments addition on existing users" do
      expected_payload = {
        email: "rawr@bear.org",
        note: "rawr@bear.org",
        user: @user.login,
        user_id: @user.id,
        actor: @user.login,
        actor_id: @user.id,
      }

      @user.add_email "rawr@bear.org"

      assert event = @log.pop
      assert_equal expected_payload, event.payload
    end

    test "does not instrument new user email validation" do
      user = User.new(email: "rawr")
      assert !user.valid?
      assert !@log.pop
    end

    test "adding an email address sends a notification" do
      AccountMailer.expects(:email_address_added).returns(stub(deliver_later: nil))
      @user.add_email("some-new-email@example.com")
    end

    test "does not nofity user of new email address if it is their signup email" do
      AccountMailer.expects(:email_address_added).never
      user = create :user, email: "foo@bar.com"
      user.add_email("foo@bar.com")
    end

    test "does not notify user of new email address if it was added by staff" do
      AccountMailer.expects(:email_address_added).never
      @user.add_email("some-new-email@example.com", actor: create(:staff_admin_user))
    end
  end

  test "adding an email rebuilds contributions for the user" do
    assert_enqueued_jobs 1, only: UserContributionsBackfillJob, queue: "user_contributions_backfill" do
      @user.add_email "some-new-email@example.com"
    end

    assert_enqueued_with(job: UserContributionsBackfillJob, args: [[@repo.id], @user.id, { context: "user_add_email" }], queue: "user_contributions_backfill")
  end

  test "removing an email rebuilds contributions for the user" do
    @email.verify!

    # we cannot remove the only email, so add another verified email to allow us to do a remove
    assert_enqueued_jobs 1, only: UserContributionsBackfillJob, queue: "user_contributions_backfill" do
      email = @user.add_email "some-new-email@example.com"
      email.verify!
    end

    assert_enqueued_with(job: UserContributionsBackfillJob, args: [[@repo.id], @user.id, { context: "user_add_email" }], queue: "user_contributions_backfill")

    reset_job_hash_locks(job: UserContributionsBackfillJob)

    assert_enqueued_jobs 1, only: UserContributionsBackfillJob, queue: "user_contributions_backfill" do
      create(:commit_contribution, :with_summaries, repository: @repo, user: @user)
      @user.remove_email @user.emails.first
    end

    assert_enqueued_with(job: UserContributionsBackfillJob, args: [[@repo.id], @user.id, { context: "user_remove_email" }], queue: "user_contributions_backfill")
  end

  test "refuses to run multiple user contributions jobs for a given repository" do
    # we cannot remove the only email, so add another to allow us to do a remove
    assert_enqueued_jobs 1, only: UserContributionsBackfillJob, queue: "user_contributions_backfill" do
      @user.add_email "some-new-email@example.com"
    end

    assert_enqueued_jobs 0, only: UserContributionsBackfillJob, queue: "user_contributions_backfill" do
      @user.add_email "some-other-email@example.com"
    end
  end

  context "notifiable emails" do
    if GitHub.email_verification_enabled?
      test "notifiable finder prefers verified emails" do
        assert_equal [@user.primary_user_email], @user.emails.notifiable
        verified_email = @user.add_email "verified@example.com"
        verified_email.verify!

        assert verified_email.verified?
        assert_equal [verified_email], @user.emails.reload.notifiable
      end

      test "returns all unverified emails if there are no verified emails" do
        assert !@user.primary_user_email.verified?
        assert_equal [@email.email].to_set, @user.notifiable_emails
        new_email = "unverified@example.com"
        @user.add_email(new_email)

        # reload the User because #notifiable_emails memoizes the results
        user = User.find_by(id: @user.id)
        assert_equal [@email.email, new_email].to_set, user.notifiable_emails
      end

      test "returns only the verified email(s) when they exist" do
        assert GitHub.email_verification_enabled?
        email_2 = @user.add_email "email_2@example.com"
        email_3 = @user.add_email "email_3@example.com"
        email_4 = @user.add_email "email_4@example.com"
        email_2.verify!
        email_3.verify!
        assert_equal [email_2.to_s, email_3.to_s].to_set, @user.notifiable_emails
      end
    else # Enterprise doesn't have email verification enabled
      test "returns all notifiable emails when email verification is disabled" do
        assert !GitHub.email_verification_enabled?
        email_2 = @user.add_email "email_2@example.com"
        @user.reload
        assert_equal [@user.email, email_2.to_s].to_set, @user.notifiable_emails
      end
    end

    test "ignores stealth emails" do
      @user.primary_user_email.toggle_visibility
      assert @user.primary_user_email.private?
      assert_equal [@user.email].to_set, @user.notifiable_emails
    end

    test "ignores bouncing emails" do
      @user.primary_user_email.verify!

      hard_bounce = @user.add_email "hard-bounce@example.com"
      hard_bounce.verify!
      hard_bounce.mark_as_bouncing!

      assert_equal [@user.email].to_set, @user.notifiable_emails

      hard_bounce.verify!

      # reload the User because #notifiable_emails memoizes the results
      user = User.find_by(id: @user.id)
      assert_equal [@user.email, hard_bounce.email].to_set, user.notifiable_emails
    end
  end

  context "state" do
    test "state defaults to 'unverified'" do
      assert_equal "unverified", @email.state
    end

    test "fails validation for an invalid state" do
      @email.state = "invalid"
      assert_equal false, @email.valid?
      assert @email.errors[:state].any?
    end

    test "can verify! to change state verified" do
      assert @email.verify!
      assert_equal "verified", @email.state
    end
  end

  context ".not_bouncing" do
    test "excludes hard bouncing emails" do
      assert @email.email_roles.primary.exists?
      create(:email_role, :hard_bouncing, email: @email)

      refute_includes UserEmail.not_bouncing, @email
    end

    test "includes non-bouncing emails" do
      assert @email.email_roles.primary.exists?
      assert_includes UserEmail.not_bouncing, @email
    end
  end

  context ".unverified" do
    test "returns any emails in unverified or nil (i.e. a legacy) state" do
      @legacy_email = @user.add_email "legacy-email@foo.com"
      @legacy_email.update_attribute(:state, nil)
      assert_equal [@legacy_email, @email].to_set, @user.emails.reload.unverified.to_set
    end
  end

  context "request_verification_reminder" do
    test "returns false if user is already verified" do
      @email.state = "verified"
      assert_equal false, @email.request_verification_reminder
    end

    test "does not send the email if user is verified" do
      @email.state = "verified"
      SignupsReminderMailer.expects(:email_verification).never
      @email.request_verification_reminder
    end

    test "sends reminder verification email" do
      email = create(:user_email, :launch_code)
      SignupsReminderMailer.expects(:launch_code_verification).with(email).returns(stub(deliver_later: nil))
      email.request_verification_reminder
    end

    test "does not send email if unverifiable" do
      email = @user.add_email "fake@localhost"
      SignupsReminderMailer.expects(:deliver_email_verification).never
      email.request_verification
    end

    test "generates token" do
      @old_email.verification_token = nil
      @old_email.request_verification_reminder
      refute_nil @old_email.verification_token
    end

    test "instruments verification requests" do
      events = subscribe "user_email.request_verification_reminder"
      expected_payload = {
        state: @email.state,
        note: @email.email,
        email_id: @email.id,
        email: @email.email,
        user: @email.user.login,
        user_id: @email.user_id,
        actor: @email.user.login,
        actor_id: @email.user_id,
      }

      @email.request_verification_reminder

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end
  end

  context "request_verification" do
    context "already verified" do
      test "returns false" do
        @email.state = "verified"
        assert_equal false, @email.request_verification
      end

      test "does not send the email" do
        @email.state = "verified"
        SignupsMailer.expects(:email_verification).never
        @email.request_verification
      end
    end

    test "does not send email if unverifiable" do
      email = @user.add_email "fake@localhost"
      SignupsMailer.expects(:deliver_email_verification).never
      email.request_verification
    end

    test "generates launch code with launch code that has not yet expired" do
      @email.update!(verification_token: nil)
      assert_nil @email.verification_token

      @email.request_verification
      assert_equal UserEmail::LAUNCH_CODE_LENGTH, @email.verification_token.length
      assert_predicate @email, :launch_code_verification?
      assert_equal Users::Kv.store.get(@email.kv_launch_code_key).value!, "true"
    end

    test "does not generate launch code if email isn't primary" do
      @email.verify!

      other_email = create(:user_email, user: @email.user)
      other_email.request_verification
      assert_equal 40, other_email.verification_token.length
      refute_predicate other_email, :launch_code_verification?
    end

    test "generates launch code if previously was a launch code" do
      @email.update!(verification_token: "1" * UserEmail::LAUNCH_CODE_LENGTH)
      assert_predicate @email, :launch_code_verification?

      @email.request_verification
      assert_equal UserEmail::LAUNCH_CODE_LENGTH, @email.reload.verification_token.length
      assert_predicate @email, :launch_code_verification?
    end

    test "sends email for launch code verification if email is using launch code" do
      email = create(:user_email, :launch_code)
      assert_predicate email, :launch_code_verification?
      SignupsMailer.expects(:launch_code_verification).with(email, invitation_token: nil, repo_invitation_token: nil).returns(stub(deliver_later: nil))
      email.request_verification
    end

    test "sends email for organization verification" do
      @email.user = @organization
      AccountMailer.expects(:organization_email_verification).with(@email,
                                                                   requested_by: :user,
                                                                   redirect: :path).returns(stub(deliver_later: nil))
      @email.request_verification(requested_by: :user, redirect: :path)
    end

    test "instruments verification requests" do
      events = subscribe "user_email.request_verification"
      expected_payload = {
        state: @email.state,
        note: @email.email,
        email_id: @email.id,
        email: @email.email,
        user: @email.user.login,
        user_id: @email.user_id,
        actor: @email.user.login,
        actor_id: @email.user_id,
      }

      @email.request_verification

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "instruments verification confirmations" do
      time = Time.zone.now.change(usec: 0)
      @email.request_verification

      events = subscribe "user_email.confirm_verification"
      expected_payload = {
        state: "verified",
        note: @email.email,
        verified_at: time,
        email_id: @email.id,
        email: @email.email,
        user: @email.user.login,
        user_id: @email.user_id,
        actor: @email.user.login,
        actor_id: @email.user_id,
      }

      Timecop.freeze(time) do
        @email.confirm_verification(@email.verification_token)
      end

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end
  end

  context "#confirm_verification" do
    context "find_email_for_verification" do
      test "finds emails directly associated to owned_by" do
        email = UserEmail.find_email_for_verification(@email.id, owned_by: @user)
        assert_equal email, @email, "Expected to find #{@email.email} owned by #{@user}"
      end

      test "finds emails associated to an organization that is adminable by @user" do
        email = create(:user_email, user: @organization)
        found = UserEmail.find_email_for_verification(email.id, owned_by: @user)
        assert_equal email, found
      end

      test "returns nil for emails that exist but the owner isn't owned_by or an organization" do
        email = create :user_email
        assert_predicate UserEmail.find_email_for_verification(email.id, owned_by: @user), :nil?
      end

      test "returns nil for emails owned by an org that @user is not an admin of" do
        org = create(:organization)
        email = create(:user_email, user: org)

        assert_predicate UserEmail.find_email_for_verification(email.id, owned_by: @user), :nil?
      end
    end

    context "invalid attempts" do
      test "rejects nil tokens" do
        @email.confirm_verification(nil)
        assert !@email.verified?
      end

      test "rejects incorrect tokens" do
        @email.request_verification
        @email.confirm_verification("random-token")
        assert !@email.verified?
      end

      # Emails may no longer have a verification token
      # https://github.com/github/github/issues/89600
      test "rejects if email has no verification_token" do
        @email.request_verification
        token = @email.verification_token
        @email.clear_verification_token
        @email.save!
        assert !@email.confirm_verification(token)
        assert !@email.verified?
      end

      test "rejects if email launch code has expired" do
        @email.request_verification
        token = @email.verification_token
        Users::Kv.store.del(@email.kv_launch_code_key)
        assert_nil Users::Kv.store.get(@email.kv_launch_code_key).value!

        refute @email.confirm_verification(token)
        refute @email.verified?
      end
    end

    context "valid attempts" do
      test "returns true" do
        @email.request_verification
        assert @email.confirm_verification(@email.verification_token)
      end

      test "saves the email" do
        @email.request_verification
        @email.confirm_verification(@email.verification_token)
        assert @email.reload.verified?
      end

      test "verifies email" do
        @email.request_verification
        @email.confirm_verification(@email.verification_token)
        assert @email.verified?
      end

      test "clears verification token" do
        @email.request_verification
        refute_nil @email.reload.verification_token
        @email.confirm_verification(@email.verification_token)
        assert_nil @email.reload.verification_token
      end

      test "clears any bouncing roles, if they exist" do
        @email.request_verification
        @email.mark_as_bouncing!

        assert @email.bouncing?

        assert @email.confirm_verification(@email.verification_token)
        refute @email.reload.bouncing?, "email should no longer be bouncing"
      end

      test "sets the first verified email as the primary" do
        # i.e. an email created after the signup email
        second_email = create :user_email, user: @user
        refute second_email.primary?
        second_email.request_verification
        second_email.confirm_verification(second_email.verification_token)
        assert second_email.reload.primary?
      end

      test "only auto-primary's the first verified email" do
        @email.request_verification
        @email.confirm_verification(@email.verification_token)

        second_email = create :user_email, user: @user
        second_email.request_verification
        second_email.confirm_verification(second_email.verification_token)
        refute second_email.reload.primary?
      end

      test "schedules a sendgrid bounce removal" do
        @email.mark_as_bouncing!
        @email.request_verification

        if GitHub.sendgrid_enabled?
          assert_enqueued_with(job: SendgridSuppressionRemovalJob, args: [@email.id]) do
            @email.confirm_verification(@email.verification_token)
          end
        else
          SendgridSuppressionRemovalJob.expects(:perform_later).never
          @email.confirm_verification(@email.verification_token)
        end
      end

      if GitHub.mailchimp_enabled?
        context "when the user has a marketing email preference" do
          test "enqueues a mailchimp subscribe job for the first verified email" do
            NewsletterPreference.set_to_marketing(user: @user)

            @email.request_verification
            assert_enqueued_with job: MailchimpSubscribeJob, args: [@email.id] do
              @email.confirm_verification(@email.verification_token)
            end
          end

          test "only enqueues a mailchimp subscribe job for first verified email" do
            NewsletterPreference.set_to_marketing(user: @user)

            @email.request_verification
            assert_enqueued_with job: MailchimpSubscribeJob, args: [@email.id] do
              @email.confirm_verification(@email.verification_token)
            end
            assert @email.verified?
            assert @email.primary?

            second_email = create :user_email, user: @user
            second_email.request_verification

            assert_no_enqueued_jobs do
              second_email.confirm_verification(second_email.verification_token)
            end
          end

          test "doesn't enqueue an unsubscribe job for the first verified email" do
            NewsletterPreference.set_to_marketing(user: @user)

            @email.request_verification
            @email.confirm_verification(@email.verification_token)

            assert_enqueued_with job: MailchimpSubscribeJob, args: [@email.id]
            assert_no_enqueued_jobs only: MailchimpUnsubscribeJob
          end
        end

        context "when the user has a transactional email preference" do
          test "does not enqueue a mailchimp subscribe job for the first verified email" do
            NewsletterPreference.set_to_transactional(user: @user)

            @email.request_verification
            @email.confirm_verification(@email.verification_token)
            assert_no_enqueued_jobs only: MailchimpSubscribeJob
          end

          test "enqueues a signup confirmation job for the first verified email" do
            NewsletterPreference.set_to_transactional(user: @user)

            @email.request_verification
            @email.confirm_verification(@email.verification_token)
            assert_enqueued_jobs 1, only: UserSignupConfirmationJob
          end

          test "only enqueues a signup confirmation job for the first verified email" do
            NewsletterPreference.set_to_transactional(user: @user)

            @email.request_verification
            @email.confirm_verification(@email.verification_token)
            assert @email.verified?
            assert @email.primary?

            second_email = create :user_email, user: @user
            second_email.request_verification

            second_email.confirm_verification(second_email.verification_token)
            assert_enqueued_with job: UserSignupConfirmationJob, args: [@email.id]
          end
        end
      else
        test "does not enqueue a mailchimp subscribe job" do
          NewsletterPreference.set_to_marketing(user: @user)

          @email.request_verification
          @email.confirm_verification(@email.verification_token)
          assert_no_enqueued_jobs only: MailchimpSubscribeJob
        end

        test "does not enqueue a user-signup-confirmation job" do
          NewsletterPreference.set_to_transactional(user: @user)

          @email.request_verification
          @email.confirm_verification(@email.verification_token)
          assert_no_enqueued_jobs only: UserSignupConfirmationJob
        end
      end
    end
  end

  context "EMU email claiming", skip_enterprise: true do
    if GitHub.single_or_multi_tenant_enterprise?
      context "no op in GHES or MT" do
        test "request_claim" do
          user = create :emu
          email = user.emails.first

          assert_nil email.verification_token

          EnterpriseManagedUserMailer.expects(:confirm_claim_email).never

          UserEmail.any_instance.expects(:save).never

          refute email.request_claim(requested_by: user)

          assert_nil email.reload.verification_token
        end

        test "cancel_claim_request" do
          user = create :emu
          email = user.emails.first

          email.update_attribute!(:verification_token, "token")
          refute_nil email.reload.verification_token

          UserEmail.any_instance.expects(:save).never

          refute email.cancel_claim_request(canceler: user)

          refute_nil email.reload.verification_token
        end

        test "confirm_claim" do
          emu = create :emu
          email = emu.emails.first

          verification_token = SecureRandom.hex(8)

          email.update!(verification_token: verification_token)

          assert emu.is_enterprise_managed?
          refute_nil email.verification_token
          assert SecurityUtils.secure_compare(email.verification_token, verification_token)

          UserEmail.any_instance.expects(:save).never

          refute email.confirm_claim(claimer: emu, token: verification_token)

          refute email.reload.claimed?
          refute_nil email.verification_token
        end

        test "mark_as_unclaimed" do
          emu = create :emu
          email = emu.emails.first

          email.update!(claimed: true)

          assert email.reload.claimed?
          assert emu.is_enterprise_managed?

          UserEmail.any_instance.expects(:save).never

          refute email.mark_as_unclaimed(unclaimer: emu)
          assert email.reload.claimed?
        end
      end
    else
      context "#request_claim" do
        test "false if no user is provided" do
          refute @email.request_claim(requested_by: nil)
        end

        test "false if user is not an emu" do
          user = create :user
          email = user.emails.first

          refute email.request_claim(requested_by: user)
        end

        test "false if the emu requesting is not the user that owns the email" do
          emu_one = create :emu
          emu_two = create :emu

          email_two = emu_two.emails.first

          refute email_two.request_claim(requested_by: emu_one)
        end

        test "false if email already exists and is claimed by another emu" do
          emu_one = create :emu, email: "emu@github.com"
          emu_two = create :emu, email: "emu@github.com"

          email_one = emu_one.emails.first
          email_two = emu_two.emails.first

          email_one.update_attribute(:claimed, true)

          refute email_two.request_claim(requested_by: emu_one)
        end

        test "false if email already exists on a normal dotcom user" do
          emu_one = create :emu, email: "foobar@github.com"

          email_one = emu_one.emails.first

          create :user, email: "foobar@github.com"

          refute email_one.request_claim(requested_by: emu_one)
        end

        test "false if email is already taken by the user requesting it" do
          emu = create :emu
          email = emu.emails.first

          email.update!(claimed: true)

          assert_predicate email, :claimed?

          refute email.request_claim(requested_by: emu)
        end

        test "false if unable to save email after generating token" do
          emu = create :emu
          email = emu.emails.first

          refute_predicate email, :claimed?

          UserEmail.any_instance.stubs(:save).returns(false)

          refute email.request_claim(requested_by: emu)
        end

        test "returns true, sets token, and sends email on success" do
          user = create :emu
          email = user.emails.first

          assert_nil email.verification_token

          EnterpriseManagedUserMailer.expects(:confirm_claim_email).with(user, email).once.returns(stub(deliver_later: nil))

          assert email.request_claim(requested_by: user)

          refute_nil email.reload.verification_token
        end
      end

      context "#cancel_claim_request" do
        test "false if no user is provided" do
          refute @email.cancel_claim_request(canceler: nil)
        end

        test "false if user is not an emu" do
          user = create :user
          email = user.emails.first

          refute email.cancel_claim_request(canceler: user)
        end

        test "false if the emu requesting is not the user that owns the email" do
          emu_one = create :emu
          emu_two = create :emu

          email_two = emu_two.emails.first

          refute email_two.cancel_claim_request(canceler: emu_one)
        end

        test "false if the email is already claimed by the user" do
          emu = create :emu
          email = emu.emails.first

          email.update_attribute(:claimed, true)

          refute email.cancel_claim_request(canceler: emu)
        end

        test "false if the save fails" do
          emu = create :emu
          email = emu.emails.first

          refute_predicate email, :claimed?

          UserEmail.any_instance.stubs(:save).returns(false)

          refute email.cancel_claim_request(canceler: emu)
        end

        test "returns true and removes the verification token otherwise" do
          emu = create :emu
          email = emu.emails.first

          refute_predicate email, :claimed?

          email.update_attribute(:verification_token, "token")

          refute_nil email.reload.verification_token

          assert email.cancel_claim_request(canceler: emu)

          assert_nil email.reload.verification_token
        end

        test "canceling when no verification token is set is a successful no-op" do
          emu = create :emu
          email = emu.emails.first

          refute_predicate email, :claimed?
          assert_nil email.verification_token

          assert email.cancel_claim_request(canceler: emu)

          assert_nil email.reload.verification_token
        end
      end

      context "#confirm_claim" do
        test "false if no user is provided" do
          refute @email.confirm_claim(claimer: nil, token: nil)
        end

        test "false if the claimer is not the user that owns the email" do
          user = create :user
          refute_equal @email.user, user
          refute @email.confirm_claim(claimer: user, token: nil)
        end

        test "false if no token is provided" do
          emu = create :emu
          email = emu.emails.first

          assert emu.is_enterprise_managed?

          refute email.confirm_claim(claimer: emu, token: nil)
        end

        test "false if no verification token is set" do
          emu = create :emu
          email = emu.emails.first

          assert emu.is_enterprise_managed?
          assert_nil email.verification_token

          refute email.confirm_claim(claimer: emu, token: "token")
        end

        test "false if the claimer is not an EMU" do
          @email.update!(verification_token: "token")
          refute @email.user.is_enterprise_managed?
          refute @email.confirm_claim(claimer: @email.user, token: "token")
          assert_equal "Email cannot be verified by users who are not enterprise managed", @email.errors.full_messages.to_sentence
        end

        test "false if the verification token and token don't match" do
          emu = create :emu
          email = emu.emails.first

          verification_token = SecureRandom.hex(8)
          token = "token"

          email.update!(verification_token: verification_token)

          assert emu.is_enterprise_managed?
          refute_nil email.verification_token
          refute SecurityUtils.secure_compare(email.verification_token, token)

          refute email.confirm_claim(claimer: emu, token: token)
        end

        test "false if the email was already claimed" do
          emu = create :emu
          email = emu.emails.first

          # make a duplicate email
          @user.emails.first.update_attribute(:email, email.deobfuscated_email)

          verification_token = SecureRandom.hex(8)
          email.update_attribute(:verification_token, verification_token)

          refute email.claimed?

          assert emu.is_enterprise_managed?
          refute_nil email.verification_token

          refute email.confirm_claim(claimer: emu, token: verification_token)
        end

        test "false if the email cannot be saved" do
          emu = create :emu
          email = emu.emails.first

          verification_token = SecureRandom.hex(8)

          email.update!(verification_token: verification_token)

          assert emu.is_enterprise_managed?
          refute_nil email.verification_token
          assert SecurityUtils.secure_compare(email.verification_token, verification_token)

          UserEmail.any_instance.stubs(:save).returns(false)

          refute email.confirm_claim(claimer: emu, token: verification_token)
        end

        test "true if the email was saved" do
          emu = create :emu
          email = emu.emails.first

          verification_token = SecureRandom.hex(8)

          email.update!(verification_token: verification_token)

          assert emu.is_enterprise_managed?
          refute_nil email.verification_token
          assert SecurityUtils.secure_compare(email.verification_token, verification_token)

          assert email.confirm_claim(claimer: emu, token: verification_token)

          assert email.reload.claimed?
          assert_nil email.verification_token
        end

        test "instruments the claim" do
          events = subscribe("user_email.confirm_claim")

          emu = create :emu
          email = emu.emails.first

          verification_token = SecureRandom.hex(8)

          email.update!(verification_token: verification_token)

          assert email.confirm_claim(claimer: emu, token: verification_token)

          expected_payload = {
            state: email.state,
            note: email.email,
            email: email.email,
            email_id: email.id,
            user: emu.login,
            user_id: emu.id,
            actor: emu.login,
            actor_id: emu.id,
          }

          assert event = events.pop
          assert_equal expected_payload, event.payload
        end
      end

      context "#mark_as_unclaimed" do
        test "false if no user is provided" do
          refute @email.mark_as_unclaimed(unclaimer: nil)
        end

        test "false if unclaimer doesn't own the email" do
          user = create :user
          refute_equal @email.user, user
          refute @email.mark_as_unclaimed(unclaimer: user)
        end

        test "false if unclaimer is not an EMU" do
          refute @email.user.is_enterprise_managed?
          @email.update_attribute(:claimed, true)
          assert @email.reload.claimed?
          refute @email.mark_as_unclaimed(unclaimer: @user)
        end

        test "false if save fails for other reasons" do
          emu = create :emu
          email = emu.emails.first

          email.update_attribute(:claimed, true)

          assert email.reload.claimed?
          assert emu.is_enterprise_managed?

          UserEmail.any_instance.stubs(:save).returns(false)

          refute email.mark_as_unclaimed(unclaimer: emu)
          assert email.reload.claimed?
        end

        test "true if save succeeds" do
          emu = create :emu
          email = emu.emails.first

          email.update!(claimed: true)

          assert email.reload.claimed?
          assert emu.is_enterprise_managed?

          assert email.mark_as_unclaimed(unclaimer: emu)
          refute email.reload.claimed?
        end

        test "instruments the unclaim" do
          events = subscribe("user_email.mark_as_unclaimed")

          emu = create :emu
          email = emu.emails.first
          email.update!(claimed: true)

          assert email.reload.claimed?
          assert emu.is_enterprise_managed?

          assert email.mark_as_unclaimed(unclaimer: emu)

          expected_payload = {
            state: email.state,
            note: email.email,
            email: email.email,
            email_id: email.id,
            user: emu.login,
            user_id: emu.id,
            actor: emu.login,
            actor_id: emu.id,
          }

          assert event = events.pop
          assert_equal expected_payload, event.payload
        end
      end
    end
  end

  context "#verify!" do
    test "sets the verified_at timestamp" do
      assert_nil @email.verified_at
      @email.verify!
      refute_nil @email.verified_at
    end

    if GitHub.billing_enabled?
      test "links any non-revoked bundled license assignments for related businesses to the user" do
        bundled_license_assignment = create(:licensing_bundled_license_assignment, email: @email.email, user: nil, revoked: false)
        _other_email_bundled_license_assignment = create(:licensing_bundled_license_assignment, email: "something-else@example.com", user: nil, revoked: false)

        assert_enqueued_with job: Licensing::SetUserFromBusinessOnBundledLicenseAssignmentJob, args: [{ assignment: bundled_license_assignment }] do
          @email.verify!
        end

        assert_enqueued_jobs 1, only: Licensing::SetUserFromBusinessOnBundledLicenseAssignmentJob
      end

      test "links bundled license assignments based on email with removed shortcode" do
        user = create :emu, email: "freeuser@github.com"
        email = user.emails.first

        bundled_license_assignment = create(:licensing_bundled_license_assignment, email: "freeuser@github.com", user: nil, revoked: false)
        _other_email_bundled_license_assignment = create(:licensing_bundled_license_assignment, email: "something-else@example.com", user: nil, revoked: false)

        assert_enqueued_with job: Licensing::SetUserFromBusinessOnBundledLicenseAssignmentJob, args: [{ assignment: bundled_license_assignment }] do
          email.verify!
        end

        assert_enqueued_jobs 1, only: Licensing::SetUserFromBusinessOnBundledLicenseAssignmentJob
      end
    else
      test "does not attempt to link any bundled license assignments" do
        _bundled_license_assignment = create(:licensing_bundled_license_assignment, email: @email.email, user: nil, revoked: false)

        assert_no_enqueued_jobs only: Licensing::SetUserFromBusinessOnBundledLicenseAssignmentJob do
          @email.verify!
        end
      end
    end
  end

  context "#unverify!" do
    test "unsets the verified_at timestamp" do
      @email.verify!
      refute_nil @email.verified_at

      @email.unverify!
      assert_nil @email.verified_at
    end

    test "enterprise managed user email cannot be unverified", skip_enterprise: true do
      business = create :business, :enterprise_managed
      user = create :emu, business: business
      email = user.emails.first

      email.verify!
      refute_nil email.verified_at

      email.unverify!
      refute_nil email.verified_at
    end
  end

  context "#mark_as_verified" do
    test "sets the state to verified" do
      @email.state = "unverified"
      @email.mark_as_verified
      assert_equal "verified", @email.state
    end

    test "sets the verified_at timestamp" do
      assert_nil @email.verified_at
      @email.mark_as_verified
      refute_nil @email.verified_at
    end
  end

  context "#toggle_visibility" do
    test "makes primary email 'private'" do
      @user.primary_user_email.toggle_visibility
      assert @user.primary_user_email.private?
    end

    test "setting to private adds the stealth email" do
      @user.primary_user_email.toggle_visibility
      assert_equal 2, @user.emails.size

      assert @user.emails.detect { |e| e.role?("stealth") }
    end

    test "setting to private, then back to public, does not destroy the stealth email" do
      @user.primary_user_email.toggle_visibility
      @user.primary_user_email.toggle_visibility
      @user.reload
      assert @user.primary_user_email.public?
      assert_equal 2, @user.emails.size
      assert_equal 1,  @user.emails.to_a.count { |e| e.role?("stealth") }
    end

    test "setting an email to public with an old style stealth email destroys the old stealth email" do
      @user.primary_user_email.toggle_visibility
      @user.emails.select { |e| e.role?("stealth") }.each { |e| e.update_attribute(:email, "#{@user.login}@#{GitHub.stealth_email_host_name}") }
      @user.reload
      assert @user.primary_user_email.private?
      assert_equal 2, @user.emails.size
      @user.primary_user_email.toggle_visibility
      @user.reload
      assert_equal 0,  @user.emails.to_a.count { |e| e.role?("stealth") }
    end

    test "setting an email to public sends the correct datadog data" do
      GitHub.dogstats.expects(:increment).at_least_once
      GitHub.dogstats.expects(:increment).with("user.email.privacy.visibility_toggle.on").at_least_once
      @user.primary_user_email.toggle_visibility
    end

    test "setting an email to private sends the correct datadog data" do
      @user.primary_user_email.toggle_visibility
      GitHub.dogstats.expects(:increment).at_least_once
      GitHub.dogstats.expects(:increment).with("user.email.privacy.visibility_toggle.off").at_least_once
      @user.primary_user_email.toggle_visibility
    end

    test "setting an email to private with a profile email removes the profile email" do
      assert_equal @user.profile.email, "profile-email@example.com"
      @user.primary_user_email.toggle_visibility
      @user.profile.reload
      assert_nil @user.profile.email
    end

    test "instruments hiding event" do
      events = subscribe("user_email.toggle_visibility")

      email = @user.primary_user_email

      expected_payload = {
        state: email.state,
        note: email.email,
        email: email.email,
        email_id: email.id,
        visibility: "hidden",
        user: @user.login,
        user_id: @user.id,
        actor: @user.login,
        actor_id: @user.id,
      }

      @user.primary_user_email.toggle_visibility

      assert event = events.pop
      assert_equal expected_payload, event.payload
    end

    test "instruments unhiding event" do
      email = @user.primary_user_email

      expected_payload = {
        state: email.state,
        note: email.email,
        email: email.email,
        email_id: email.id,
        visibility: "visible",
        user: @user.login,
        user_id: @user.id,
        actor: @user.login,
        actor_id: @user.id,
      }

      @user.primary_user_email.toggle_visibility
      events = subscribe("user_email.toggle_visibility")
      @user.primary_user_email.toggle_visibility

      assert event = events.pop
      assert_equal expected_payload, event.payload
    end
  end

  context "deobfuscating email addresses" do
    context "UserEmail.deobfuscate" do
      test "strips dots" do
        assert_equal "test@example.com", UserEmail.deobfuscate("te.s.t.@example.com")
      end

      test "handles +" do
        assert_equal "test@example.com", UserEmail.deobfuscate("te.s.t+foo@example.com")
      end

      test "handles empty email" do
        assert_equal "", UserEmail.deobfuscate("")
      end

      test "does not choke on nil" do
        assert_equal "", UserEmail.deobfuscate(nil)
      end

      test "does not choke with no domain" do
        assert_equal "test", UserEmail.deobfuscate("test@")
      end

      test "does not choke with no domain part" do
        assert_equal "test", UserEmail.deobfuscate("test")
      end

      test "does not choke with no user part" do
        assert_equal "@example.com", UserEmail.deobfuscate("@example.com")
      end
    end
  end

  context ".generic_domain?" do
    test "returns true for various generic domains" do
      domains = %w(fake laptop.none example.com me.test.net localhost local.host
                   local laptop.local)
      domains.each do |domain|
        email = "user@#{domain}"
        assert UserEmail.generic_domain?(email), "#{email} failed to test as a generic domain"
      end
    end if GitHub.email_detect_generic_domains?

    test "returns false for non-generic domains" do
      assert !UserEmail.generic_domain?("tekkub@github.com")
    end

    test "returns false if generic domain detection is disabled" do
      GitHub.stubs(:email_detect_generic_domains?).returns(false)
      %w(test@example.local tekkub@github.com).each do |email|
        refute UserEmail.generic_domain?(email)
      end
    end
  end

  context "publicly_visible_email" do

    if GitHub.enterprise?
      test "returns the profile email for Enterprise users" do
        assert_equal "profile-email@example.com", @user.publicly_visible_email(logged_in: false)
      end
    else
      test "returns nil for logged out users" do
        assert_nil @user.publicly_visible_email(logged_in: false)
      end
    end

    test "returns the profile email for logged in user" do
      assert_equal "profile-email@example.com", @user.publicly_visible_email(logged_in: true)
    end

    test "does not return email based on preference even when viewer is logged in" do
      @user.primary_user_email.toggle_visibility
      assert_nil @user.publicly_visible_email(logged_in: true)
    end

    test "returns nil when the user doesn't have a profile email" do
      user = create :user, email: "user@example.com"
      assert_nil user.publicly_visible_email(logged_in: true)
    end

    test "returns nil when the user has a blank profile email" do
      user = create :user, email: "user@example.com"
      user.profile = create :profile, email: ""
      assert_nil user.publicly_visible_email(logged_in: true)
    end

    test "returns the email for organizations" do
      org = create(:organization)
      org.profile = create :profile, email: "org@example.com"
      assert_equal "org@example.com", org.publicly_visible_email(logged_in: true)
    end

    test "returns nil when the organization has a blank profile email" do
      org = create(:organization)
      org.profile = create :profile, email: ""
      assert_nil org.publicly_visible_email(logged_in: true)
    end

    test "does not require log in for organization emails" do
      org = create(:organization)
      org.profile = create :profile, email: "org@example.com"
      assert_equal "org@example.com", org.publicly_visible_email(logged_in: false)
    end
  end

  context "#launch_code_verification?" do
    test "returns true for token that is length of launch code" do
      refute_predicate @email, :launch_code_verification?
      @email.update!(verification_token: "1" * UserEmail::LAUNCH_CODE_LENGTH)
      assert_predicate @email, :launch_code_verification?
    end

    test "returns false for traditional token" do
      refute_predicate @email, :launch_code_verification?
    end

    test "returns false if verification_token is nil" do
      @email.update!(verification_token: nil)
      refute_predicate @email, :launch_code_verification?
    end

    test "returns false for bouncing emails" do
      @email.mark_as_bouncing!
      refute_predicate @email, :launch_code_verification?
    end

    test "returns false for non-primary emails" do
      @email2 = @user.emails.create!(email: "second@example.com")

      refute_predicate @email2, :launch_code_verification?
    end

    test "returns false for orgs" do
      @email.user = @organization
      refute_predicate @email, :launch_code_verification?
    end
  end
end

class UserEmailAndEmailRolesTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @email1 = @user.emails.first
    @email2 = @user.emails.create!(email: "second@example.com")
  end

  test "primary emails are primary and primary_role (legacy vs new emails)" do
    assert_includes @email1.email_roles.map(&:role), "primary"
    assert_equal true, @email1.primary?
    assert_equal true, @email1.primary_role?
  end

  test "backups emails are backup_role" do
    @email2.verify!
    @user.set_backup_email(@email2)
    assert_includes @email2.email_roles.map(&:role), "backup"
    assert_equal true, @email2.backup_role?
  end

  test "an email can test its role" do
    assert @email1.role?("primary")
    assert !@email1.role?("stealth")
  end

  test "destroying UserEmail also destroys any associated EmailRoles" do
    # Need to have a verified email to fall back to
    @email2.verify!

    assert @email1.destroy
    assert_equal [], EmailRole.where(email_id: @email1.id)
  end

  test "can get single email with role" do
    assert_equal @email1, @user.emails.with_role("primary")
    assert_nil @user.emails.with_role("dont-exist")
  end

  context "#repair_primary_email" do
    test "fails gracefully if primary email already set" do
      result = @user.repair_primary_email
      refute result
    end

    test "fails gracefully if user has no emails" do
      @email1.delete
      @email2.delete
      assert @user.reload.emails.empty?

      result = @user.repair_primary_email
      refute result
    end

    test "sets the primary email" do
      @email1.email_roles.primary.first.delete
      refute @user.reload.has_primary_email?

      result = @user.repair_primary_email
      assert result
      assert @user.reload.has_primary_email?
    end
  end

  test "non-primary emails are always private" do
    assert_predicate @email2, :private?
    refute_predicate @email2, :public?
  end

  context "normalized_domain" do
    test "creating a new email saves the normalized domain" do
      email = @user.add_email "peppermint-sombra@example.com"
      assert_equal "example.com", email.normalized_domain
    end

    test "normalized domain includes the email subdomain" do
      email = @user.add_email "peppermint-sombra@opensource.example.com"
      assert_equal "opensource.example.com", email.normalized_domain
    end

    test "works with invalid email address" do
      email = @user.add_email "peppermint-sombra@opensource.local"
      assert_equal "opensource.local", email.normalized_domain
    end
  end

  context "#process_email_domain_for_reputation_data" do
    test "calls EmailDomainReputationRecord.process_later with normalized_domain when record is created" do
      EmailDomainReputationRecord.expects(:process_later).with("foo.com")
      create(:user_email, user: @user, email: "hello@foo.com")
    end

    test "calls EmailDomainReputationRecord.process_later with normalized_domain when record is destroyed" do
      email = create(:user_email, user: @user, email: "hello@foo.com")
      EmailDomainReputationRecord.expects(:process_later).with("foo.com")
      email.destroy
    end
  end
end

if GitHub.spamminess_check_enabled?
  class SpammableTest < GitHub::TestCase
    fixtures do
      @user = create(:user)
      @email = @user.emails.first
    end

    test "considered spammy if owner is spammy" do
      assert !@email.user.spammy?
      assert !@email.spammy?

      perform_enqueued_jobs(only: UpdateTableUserHiddenJob) do
        @email.user.mark_as_spammy
      end
      assert @email.reload.spammy?
    end
  end
end

class UserEmailWithoutGravatarEmailTest < GitHub::TestCase
  setup do
    GitHub.auth_mode = :ldap
    @external_user = create(:external_auth_user)
    @normal_user   = create(:user)
  end

  test "initial gravatar state for external_auth'ed users" do
    assert_nil @external_user.gravatar_email
  end

  test "set the gravatar email when the primary email is set" do
    @external_user.add_email("foo@example.com")
    assert_equal "foo@example.com", @external_user.gravatar_email
  end

  test "don't set the gravatar email on primary email change if more than one email exists" do
    @external_user.add_email("foo@example.com")
    @external_user.add_email("bar@example.com", is_primary: true)
    assert_equal 2, @external_user.emails.size
    assert_equal "bar@example.com", @external_user.email
    assert_equal "foo@example.com", @external_user.gravatar_email
  end

  test "keep the same gravatar email set on registration" do
    @normal_user.add_email("foo@example.com", is_primary: true)
    refute_equal "foo@example.com", @external_user.gravatar_email
  end
end

class BelongsToABotTest < GitHub::TestCase
  test "returns true if the email contains Bot login suffix and stealth domain" do
    email = "super-ci[bot]@users.noreply.github.com"
    assert UserEmail.belongs_to_a_bot?(email)
  end

  test "returns false if the email does not contain Bot login suffix" do
    email = "super-ci@users.noreply.github.com"
    refute UserEmail.belongs_to_a_bot?(email)
  end

  test "returns false if the email does not contain the stealth domain" do
    email = "super-ci[bot]@example.com"
    refute UserEmail.belongs_to_a_bot?(email)
  end
end
