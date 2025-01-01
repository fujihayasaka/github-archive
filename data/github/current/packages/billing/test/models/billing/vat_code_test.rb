# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::VatCodeTest < GitHub::BillingTestCase
  def parse_vat(vat_code)
    Billing::VatCode.parse(vat_code)
  end

  test "given a non-vat_code, returns nil" do
    assert_nil parse_vat("")
    assert_nil parse_vat(nil)
    assert_nil parse_vat("BELGIUM")
    assert_nil parse_vat("I AM NOT A VAT CODE")
    assert_nil parse_vat("AL1 4LE\r\n\r")
    assert_nil parse_vat("TW9 2BX\r")
    assert_nil parse_vat("NO 913385195 MVA")
    assert_nil parse_vat("NECULAI STEFAN IF\r\nCUI 32595829")
  end

  test "given a user with billing extra, parses vat_code" do
    assert_equal "ATU12345678", parse_vat("ATU12345678")     # Austria
    assert_equal "BE0123456789", parse_vat("BE0123456789")     # Belgium
    assert_equal "BG123456789", parse_vat("BG123456789")       # Bulgaria v1
    assert_equal "BG1234567899", parse_vat("BG1234567899")     # Bulgaria v2
    assert_equal "CY12345678L", parse_vat("CY12345678L")       # Cyprus
    assert_equal "CZ12345678", parse_vat("CZ12345678")         # Czech
    assert_equal "CZ123456789", parse_vat("CZ123456789")
    assert_equal "CZ1234567899", parse_vat("CZ1234567899")
    assert_equal "DE123456789", parse_vat("DE123456789")       # Germany
    assert_equal "DK12 34 56 78", parse_vat("DK12 34 56 78")   # Denmark
    assert_equal "EE123456789", parse_vat("EE123456789")       # Estonia
    assert_equal "EL123456789", parse_vat("EL123456789")       # Greece
    assert_equal "ESX1234567X", parse_vat("ESX1234567X")     # Spain
    assert_equal "FI12345678", parse_vat("FI12345678")         # Finland
    assert_equal "FRXX 123456789", parse_vat("FRXX 123456789") # France
    assert_equal "HR12345678999", parse_vat("HR12345678999")   # Croatia
    assert_equal "HU12345678", parse_vat("HU12345678")         # Hungary
    assert_equal "IE9S99999L", parse_vat("IE9S99999L")         # Ireland
    assert_equal "LT123456789", parse_vat("LT123456789")       # Lithuania
    assert_equal "LT1234567899", parse_vat("LT1234567899")
    assert_equal "LU12345678", parse_vat("LU12345678")         # Luxembourg
    assert_equal "LV12345678999", parse_vat("LV12345678999")   # Latvia
    assert_equal "MT12345678", parse_vat("MT12345678")         # Malta
    assert_equal "NL123456789999", parse_vat("NL123456789999") # Netherlands
    assert_equal "PL1234567899", parse_vat("PL1234567899")     # Poland
    assert_equal "PT123456789", parse_vat("PT123456789")       # Portugal
    assert_equal "RO99", parse_vat("RO99")                     # Romania
    assert_equal "RO1234567899", parse_vat("RO1234567899")
    assert_equal "SE123456789999", parse_vat("SE123456789999") # Sweden
    assert_equal "SK1234567899", parse_vat("SK1234567899")     # Slovakia
    assert_equal "GB123 4567 89", parse_vat("GB123 4567 89")   # UK
    assert_equal "GB123 4567 89 999", parse_vat("GB123 4567 89 999")
    assert_equal "GBGD999", parse_vat("GBGD999")
  end

  test "weird ones" do
    assert_equal "DE256709442", parse_vat("VAT DE256709442")
    assert_equal "ESB91815951", parse_vat("ESB91815951")
    assert_equal "BG123456789", parse_vat("BG 123456789")
    assert_equal "FR82 512708041", parse_vat("FR82\t512708041")
    assert_equal "FR00 539699751", parse_vat("FR 00 539699751")
    assert_equal "GB898 8697 11", parse_vat("GB 898 8697 11")
    assert_equal "NL211368593B01", parse_vat("MUNKICLOUD\r\nBTW: NL211368593B01")
    # assert_equal "ATU17448304", parse_vat("ATU 174 48304")
    assert_equal "GB168 2878 59",
      parse_vat("TIS\r\nPlymouth University\r\nDrake Circus\r\nPlymouth\r\nDevon\r\nPL48AA\r\nGB168287859")
    assert_equal "BE0503965379",
      parse_vat("ADAMWEB SPRL\r\n198B BOULEVARD INDUSTRIEL 1190 BRUXELLES BELGIQUE\r\nTVA: BE0503965379")
    assert_equal "PL5262091147",
      parse_vat("EVIGO sp. z o.o. sp.k.\r\nZielna 37\r\n00-108 Warsaw\r\nPOLAND\r\nPL5262091147")
    assert_equal "BE0894351777",
      parse_vat("Palacehotel Software sprl\r\n159, chaussée de Charleroi\r\n1060 Bruxelles\r\nBELGIUM\r\nNE: BE0894351777")
  end
end
