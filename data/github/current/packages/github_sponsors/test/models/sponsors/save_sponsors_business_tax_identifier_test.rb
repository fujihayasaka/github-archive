# typed: true
# frozen_string_literal: true

require "test_helper"

class Sponsors::SaveSponsorsBusinessTaxIdentifierTest < GitHub::TestCase
  fixtures do
    @sponsor = create(:user)
  end

  setup do
    @inputs = {
      user: @sponsor,
      country: "AU",
      region: "AU-NSW",
      vat_code: "123-VAT"
    }
  end

  test "creates new SponorsBusinessTaxIdentifier if one does not exist yet" do
    assert_difference "SponsorsBusinessTaxIdentifier.count", 1 do
      save_business_tax_identifier
    end

    assert_saved_business_tax_identifier
  end

  test "creates new SponsorsBusinessTaxIdentifier if country, region, or vat_code is different" do
    [{ country: "CA", region: "CA-ON" }, { region: "AU-VIC" }, { vat_code: "123-different" }].each do |different_attrs|
      create(:sponsors_business_tax_identifier, **@inputs)

      assert_difference "SponsorsBusinessTaxIdentifier.count", 1 do
        save_business_tax_identifier(overrides: different_attrs)
      end

      assert_saved_business_tax_identifier(overrides: different_attrs)
    end
  end

  test "does not create new SponsorsBusinessTaxIdentifier if one exists with the exact same info" do
    _tax_identifier_with_same_info = create(:sponsors_business_tax_identifier, **@inputs)

    assert_no_difference "SponsorsBusinessTaxIdentifier.count" do
      save_business_tax_identifier
    end
  end

  test "creates new SponsorsBusinessTaxIdentifier if same tax info exists but for different user" do
    tax_identifier_with_different_sponsor = create(
      :sponsors_business_tax_identifier,
      **@inputs.merge(user: create(:user))
    )

    assert_difference "SponsorsBusinessTaxIdentifier.count", 1 do
      save_business_tax_identifier
    end

    assert_saved_business_tax_identifier
  end

  test "raises UnprocessableError if SponsorsBusinessTaxIdentifier fails to save" do
    error = assert_raises Sponsors::SaveSponsorsBusinessTaxIdentifier::UnprocessableError do
      save_business_tax_identifier(overrides: { country: nil, region: nil })
    end
    assert_equal "Could not save tax info: Country is the wrong length (should be 2 characters)," \
     " Region can't be blank, and Country is not a valid country", error.message
  end

  def save_business_tax_identifier(overrides: {})
    Sponsors::SaveSponsorsBusinessTaxIdentifier.call(**@inputs.merge(overrides))
  end

  def assert_saved_business_tax_identifier(overrides: {})
    inputs = @inputs.merge(overrides)
    tax_identifier = SponsorsBusinessTaxIdentifier.last

    assert_equal T.must(tax_identifier).user, inputs[:user]
    assert_equal T.must(tax_identifier).country, inputs[:country]
    assert_equal T.must(tax_identifier).region, inputs[:region]
    assert_equal T.must(tax_identifier).vat_code, inputs[:vat_code]
  end
end unless GitHub.enterprise?
