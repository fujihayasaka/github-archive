# typed: true
# frozen_string_literal: true

require "test_helper"

class PublisherVerificationDependencyTest < GitHub::TestCase
  fixtures do
    @org = create(:business_plus_org)
    @user = create(:user)
    @org.add_member(@user)
  end

  context "can_request_verification?" do
    test "returns false if profile email is not set" do
      verification_setup(email: nil)
      refute @org.reload.can_request_verification?(@user)
    end

    test "returns false if profile name is not set" do
      verification_setup(name: nil)
      refute @org.reload.can_request_verification?(@user)
    end

    test "returns false if profile location is not set" do
      verification_setup(location: nil)
      refute @org.reload.can_request_verification?(@user)
    end

    test "returns false if location is not from dropdown list" do
      verification_setup(location: "A place")
      refute @org.reload.can_request_verification?(@user)
    end

    test "returns false if restricted" do
      @org.trade_controls_restriction.tier_1!
      verification_setup(location: "Ukraine")
      refute @org.reload.can_request_verification?(@user)
    end

    test "returns false if location is from embargo list" do
      verification_setup(location: "Syria")
      refute @org.reload.can_request_verification?(@user)
    end

    test "returns false if org domain is not verified" do
      verification_setup(verified: false)
      refute @org.reload.can_request_verification?(@user)
    end

    test "returns false if 2fa is not enabled" do
      verification_setup(two_factor_enabled: false)
      refute @org.reload.can_request_verification?(@user)
    end

    test "returns false if email is not verified" do
      verification_setup
      refute @org.reload.can_request_verification?(@user)
    end

    test "returns true if email is verified" do
      verification_setup
      email_setup(verified: true)
      assert @org.reload.can_request_verification?(@user)
    end
  end

  context "can_request_verification_for_org?" do
    test "returns false if profile email is not set" do
      verification_setup(email: nil)
      refute @org.reload.can_request_verification_for_org?
    end

    test "returns false if profile name is not set" do
      verification_setup(name: nil)
      refute @org.reload.can_request_verification_for_org?
    end

    test "returns false if profile location is not set" do
      verification_setup(location: nil)
      refute @org.reload.can_request_verification_for_org?
    end

    test "returns false if location is not from dropdown list" do
      verification_setup(location: "A place")
      refute @org.reload.can_request_verification_for_org?
    end

    test "returns false if restricted" do
      @org.trade_controls_restriction.tier_1!
      verification_setup(location: "Ukraine")
      refute @org.reload.can_request_verification_for_org?
    end

    test "returns false if location is from embargo list" do
      verification_setup(location: "Syria")
      refute @org.reload.can_request_verification_for_org?
    end

    test "returns false if org domain is not verified" do
      verification_setup(verified: false)
      refute @org.reload.can_request_verification_for_org?
    end

    test "returns false if 2fa is not enabled" do
      refute @org.reload.can_request_verification_for_org?
    end

    test "returns false if email is not verified" do
      verification_setup
      refute @org.reload.can_request_verification_for_org?
    end

    test "returns true if email is verified, domain is verified and org has 2fa enabled" do
      @org.enable_two_factor_required(actor: @user)
      verification_setup
      email_setup(verified: true)
      assert @org.reload.can_request_verification_for_org?
    end
  end

  context "has_verified_domain?" do
    test "returns true if there is a verified domain that belongs to the org" do
      @org.create_profile(email: "user@github.com")
      create(:verifiable_domain, owner: @org, verified: true, domain: @org.profile_email)
      assert @org.has_verified_domain?
    end

    test "returns true if there's a verified domain that belongs to parent enterprise" do
      business = create(:business, organizations: [@org])
      @org.create_profile(email: "user@github.com")
      create(:verifiable_domain, owner: business, verified: true, domain: @org.profile_email)
      assert @org.reload.has_verified_domain?
    end

    test "returns false if there's no verified domain" do
      assert_empty VerifiableDomain.usable_for(@org).verified
      refute @org.has_verified_domain?

      business = create(:business, organizations: [@org])
      create(:verifiable_domain, owner: @org, verified: false)
      create(:verifiable_domain, owner: business, verified: false)
      assert_empty VerifiableDomain.usable_for(@org.reload).verified
      refute_empty VerifiableDomain.usable_for(@org)
      refute @org.has_verified_domain?
    end
  end

  context "profile_complete" do
    test "returns false when email verification is not initiated" do
      verification_setup
      refute @org.reload.profile_complete?
    end

    test "returns false when email is not verified" do
      verification_setup
      email_setup
      refute @org.reload.profile_complete?
    end

    test "returns true when email is verified" do
      verification_setup
      email_setup(verified: true)
      assert @org.reload.profile_complete?
    end
  end

  def verification_setup(
    email: "user@github.com",
    name: "A user",
    location: "India",
    domain_owner: @org,
    verified: true,
    two_factor_enabled: true
  )
    @org.create_profile(email: email, name: name, location: location)
    if email.present?
      create(:verifiable_domain, owner: domain_owner, verified: verified, domain: email)
    else
      create(:verifiable_domain, owner: domain_owner, verified: verified)
    end
    @user.stubs(:two_factor_authentication_enabled?).returns(two_factor_enabled)
  end

  def email_setup(verified: nil)
    if verified
      create(:organization_profile_email, :verified, organization: @org)
    else
      create(:organization_profile_email, organization: @org)
    end
  end
end
