# typed: true
# frozen_string_literal: true

require "test_helper"

class MarketplaceAgreementSignatureTest < GitHub::TestCase
  context "validations" do
    [:agreement, :signatory].each do |attr|
      test "requires #{attr}" do
        signature = Marketplace::AgreementSignature.new(attr => nil)

        refute_predicate signature, :valid?, "should not be valid without a #{attr}"
        assert_predicate signature.errors[attr], :any?, "should require a #{attr}"
      end
    end

    test "requires signatory be an admin of given organization" do
      org = create(:organization)
      user = create(:user)
      org.add_member(user)

      signature = build(:marketplace_agreement_signature, signatory: user, organization: org)

      refute_predicate signature, :valid?
      assert_predicate signature.errors[:signatory], :any?
    end
  end

  context "audit log events" do
    test "creates audit log event on creation" do
      events = subscribe("marketplace_agreement_signature.create")

      user = create(:user)
      agreement = create(:marketplace_agreement)
      signature = create(:marketplace_agreement_signature, signatory: user, agreement: agreement)

      assert event = events.pop, "no event was created"
      assert_equal "marketplace_agreement_signature.create", event.name

      expected_payload = {
        actor: user.login,
        actor_id: user.id,
        user: user.login,
        user_id: user.id,
        marketplace_agreement_id: agreement.id,
        signatory_type: :integrator,
        marketplace_agreement_signature_id: signature.id,
        version: agreement.version,
        marketplace_agreement: "Marketplace Developer Agreement",
      }
      assert_equal expected_payload, event.payload
    end

    test "includes org details if signature is on behalf of an organization" do
      events = subscribe("marketplace_agreement_signature.create")

      user = create(:user)
      agreement = create(:marketplace_agreement, :end_user)
      signature = create(:marketplace_agreement_signature, :organization, signatory: user,
                                                       agreement: agreement)

      assert event = events.pop, "no event was created"
      assert_equal "marketplace_agreement_signature.create", event.name

      expected_payload = {
        actor: user.login,
        actor_id: user.id,
        org: signature.organization.login,
        org_id: signature.organization.id,
        marketplace_agreement_id: agreement.id,
        signatory_type: :end_user,
        marketplace_agreement_signature_id: signature.id,
        version: agreement.version,
        marketplace_agreement: "Marketplace Terms of Service",
      }
      assert_equal expected_payload, event.payload
    end
  end
end
