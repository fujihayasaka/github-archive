# typed: true
# frozen_string_literal: true

require "test_helper"

class MarketplaceAgreementTest < GitHub::TestCase
  context "validations" do
    [:body, :version, :signatory_type].each do |attr|
      test "requires a #{attr}" do
        agreement = build(:marketplace_agreement)
        agreement.send(:write_attribute, attr, nil)

        refute_predicate agreement, :valid?, "should not be valid without a #{attr}"
        assert_predicate agreement.errors[attr], :any?, "should require a #{attr}"
      end
    end

    test "requires a unique version per signatory type" do
      create(:marketplace_agreement, version: "1.0", signatory_type: :integrator)
      create(:marketplace_agreement, version: "1.0", signatory_type: :end_user)

      agreement = build(:marketplace_agreement, version: "1.0", signatory_type: :integrator)
      refute_predicate agreement, :valid?
      assert_predicate agreement.errors[:version], :any?
    end

    test "ensures later integrator agreements have a later version" do
      create(:marketplace_agreement, version: "v1.0")
      agreement2 = build(:marketplace_agreement, version: "v0.9")

      refute_predicate agreement2, :valid?
      assert_predicate agreement2.errors[:version], :any?
    end

    test "ensures later end-user agreements have a later version" do
      create(:marketplace_agreement, :end_user, version: "4")
      agreement2 = build(:marketplace_agreement, :end_user, version: "3")

      refute_predicate agreement2, :valid?
      assert_predicate agreement2.errors[:version], :any?
    end
  end

  context "#signed_by?" do
    test "true when personal signature exists for the agreement and given user" do
      signature = create(:marketplace_agreement_signature)

      assert signature.agreement.signed_by?(signature.signatory)
    end

    test "false when org signature exists for the agreement and given user" do
      signature = create(:marketplace_agreement_signature, :organization)

      refute signature.agreement.signed_by?(signature.signatory)
    end

    test "false when no signature exists for the agreement and given user" do
      agreement = create(:marketplace_agreement)

      refute agreement.signed_by?(create(:user))
    end
  end

  context "#signed_for?" do
    test "true when signature exists for the agreement and given org" do
      signature = create(:marketplace_agreement_signature, :organization)

      assert signature.agreement.signed_for?(signature.organization)
    end

    test "false when no signature exists for the agreement and given org" do
      agreement = create(:marketplace_agreement)

      refute agreement.signed_for?(create(:organization))
    end
  end

  context "#latest_for_integrators" do
    test "returns nil when no integrator agreement" do
      create(:marketplace_agreement, :end_user)

      assert_nil Marketplace::Agreement.latest_for_integrators
    end

    test "returns latest version of integrator agreement when there are multiple" do
      create(:marketplace_agreement, version: "3.1")
      agreement = create(:marketplace_agreement, version: "3.2")

      assert_equal agreement, Marketplace::Agreement.latest_for_integrators
    end
  end

  context "#latest_for_end_users" do
    test "returns nil when no end user agreement" do
      create(:marketplace_agreement) # for integrators

      assert_nil Marketplace::Agreement.latest_for_end_users
    end

    test "returns latest version of end-user agreement when there are multiple" do
      create(:marketplace_agreement, :end_user, version: "0.1a")
      agreement = create(:marketplace_agreement, :end_user, version: "1.0")

      assert_equal agreement, Marketplace::Agreement.latest_for_end_users
    end
  end

  context "#sign" do
    test "returns true when signature is created" do
      agreement = create(:marketplace_agreement)
      user = create(:user)
      org = create(:organization, admin: user)

      assert_difference "agreement.signatures.count" do
        assert agreement.sign(user: user, organization: org)
      end
    end

    test "returns false when signature fails to save" do
      agreement = create(:marketplace_agreement)
      org = create(:organization)

      assert_no_difference "Marketplace::AgreementSignature.count" do
        refute agreement.sign(user: nil, organization: org)
      end
    end
  end
end
