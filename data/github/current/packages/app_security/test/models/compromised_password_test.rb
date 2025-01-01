# typed: true
# frozen_string_literal: true

require "test_helper"

class CompromisedPasswordTest < GitHub::TestCase
  fixtures do
    @compromised_password_datasource = create(:compromised_password_datasource, name: "HAVE_I_BEEN_PWNED", version: "5")
    @compromised_password = create(:compromised_password, plain: COMPROMISED_USER_PASSWORD)
    @user = create(:user)
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  def compromised_password_tags(options)
    {
      compromised: "true",
      action: "unknown",
      employee: "false",
      spammy: "false",
      tfa_enabled: "false",
      correct_password: "true",
      valid_user: "true",
      block_type: "false",
    }.merge(options).map do |k, v|
      "#{k}:#{v}"
    end
  end

  test "compromised_password is readonly" do
    compromised_password = create(:compromised_password, plain: "readonly")
    assert_raises ActiveRecord::ReadOnlyRecord do
      compromised_password.update(sha1_password: Digest::SHA1.hexdigest("test").upcase) # rubocop:disable GitHub/InsecureHashAlgorithm
    end
  end

  test "COMPROMISED_USER_PASSWORD is found", skip_enterprise: !GitHub.weak_password_checking_enabled? do
    assert CompromisedPassword.find_using_password(COMPROMISED_USER_PASSWORD)
  end

  test "COMPROMISED_USER_PASSWORD_K_ANON is not found", skip_enterprise: !GitHub.weak_password_checking_enabled? do
    assert !CompromisedPassword.find_using_password(COMPROMISED_USER_PASSWORD_K_ANON)
  end

  test "some other password not inserted is not found", skip_enterprise: !GitHub.weak_password_checking_enabled? do
    assert !CompromisedPassword.find_using_password("good_password")
  end

  test "sha1 comparison is case insensitive", skip_enterprise: !GitHub.weak_password_checking_enabled? do
    plain = "mixed_case_sha"
    digest = Digest::SHA1.hexdigest(plain) # rubocop:disable GitHub/InsecureHashAlgorithm

    mixed_case = [
      digest[0...20]&.upcase,
      digest[20...40]&.downcase,
    ].join

    CompromisedPassword.create!(sha1_password: mixed_case)

    assert CompromisedPassword.find_using_password(plain)
  end

  test "stats employee status", skip_enterprise: !GitHub.weak_password_checking_enabled? do
    employee = create(:staff_admin_user)
    CompromisedPassword.find_using_password(COMPROMISED_USER_PASSWORD, user: employee)
    assert_equal 1, GitHub.dogstats.increments("auth.compromised_password", tags: compromised_password_tags(employee: true)).length
  end

  test "stats spammy status", skip_enterprise: !GitHub.weak_password_checking_enabled? do
    @user.mark_as_spammy
    CompromisedPassword.find_using_password(COMPROMISED_USER_PASSWORD, user: @user)
    assert_equal 1, GitHub.dogstats.increments("auth.compromised_password", tags: compromised_password_tags(spammy: true)).length
  end

  test "stats 2fa status", skip_enterprise: !GitHub.weak_password_checking_enabled? do
    make_two_factor_credential(@user)
    CompromisedPassword.find_using_password(COMPROMISED_USER_PASSWORD, user: @user)
    assert_equal 1, GitHub.dogstats.increments("auth.compromised_password", tags: compromised_password_tags(tfa_enabled: true)).length
  end

  test "stats correct password status", skip_enterprise: !GitHub.weak_password_checking_enabled? do
    CompromisedPassword.find_using_password(COMPROMISED_USER_PASSWORD, user: @user, correct_password: false)
    assert_equal 1, GitHub.dogstats.increments("auth.compromised_password", tags: compromised_password_tags(correct_password: false)).length
  end

  test "stats nil user", skip_enterprise: !GitHub.weak_password_checking_enabled? do
    CompromisedPassword.find_using_password(COMPROMISED_USER_PASSWORD, user: nil)
    assert_equal 1, GitHub.dogstats.increments("auth.compromised_password", tags: compromised_password_tags(valid_user: false, spammy: nil, tfa_enabled: nil, employee: nil, block_type: nil)).length
  end

  test "stats 30 days blocked user", skip_enterprise: !GitHub.weak_password_checking_enabled? do
    metadata = build(:password_check_metadata_with_blocking_timestamp)
    @user.update_attribute(:weak_password_check_result, metadata.to_binary_s)
    CompromisedPassword.find_using_password(COMPROMISED_USER_PASSWORD, user: @user)
    assert_equal 1, GitHub.dogstats.increments("auth.compromised_password", tags: compromised_password_tags(block_type: "30_days")).length
  end

  test "stats exact match blocked user", skip_enterprise: !GitHub.weak_password_checking_enabled? do
    metadata = build(:password_check_metadata_exact_match)
    @user.update_attribute(:weak_password_check_result, metadata.to_binary_s)
    CompromisedPassword.find_using_password(COMPROMISED_USER_PASSWORD, user: @user)
    assert_equal 1, GitHub.dogstats.increments("auth.compromised_password", tags: compromised_password_tags(block_type: "exact_match")).length
  end

  test "doesn't stat when told not to", skip_enterprise: !GitHub.weak_password_checking_enabled? do
    metadata = build(:password_check_metadata_exact_match)
    @user.update_attribute(:weak_password_check_result, metadata.to_binary_s)
    CompromisedPassword.find_using_password(COMPROMISED_USER_PASSWORD, user: @user, stat: false)
    assert_equal 0, GitHub.dogstats.increments("auth.compromised_password").length
  end
end
