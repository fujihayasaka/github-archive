# typed: true
# frozen_string_literal: true

require "test_helper"

class TradeControlsDomainsTest < GitHub::TestCase
  context ".sanctioned_email" do
    [
      "example.gov.ir",
      "justice.ir",
      "example.gob.cu",
      "mic.cu",
      "aq.ru",
      "pib.ua",
      "mzkt.by",
      "tishreen.edu.sy",
      "sberbank.at",
      "vtb.eu",
      "vtb.com.vn",
      "asbgroup.com.tr",
      "vpv.su",
      "nu.edu.pk",
      "bentway.de",
      "ideascup.me",
      "bisoft.com.mx",
      "hamriyahsteel.ae",
      "ron.in",
      "mci.rs",
      "vbbrothers.com.mv",
      "gt.cn",
      "sistema.com.ro",
      "ett.be",
      "herzallah.ps",
      "ugmk.com"
    ].each do |domain|
      test "#{domain} is treated as sanctioned email" do
        assert TradeControls::Domains.sanctioned_email?("test@#{domain}")
      end
    end

    [
      "example.gov.ir@example.com",
      "user@anotherjustice.ir",
      "  ",
      "",
      "example@somecu.cu"
    ].each do |email|
      test "#{email} is not treated as sanctioned email" do
        refute TradeControls::Domains.sanctioned_email?(email)
      end
    end
  end
end
