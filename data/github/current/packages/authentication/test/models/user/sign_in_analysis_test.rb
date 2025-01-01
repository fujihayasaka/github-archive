# typed: true
# frozen_string_literal: true

require "test_helper"

class SignInAnalysisTest < GitHub::TestCase
  fixtures do
    @user = create(:user)

    @verified_device = create(:verified_authenticated_device, user: @user)
    @verified_authentication_record = create(:authentication_record, user: @user, authenticated_device: @verified_device, client: :web)
    @known_device = create(:authenticated_device, user: @user)
    @known_authentication_record = create(:authentication_record, user: @user, authenticated_device: @known_device, client: :web)
  end

  def new_device
    create(:authenticated_device, user: @user)
  end

  def assert_verification(result, device, ip_address, octolytics_id)
    assert_equal result, @user.sign_in_verification_method(device, ip_address, octolytics_id)
  end

  def refute_verification(result, device, ip_address, octolytics_id)
    refute_equal result, @user.sign_in_verification_method(device, ip_address, octolytics_id)
  end

  test "recognizes verified devices" do
    assert_verification :verified_device, @verified_device, Faker::Internet.ip_v4_address, Analytics::Visitor.create.octolytics_id
  end

  test "recognizes two factor users" do
    make_two_factor_credential(@user)
    assert_verification :two_factor_user, new_device, Faker::Internet.ip_v4_address, Analytics::Visitor.create.octolytics_id
  end

  test "recognizes verified IPs" do
    assert_verification :verified_ip, new_device, @verified_authentication_record.ip_address, Analytics::Visitor.create.octolytics_id
  end

  test "#masked_primary_and_account_related_emails returns the primary email and a random sampling of the remaining, all masked" do
    5.times do # add one too many emails for display
      @user.add_email(Faker::Internet.email)
    end
    emails = @user.masked_primary_and_account_related_emails
    assert_equal 5, emails.size
    assert_equal @user.mask_email(@user.email), emails.first
    emails.each do |email|
      assert_match /\A[\w]\**@/, email, "#{email} does not match the masked prefix (f**@bar.com)"
    end
  end
end unless GitHub.enterprise? && !GitHub.sign_in_analysis_enabled?
