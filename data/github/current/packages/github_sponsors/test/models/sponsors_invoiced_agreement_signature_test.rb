# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsInvoicedAgreementSignatureTest < GitHub::TestCase
  include HydroTestHelpers

  # skip because EMUs cannot use Sponsors
  skip_with_all_emus

  fixtures do
    @owner = create(:verified_user)
    @other_admin = create(:verified_user)
    @org = create(:organization, admin: @owner)
    @invoice_agreement = create(:sponsors_agreement, :invoiced_sponsor, version: 1)

    @org.add_admin(@other_admin)
  end

  test "sets expiry on creation" do
    signature = SponsorsInvoicedAgreementSignature.new(
      organization: @org,
      agreement: @invoice_agreement,
      signatory: @owner,
    )

    travel_to("2022-03-08") do
      expected_expires = SponsorsInvoicedAgreementSignature::DEFAULT_DURATION_IN_YEARS.years.from_now.to_date

      assert signature.save
      assert_equal @invoice_agreement.id, signature.sponsors_agreement_id
      assert_equal @owner.id, signature.signatory_id
      assert_equal @org.id, signature.organization_id
      assert_equal expected_expires, signature.expires_on
    end
  end

  context "#agreement_version" do
    test "returns the version of the agreement that was signed" do
      agreement = SponsorsAgreement.new(version: "123abc")
      signature = SponsorsInvoicedAgreementSignature.new(agreement: agreement)
      assert_equal "123abc", signature.agreement_version
    end
  end

  context "#terminate" do
    test "sets the expiration date to today" do
      signature = create(:sponsors_invoiced_agreement_signature)
      signature.terminate
      assert_equal Date.current, signature.reload.expires_on
    end

    test "sends the invoice_agreement_signature_terminated email with expected arguments" do
      signature = create(:sponsors_invoiced_agreement_signature)
      SponsorsPrimerMailer.expects(:invoice_agreement_signature_terminated)
        .once
        .with(org: signature.organization, termination_date: Date.current)
        .returns(stub(deliver_later: true))

      signature.terminate
    end
  end

  context "validations" do
    test "requires an agreement" do
      signature = SponsorsInvoicedAgreementSignature.new(agreement: nil)
      refute_predicate signature, :valid?
      assert_includes signature.errors[:agreement], "must exist"
    end

    test "requires an organization" do
      signature = SponsorsInvoicedAgreementSignature.new(organization: nil)
      refute_predicate signature, :valid?
      assert_includes signature.errors[:organization], "must exist"
    end

    test "requires a signatory" do
      signature = SponsorsInvoicedAgreementSignature.new(signatory: nil)
      refute_predicate signature, :valid?
      assert_includes signature.errors[:signatory], "must exist"
    end

    test "requires at creation time that the signatory be an admin or billing manager of the org" do
      org_admin, rando, org_member, billing_manager = create_list(:user, 4)
      org = create(:organization, admin: org_admin)
      org.billing.add_manager(billing_manager, actor: org_admin)
      org.add_member(org_member)

      signature = SponsorsInvoicedAgreementSignature.new(organization: org, signatory: rando)
      refute_predicate signature, :valid?
      assert_includes signature.errors[:signatory], "is not an owner or billing manager for @#{org}"

      signature.signatory = org_member
      refute_predicate signature, :valid?
      assert_includes signature.errors[:signatory], "is not an owner or billing manager for @#{org}"

      signature.signatory = org_admin
      signature.valid?
      assert_empty signature.errors[:signatory]

      signature.signatory = billing_manager
      signature.valid?
      assert_empty signature.errors[:signatory]
    end

    test "requires an invoiced sponsor agreement" do
      agreement = create(:sponsors_agreement, :optional_data_provision)
      refute_predicate agreement, :invoiced_sponsor_kind?

      signature = SponsorsInvoicedAgreementSignature.new(agreement: agreement)
      refute_predicate signature, :valid?
      assert_includes signature.errors[:agreement], "kind does not match signature type"
    end

    test "requires agreement to be the current version" do
      agreement = create(:sponsors_agreement, :invoiced_sponsor, version: 2)
      signature = SponsorsInvoicedAgreementSignature.new(agreement: @invoice_agreement)
      refute_predicate signature, :valid?
      assert_includes signature.errors[:agreement], "must be the current version, 2"
    end
  end

  context ".signed_for_org?" do
    test "returns true when organization has signed the latest agreement and no version is given" do
      agreement = create(:sponsors_agreement, :invoiced_sponsor)
      org = create(:organization)
      create(:sponsors_invoiced_agreement_signature, organization: org, agreement: agreement)

      assert SponsorsInvoicedAgreementSignature.signed_for_org?(org)
    end

    test "returns false when organization has an expired signature for the latest agreement and no version is specified" do
      agreement = create(:sponsors_agreement, :invoiced_sponsor)
      org = create(:organization)
      create(:sponsors_invoiced_agreement_signature, :expired, organization: org, agreement: agreement)

      refute SponsorsInvoicedAgreementSignature.signed_for_org?(org)
    end

    test "returns false when organization has not signed the latest agreement and no version is given" do
      old_agreement = create(:sponsors_agreement, :invoiced_sponsor)
      org = create(:organization)
      create(:sponsors_invoiced_agreement_signature, organization: org, agreement: old_agreement)
      create(:sponsors_agreement, :invoiced_sponsor, version: old_agreement.version + ".1")

      refute SponsorsInvoicedAgreementSignature.signed_for_org?(org)
    end

    test "returns true when organization has signed the agreement at the specified version" do
      old_agreement = create(:sponsors_agreement, :invoiced_sponsor)
      org = create(:organization)
      create(:sponsors_invoiced_agreement_signature, organization: org, agreement: old_agreement)
      create(:sponsors_agreement, :invoiced_sponsor, version: old_agreement.version + ".1")

      assert SponsorsInvoicedAgreementSignature.signed_for_org?(org, version: old_agreement.version)
    end

    test "returns false when organization has an expired signature for the agreement at the specified version" do
      old_agreement = create(:sponsors_agreement, :invoiced_sponsor)
      org = create(:organization)
      create(:sponsors_invoiced_agreement_signature, :expired, organization: org, agreement: old_agreement)
      create(:sponsors_agreement, :invoiced_sponsor, version: old_agreement.version + ".1")

      refute SponsorsInvoicedAgreementSignature.signed_for_org?(org, version: old_agreement.version)
    end

    test "returns false when organization has not signed the agreement at the specified version" do
      old_agreement = create(:sponsors_agreement, :invoiced_sponsor)
      org = create(:organization)
      new_agreement = create(:sponsors_agreement, :invoiced_sponsor, version: old_agreement.version + ".1")
      create(:sponsors_invoiced_agreement_signature, organization: org, agreement: new_agreement)

      refute SponsorsInvoicedAgreementSignature.signed_for_org?(org, version: old_agreement.version)
    end
  end

  context "audit log instrumentation" do
    test "emits an event when a signature is created" do
      agreement = create(:sponsors_agreement, :invoiced_sponsor, version: "8675309")
      org_admin = create(:user)
      org = create(:organization, admin: org_admin)
      events = subscribe("sponsors.invoiced_agreement_sign")

      signature = create(:sponsors_invoiced_agreement_signature, organization: org, signatory: org_admin,
        agreement: agreement)

      refute_nil event = events.pop, "an event was expected"
      expected = {
        sponsors_invoiced_agreement_signature_id: signature.id,
        sponsors_agreement_id: agreement.id,
        version: "8675309",
        actor_id: org_admin.id,
        org_id: org.id,
        expires_on: signature.expires_on,
        org: org.display_login,
        sponsors_agreement: "GitHub Invoiced Sponsor Agreement",
        actor: org_admin.display_login,
      }
      assert_equal expected, event.payload
    end
  end

  context "latest scope" do
    test "includes only the latest signature for any given org" do
      org1 = create(:organization)
      org2 = create(:organization)

      org1_first_signature = create(:sponsors_invoiced_agreement_signature, organization: org1)
      org1_first_signature.update(expires_on: 1.month.from_now)

      org1_second_signature = create(:sponsors_invoiced_agreement_signature, organization: org1)
      org1_second_signature.update(expires_on: 3.months.from_now)

      org2_first_signature = create(:sponsors_invoiced_agreement_signature, organization: org2)
      org2_first_signature.update(expires_on: 2.months.from_now)

      org2_second_signature = create(:sponsors_invoiced_agreement_signature, organization: org2)
      org2_second_signature.update(expires_on: 4.months.from_now)

      result = SponsorsInvoicedAgreementSignature.latest

      assert_same_elements [org1_second_signature, org2_second_signature], result.to_a
    end

    test "only includes one signature for each org" do
      org = create(:organization)

      signature1 = create(:sponsors_invoiced_agreement_signature, organization: org)
      signature2 = create(:sponsors_invoiced_agreement_signature, organization: org)

      result = SponsorsInvoicedAgreementSignature.latest

      # using result.length, because .count returns the number of items grouped by id instead of the overall count
      assert_equal 1, result.length
    end
  end

  context "not_expired scope" do
    test "includes only signatures whose expiration dates have not been met" do
      expired_signature = create(:sponsors_invoiced_agreement_signature, :expired)
      active_signature = create(:sponsors_invoiced_agreement_signature)

      result = SponsorsInvoicedAgreementSignature.not_expired
        .where(id: [expired_signature, active_signature])

      assert_equal [active_signature], result
    end
  end

  context "for_org scope" do
    test "returns signatures for the specified organization" do
      org1, org2, org3 = create_list(:organization, 3)
      org1_signature = create(:sponsors_invoiced_agreement_signature, organization: org1)
      org2_signature1, org2_signature2 = create_pair(:sponsors_invoiced_agreement_signature, organization: org2)

      assert_equal [org1_signature], SponsorsInvoicedAgreementSignature.for_org(org1)
      assert_same_elements [org2_signature1, org2_signature2], SponsorsInvoicedAgreementSignature.for_org(org2)
      assert_empty SponsorsInvoicedAgreementSignature.for_org(org3)
    end
  end

  context "Hydro instrumentation" do
    test "emits an event when signature is created" do
      agreement = create(:sponsors_agreement, :invoiced_sponsor, version: "8675309")
      org_admin = create(:user)
      org = create(:organization, admin: org_admin)

      signature = create(:sponsors_invoiced_agreement_signature, organization: org, signatory: org_admin,
        agreement: agreement)

      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        signatory: Hydro::EntitySerializer.user(org_admin),
        agreement_version: "8675309",
        organization: Hydro::EntitySerializer.organization(org),
        expires_on: signature.expires_on.to_s,
      }

      assert_hydro_published(message, schema: "github.sponsors.v1.SponsorsInvoicedAgreementSign")
      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorsInvoicedAgreementSign")
    end
  end

  context "for_agreement scope" do
    test "returns signatures for the specified agreement" do
      agreement1 = create(:sponsors_agreement, :invoiced_sponsor)
      agreement1_signature = create(:sponsors_invoiced_agreement_signature, agreement: agreement1)

      agreement2 = create(:sponsors_agreement, :invoiced_sponsor)
      agreement2_signature1, agreement2_signature2 = create_pair(:sponsors_invoiced_agreement_signature,
        agreement: agreement2)

      agreement3 = create(:sponsors_agreement, :invoiced_sponsor)

      assert_equal [agreement1_signature], SponsorsInvoicedAgreementSignature.for_agreement(agreement1)
      assert_same_elements [agreement2_signature1, agreement2_signature2], SponsorsInvoicedAgreementSignature
        .for_agreement(agreement2)
      assert_empty SponsorsInvoicedAgreementSignature.for_agreement(agreement3)
    end
  end

  context "#safe_signatory" do
    test "returns signatory user if exists" do
      signature = create(:sponsors_invoiced_agreement_signature,
        organization: @org,
        signatory: @other_admin,
      )
      assert_equal @other_admin, signature.reload.safe_signatory
    end

    test "returns ghost user if signatory has been deleted" do
      signature = create(:sponsors_invoiced_agreement_signature,
        organization: @org,
        signatory: @other_admin,
      )
      @org.remove_member!(@other_admin)
      @other_admin.destroy!
      assert_equal User.ghost, signature.reload.safe_signatory
    end
  end

  context "#safe_organization" do
    test "returns signatory user if exists" do
      signature = create(:sponsors_invoiced_agreement_signature,
        organization: @org,
        signatory: @other_admin,
      )
      assert_equal @org, signature.reload.safe_organization
    end

    test "returns ghost user if organization has been deleted" do
      signature = create(:sponsors_invoiced_agreement_signature,
        organization: @org,
        signatory: @other_admin,
      )
      @org.destroy!
      assert_equal User.ghost, signature.reload.safe_organization
    end
  end
end
