# typed: true
# frozen_string_literal: true

require "test_helper"

class DisposableEmailsTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @real_email = create :user_email, user: @user, email: "#{@user.login}@github.invalid"
    @disposable_email = build :user_email, user: @user, email: "#{@user.login}@mailinator.com"
    @disposable_email.save(validate: false)
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  context "#disposable?" do
    test "valid emails are not disposable" do
      refute_predicate @real_email, :disposable?
    end

    test "disposable emails are disposable when GitHub.prevent_disposable_email_verification is enabled" do
      GitHub.stubs(prevent_disposable_email_verification?: true)
      assert_predicate @disposable_email, :disposable?
    end

    test "disposable emails are not disposable when GitHub.prevent_disposable_email_verification is disabled" do
      GitHub.stubs(prevent_disposable_email_verification?: false)
      refute_predicate @disposable_email, :disposable?
    end
  end

  context "self.disposable_email?" do
    test "valid emails are not disposable" do
      refute UserEmail::DisposableEmailsDependency.disposable_email?("user@github.invalid")
    end

    test "disposable emails are disposable when GitHub.prevent_disposable_email_verification is enabled" do
      GitHub.stubs(prevent_disposable_email_verification?: true)
      assert UserEmail::DisposableEmailsDependency.disposable_email?("user@mailinator.com")
    end

    test "disposable emails are not disposable when GitHub.prevent_disposable_email_verification is disabled" do
      GitHub.stubs(prevent_disposable_email_verification?: false)
      refute UserEmail::DisposableEmailsDependency.disposable_email?("user@mailinator.com")
    end
  end

  context "#try_to_verify?" do
    test "disposable emails should not be verified when GitHub.prevent_disposable_email_verification is enabled" do
      GitHub.stubs(prevent_disposable_email_verification?: true)
      refute_predicate @disposable_email, :try_to_verify?
    end

    test "disposable emails should be verified when GitHub.prevent_disposable_email_verification is disabled" do
      GitHub.stubs(prevent_disposable_email_verification?: false)
      assert_predicate @disposable_email, :try_to_verify?
    end

    test "emails without a domain should not be verified" do
      @real_email.email = "definitelynotvalid"
      # in production these are legacy records, not sure how else to replicate that behavior
      @real_email.save(validate: false)
      assert_nil @real_email.domain

      refute_predicate @real_email, :try_to_verify?
    end

    test "real emails should be verified" do
      assert_predicate @real_email, :try_to_verify?
    end
  end

  test "cannot request verification for disposable emails when GitHub.prevent_disposable_email_verification is enabled" do
    GitHub.stubs(prevent_disposable_email_verification?: true)
    refute @disposable_email.request_verification
  end

  test "can request verification for disposable emails when GitHub.prevent_disposable_email_verification is disabled" do
    GitHub.stubs(prevent_disposable_email_verification?: false)
    assert @disposable_email.request_verification
  end

  context "validation for existing emails" do
    test "unverified disposable emails are valid" do
      assert_predicate @disposable_email, :valid?
    end

    test "disposable emails cannot be verified when GitHub.prevent_disposable_email_verification is enabled" do
      GitHub.stubs(prevent_disposable_email_verification?: true)
      @disposable_email.state = "verified"
      refute_predicate @disposable_email, :valid?
      msg = @disposable_email.errors.full_messages.to_sentence
      assert_equal "Email has a domain that cannot be verified", msg
    end

    test "disposable emails can be verified when GitHub.prevent_disposable_email_verification is disabled" do
      GitHub.stubs(prevent_disposable_email_verification?: false)
      @disposable_email.state = "verified"
      assert_predicate @disposable_email, :valid?
    end

    test "already verified disposable emails are valid" do
      @disposable_email.update_attribute :state, "verified"
      assert_predicate @disposable_email, :valid?
    end

    test "disposable emails can be added" do
      assert @user.add_email "#{@user.login}2@mailinator.com"
      assert_includes @user.emails.map(&:email), "#{@user.login}@mailinator.com"
      assert_includes @user.emails.map(&:email), "#{@user.login}2@mailinator.com"
    end
  end

  context "validation for new emails" do
    test "new disposable emails are invalid when GitHub.prevent_disposable_email_verification is enabled" do
      GitHub.stubs(prevent_disposable_email_verification?: true)
      new_user = create(:user)
      new_disposable_email = build(:user_email, user: new_user, email: "#{new_user.login}@mailinator.com")
      refute_predicate new_disposable_email, :valid?
    end

    test "new disposable emails are valid when GitHub.prevent_disposable_email_verification is disabled" do
      GitHub.stubs(prevent_disposable_email_verification?: false)
      new_user = create(:user)
      new_disposable_email = build(:user_email, user: new_user, email: "#{new_user.login}@mailinator.com")
      assert_predicate new_disposable_email, :valid?
    end

    test "new disposable emails cannot be created when GitHub.prevent_disposable_email_verification is enabled" do
      GitHub.stubs(prevent_disposable_email_verification?: true)
      new_user = create(:user)
      new_disposable_email = build(:user_email, user: new_user, email: "#{new_user.login}@mailinator.com")
      new_disposable_email.save
      msg = new_disposable_email.errors.full_messages.to_sentence
      assert_equal "Email domain could not be verified", msg
    end

    test "new disposable emails can be created when GitHub.prevent_disposable_email_verification is disabled" do
      GitHub.stubs(prevent_disposable_email_verification?: false)
      new_user = create(:user)
      new_disposable_email = build(:user_email, user: new_user, email: "#{new_user.login}@mailinator.com")
      new_disposable_email.save
      assert_empty new_disposable_email.errors
    end
  end

  context "stats" do
    test "records stats on create when GitHub.prevent_disposable_email_verification is enabled" do
      GitHub.stubs(prevent_disposable_email_verification?: true)
      user_email = UserEmail.new user: @user, email: "#{@user.login}+stats@mailinator.com"
      user_email.save(validate: false)
      stat = GitHub.dogstats.operations.find { |operation| operation.stat == "user_email.disposable.created" }
      assert stat, "Expected a user_email.disposable.created stat to have been set"
      assert_equal ["domain:mailinator.com"].to_set, stat.tags
    end

    test "does not record stats on create when GitHub.prevent_disposable_email_verification is disabled" do
      GitHub.stubs(prevent_disposable_email_verification?: false)
      UserEmail.create user: @user, email: "#{@user.login}+stats@mailinator.com"
      stat = GitHub.dogstats.operations.find { |operation| operation.stat == "user_email.disposable.created" }
      refute stat, "Expected a user_email.disposable.created stat to not have been set"
    end

    test "doesn't record for non-disposable emails" do
      UserEmail.create user: @user, email: "#{@user.login}+stats@github.invalid"
      stat = GitHub.dogstats.operations.find { |operation| operation.stat == "user_email.disposable.created" }
      refute stat, "Expected a user_email.disposable.created stat to not have been set"
    end
  end
end
