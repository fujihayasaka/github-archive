# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsBusinessTaxIdentifierTest < GitHub::TestCase
  context "validations" do
    test "requires a user" do
      record = build(:sponsors_business_tax_identifier, user: nil)

      refute_predicate record, :valid?
      assert_includes record.errors[:user], "must exist"
    end

    test "requires region" do
      record = build(:sponsors_business_tax_identifier, region: nil)
      refute_predicate record, :valid?
      assert_includes record.errors[:region], "can't be blank"
    end

    test "validates country length" do
      record = build(:sponsors_business_tax_identifier)
      assert_equal 2, record.country.length
      assert_predicate record, :valid?

      record.country = "a"
      refute_predicate record, :valid?
      assert_includes record.errors[:country], "is the wrong length (should be 2 characters)"

      record.country = "aaa"
      refute_predicate record, :valid?
      assert_includes record.errors[:country], "is the wrong length (should be 2 characters)"
    end

    test "validates region matches country" do
      record = build(:sponsors_business_tax_identifier, country: "US", region: "CA-QC")
      refute_predicate record, :valid?

      assert_includes record.errors[:region], "is not a valid region for this country"
    end

    test "validates ISO3166 country" do
      record = build(:sponsors_business_tax_identifier, country: "ZZ")
      refute_predicate record, :valid?

      assert_includes record.errors[:country], "is not a valid country"
    end

    test "validates US doesn't use VAT" do
      valid_record = build(:sponsors_business_tax_identifier,
        country: "US",
        region: "US-TX",
        vat_code: nil
      )
      assert_predicate valid_record, :valid?

      invalid_record = build(:sponsors_business_tax_identifier,
        country: "US",
        region: "US-TX",
        vat_code: "no-vat-for-usa"
      )
      refute_predicate invalid_record, :valid?

      assert_includes invalid_record.errors[:vat_code], "is not supported for this country"
    end
  end

  test "#human_country" do
    business_tax_identifier = build(:sponsors_business_tax_identifier, country: "US")
    assert_equal "United States of America", business_tax_identifier.human_country
  end

  test "#human_region" do
    business_tax_identifier = build(:sponsors_business_tax_identifier, region: "US-CA")
    assert_equal "California", business_tax_identifier.human_region
  end
end if GitHub.sponsors_enabled?
