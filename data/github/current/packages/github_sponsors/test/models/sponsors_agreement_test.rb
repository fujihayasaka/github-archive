# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsAgreementTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @old_agreement = create(:sponsors_agreement, :invoiced_sponsor, version: "1.0")
    @agreement = create(:sponsors_agreement, :invoiced_sponsor, version: "1.1")
  end

  setup do
    skip unless GitHub.sponsors_enabled?
  end

  context "#total_active_signatures" do
    test "returns count of non-expired signatures for the agreement" do
      assert_equal 0, @agreement.total_active_signatures

      create(:sponsors_invoiced_agreement_signature, agreement: @agreement)
      assert_equal 1, @agreement.reload.total_active_signatures

      create(:sponsors_invoiced_agreement_signature, :expired, agreement: @agreement)
      assert_equal 1, @agreement.reload.total_active_signatures
    end

    test "can be efficiently batch loaded" do
      create_pair(:sponsors_invoiced_agreement_signature, agreement: @agreement)

      agreement2 = create(:sponsors_agreement, :invoiced_sponsor, version: @agreement.version + ".1")
      create(:sponsors_invoiced_agreement_signature, agreement: agreement2)

      agreement3 = create(:sponsors_agreement, :invoiced_sponsor, version: agreement2.version + ".1")

      agreements = [@agreement, agreement2, agreement3]

      assert_query_count(1) do
        GitHub::PrefillAssociations.prefill_batch_method(agreements, :total_active_signatures)
      end

      assert_query_count(0) do
        assert_equal 2, @agreement.total_active_signatures
        assert_equal 1, agreement2.total_active_signatures
        assert_equal 0, agreement3.total_active_signatures
      end
    end
  end

  context "with_latest_version scope" do
    test "filters to just the agreements with the latest version for their kind" do
      other_kind_old = create(:sponsors_agreement, :optional_data_provision, version: "0.1a")
      other_kind_new = create(:sponsors_agreement, :optional_data_provision, version: "0.2")

      result = SponsorsAgreement.with_latest_version
        .where(id: [@old_agreement, @agreement, other_kind_old, other_kind_new])

      assert_same_elements [other_kind_new, @agreement], result
    end
  end

  context "newest_first scope" do
    test "sorts by version descending" do
      agreement2 = create(:sponsors_agreement, :invoiced_sponsor, version: "1.5")
      agreement3 = create(:sponsors_agreement, :invoiced_sponsor, version: "2.0a")

      result = SponsorsAgreement.newest_first.where(id: [@agreement.id, agreement2.id, agreement3.id])

      assert_equal [agreement3, agreement2, @agreement], result
    end
  end

  context "validations" do
    test "requires a non-nil body" do
      agreement = SponsorsAgreement.new(body: nil)
      refute_predicate agreement, :valid?
      assert_includes agreement.errors[:body], "can't be blank"
    end

    test "requires a non-blank body" do
      agreement = SponsorsAgreement.new(body: "")
      refute_predicate agreement, :valid?
      assert_includes agreement.errors[:body], "can't be blank"
    end

    test "requires a non-nil version" do
      agreement = SponsorsAgreement.new(version: nil)
      refute_predicate agreement, :valid?
      assert_includes agreement.errors[:version], "can't be blank"
    end

    test "requires a non-blank version" do
      agreement = SponsorsAgreement.new(version: "")
      refute_predicate agreement, :valid?
      assert_includes agreement.errors[:version], "can't be blank"
    end

    test "requires a unique version per kind" do
      new_agreement = build(:sponsors_agreement, version: @agreement.version, kind: @agreement.kind)
      refute_predicate new_agreement, :valid?
      assert_includes new_agreement.errors[:version], "has already been taken"
    end

    test "requires version to increase only, for non-org-specific agreements" do
      new_agreement = build(:sponsors_agreement, :invoiced_sponsor, version: "1.01")
      refute_predicate new_agreement, :valid?
      assert_includes new_agreement.errors[:version], "1.01 must come after the previous invoiced_sponsor " \
        "version, 1.1"
    end

    test "requires version to increase only, for org-specific agreement" do
      org = create(:organization, login: "GreatestOrg")
      existing_agreement = create(:sponsors_agreement, :invoiced_sponsor, version: "GreatVersion1.0",
        organization: org)
      new_agreement = build(:sponsors_agreement, :invoiced_sponsor, version: "GreatVersion0.5", organization: org)
      refute_predicate new_agreement, :valid?
      assert_includes new_agreement.errors[:version], "GreatVersion0.5 must come after the previous " \
        "@GreatestOrg-specific invoiced_sponsor version, GreatVersion1.0"
    end

    test "requires organization_login to be valid when specified for a new agreement" do
      agreement = SponsorsAgreement.new(organization_login: "invalid")
      refute_predicate agreement, :valid?
      assert_includes agreement.errors[:organization_login], "does not match an existing organization"
    end

    test "requires organization_id to be valid when specified for a new agreement" do
      max_id = Organization.maximum(:id) || 0
      agreement = SponsorsAgreement.new(organization_id: max_id + 1)
      refute_predicate agreement, :valid?
      assert_includes agreement.errors[:organization_id], "does not exist"
    end
  end

  test "sets organization from organization_login when specified" do
    org = create(:organization)
    agreement = create(:sponsors_agreement, organization_login: org.login, organization: nil, organization_id: nil)
    assert_equal org, agreement.reload.organization
  end

  context "#organization_login" do
    test "returns nil for agreement without an organization" do
      assert_nil @agreement.organization_login
    end

    test "returns the organization's login for an organization-specific agreement" do
      org = create(:organization)
      agreement = create(:sponsors_agreement, organization: org)
      assert_equal org.display_login, agreement.organization_login
    end

    test "memoizes result to avoid repeat lookups" do
      org = create(:organization)
      agreement_with_org = create(:sponsors_agreement, organization_id: org.id)
      agreement_with_org.reload
      agreement_wo_org = create(:sponsors_agreement, organization_id: nil)
      agreement_wo_org.reload

      assert_query_count(1) do
        assert_equal org.display_login, agreement_with_org.organization_login
        assert_nil agreement_wo_org.organization_login
      end

      assert_query_count(0) do
        assert_equal org.display_login, agreement_with_org.organization_login
        assert_equal org.display_login, agreement_with_org.organization_login
        assert_nil agreement_wo_org.organization_login
        assert_nil agreement_wo_org.organization_login
      end
    end
  end

  context ".latest_version_by_kind_and_organization_id" do
    test "returns a hash of agreement kinds, organization IDs, and the the most recent version for that kind + org" do
      other_agreement = create(:sponsors_agreement, :optional_data_provision)
      org1, org2 = create_pair(:organization)
      create(:sponsors_agreement, :invoiced_sponsor, organization: org1, version: "org1-v1")
      org1_latest = create(:sponsors_agreement, :invoiced_sponsor, organization: org1, version: "org1-v2")
      org2_latest = create(:sponsors_agreement, :invoiced_sponsor, organization: org2, version: "Org 2 version")
      expected = {
        "optional_data_provision" => { nil => other_agreement.version },
        "invoiced_sponsor" => {
          nil => @agreement.version,
          org1.id => org1_latest.version,
          org2.id => org2_latest.version,
        },
      }
      assert_equal expected, SponsorsAgreement.latest_version_by_kind_and_organization_id
    end
  end

  context ".current_invoiced_sponsor_agreement" do
    test "returns the agreement of kind=invoiced_sponsor with the most recent version" do
      assert_equal @agreement, SponsorsAgreement.current_invoiced_sponsor_agreement

      newer_agreement = create(:sponsors_agreement, :invoiced_sponsor, version: @agreement.version + ".1")
      assert_equal newer_agreement, SponsorsAgreement.current_invoiced_sponsor_agreement

      other_agreement_kind = create(:sponsors_agreement, :optional_data_provision,
        version: newer_agreement.version + ".1")
      assert_equal newer_agreement, SponsorsAgreement.current_invoiced_sponsor_agreement,
        "should not return newer version of a different kind"
    end

    test "does not return org-specific agreement even if it's the latest" do
      assert_equal @agreement, SponsorsAgreement.current_invoiced_sponsor_agreement

      newer_org_specific_agreement = create(:sponsors_agreement, :invoiced_sponsor,
        organization: create(:organization),
        version: @agreement.version + ".1")
      assert_equal @agreement, SponsorsAgreement.current_invoiced_sponsor_agreement
    end
  end

  context "#name" do
    test "returns human-friendly name for kind=optional_data_provision" do
      agreement = SponsorsAgreement.new(kind: :optional_data_provision)
      assert_equal SponsorsAgreement::AGREEMENT_NAMES_BY_KIND[:optional_data_provision], agreement.name
    end

    test "returns human-friendly name for kind=invoiced_sponsor" do
      agreement = SponsorsAgreement.new(kind: :invoiced_sponsor)
      assert_equal SponsorsAgreement::AGREEMENT_NAMES_BY_KIND[:invoiced_sponsor], agreement.name
    end
  end

  context "#body_html" do
    test "supports empty body" do
      agreement = build(:sponsors_agreement, body: nil)
      assert_equal "", agreement.body_html
    end

    test "supports colon-style emoji" do
      agreement = build(:sponsors_agreement, body: ":smile:")
      doc = Nokogiri::HTML.fragment(agreement.body_html)
      refute_nil doc.css("g-emoji[alias='smile']")
    end

    test "supports native emoji" do
      agreement = build(:sponsors_agreement, body: GRIN_EMOJI)
      doc = Nokogiri::HTML.fragment(agreement.body_html)
      refute_nil doc.css("g-emoji[alias='smile']")
    end
  end
end
