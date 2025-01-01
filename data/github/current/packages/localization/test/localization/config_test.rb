# typed: true
# frozen_string_literal: true

require_relative "../fast_test_helper"
require RAILS_PATH.join("app/helpers/trending/spoken_language_finder").to_s

class Localization::ConfigTest < GitHub::TestCase
  def config
    @config ||= Localization::Config.new(request: request)
  end

  def create_config
    Localization::Config.new
  end

  def user
    User.new(id: 1)
  end

  def user_config
    config.for_actor(user)
  end

  def setup
    skip if GitHub.enterprise?
    reset_flipper
  end

  test "#ugct_banner_enabled? returns false when disabled" do
    GitHub.flipper[:ugc_machine_translation_banner].disable

    refute config.ugct_banner_enabled?
    refute user_config.ugct_banner_enabled?
  end

  test "#ugct_banner_enabled? returns true when enable" do
    GitHub.flipper[:ugc_machine_translation_banner].enable

    assert config.ugct_banner_enabled?
    assert user_config.ugct_banner_enabled?
  end

  test "#default_currency" do
    assert_equal "USD", config.default_currency
  end

  test "#user_currency" do
    assert_equal "USD", config.user_currency
  end

  test "#available_locales" do
    expected = %w[en ja pt ko]

    assert_equal expected.sort, config.available_locales.sort
  end

  test "#default_locale" do
    assert_equal "en", config.default_locale
  end

  test "#country_code returns a country code" do

    GitHub::Location.stubs(:look_up).with("the-remote_ip").returns(country_code: "BR")

    assert_equal "BR", config.country_code
  end

  test "#allowed_accept_language_headers includes only en-US by default" do
    GitHub.flipper[:ko_homepage_translation].disable
    GitHub.flipper[:pt_br_homepage_translation].disable

    assert_equal %w[en-US ja], config.allowed_accept_language_headers
  end

  test "#allowed_accept_language_headers korean languages when they are enabled" do
    GitHub.flipper[:ko_homepage_translation].enable
    GitHub.flipper[:pt_br_homepage_translation].disable

    assert_equal %w[en-US ja ko ko-KR].sort, config.allowed_accept_language_headers.sort
  end

  test "#allowed_accept_language_headers Portuguese language when they are enabled" do
    GitHub.flipper[:ko_homepage_translation].disable
    GitHub.flipper[:pt_br_homepage_translation].enable

    assert_equal %w[en-US ja pt-BR].sort, config.allowed_accept_language_headers.sort
  end

  test "#homepage_translation_languages returns empty array :ko_homepage_translation is disabled" do
    GitHub.flipper[:ko_homepage_translation].disable

    assert_equal [], config.homepage_translation_languages
  end

  test "#homepage_translation_languages includes 'ko' when :ko_homepage_translation is enabled" do
    GitHub.flipper[:ko_homepage_translation].enable

    assert_equal ["ko"], config.homepage_translation_languages
  end

  test "#primary_browser_language returns top priority language" do
    assert_equal "pt-BR", config.primary_browser_language
  end

  test "#primary_browser_language_name returns top priority language" do
    assert_equal "Portuguese", config.primary_browser_language_name
  end

  test "#language_name returns language name in English" do
    assert_equal "Portuguese", config.language_name("pt-BR")
    assert_equal "Korean", config.language_name("ko")
    assert_equal "English", config.language_name("en-us")
    assert_equal "English", config.language_name("en")
  end

  test "#ugct_languages" do
    assert_equal %w[en ko pt es], config.ugct_languages
  end

  test "#ugct_supports_language?" do
    assert config.ugct_supports_language?("en")
    assert config.ugct_supports_language?("pt")
    assert config.ugct_supports_language?("ko")
    assert config.ugct_supports_language?("en-US")
    refute config.ugct_supports_language?("xy")
    refute config.ugct_supports_language?(nil)
  end

  private

  def bank
    key = Localization::CurrencyExchangeBank::CURRENCY_CACHE_KEY
    GitHub.cache.delete(key)
    GitHub.cache.write(key, cached)

    @bank ||= Money::Bank::VariableExchange.new(Localization::CurrencyExchangeBank.new)
  end

  def cached
    '{"disclaimer":"Usage subject to terms: https://openexchangerates.org/terms","license":"https://openexchangerates.org/license","timestamp":1614110400,"base":"USD","rates":{"AED":3.67295,"AFN":77.199999,"ALL":101.756827,"AMD":523.749793,"ANG":1.795038,"AOA":648,"ARS":89.4745,"AUD":1.264004,"AWG":1.8,"AZN":1.700805,"BAM":1.609405,"BBD":2,"BDT":84.797462,"BGN":1.608356,"BHD":0.376705,"BIF":1960,"BMD":1,"BND":1.320585,"BOB":6.905171,"BRL":5.4454,"BSD":1,"BTC":0.000021750981,"BTN":72.465051,"BTS":23.1913861702,"BWP":10.858286,"BYN":2.59963,"BZD":2.015765,"CAD":1.259292,"CDF":1978.5,"CHF":0.905455,"CLF":0.02555,"CLP":704.699526,"CNH":6.460547,"CNY":6.46665,"COP":3596.623952,"CRC":611.785581,"CUC":1,"CUP":25.75,"CVE":91.225,"CZK":21.293823,"DASH":0.0046230017,"DJF":178.025,"DKK":6.123737,"DOGE":22.4741268041,"DOP":58.03,"DZD":132.834017,"EGP":15.6813,"ERN":14.999599,"ETB":40.302548,"ETH":0.0006863559,"EUR":0.823433,"FJD":2.02435,"FKP":0.708829,"GBP":0.708829,"GEL":3.315,"GGP":0.708829,"GHS":5.75,"GIP":0.708829,"GMD":51.28,"GNF":10085,"GTQ":7.704696,"GYD":209.15793,"HKD":7.754128,"HNL":24.05998,"HRK":6.2414,"HTG":76.024187,"HUF":295.283623,"IDR":14082.7,"ILS":3.26905,"IMP":0.708829,"INR":72.39955,"IQD":1461.5,"IRR":42105,"ISK":127.65,"JEP":0.708829,"JMD":150.965998,"JOD":0.709,"JPY":105.3234,"KES":109.7,"KGS":84.555601,"KHR":4065,"KMF":405.149922,"KPW":900,"KRW":1111.662194,"KWD":0.302541,"KYD":0.83334,"KZT":414.957,"LAK":9355,"LBP":1524.5,"LD":320,"LKR":193.502386,"LRD":173.375018,"LSL":14.56,"LTC":0.0061109753,"LYD":4.46,"MAD":8.885,"MDL":17.479552,"MGA":3765.659784,"MKD":50.69816,"MMK":1410.020462,"MNT":2851.534298,"MOP":7.98621,"MRO":356.999828,"MRU":36.016555,"MUR":39.703377,"MVR":15.4,"MWK":780,"MXN":20.539858,"MYR":4.0425,"MZN":75.199995,"NAD":14.645,"NGN":381,"NIO":34.900483,"NOK":8.481301,"NPR":115.942488,"NXT":32.0586808824,"NZD":1.362361,"OMR":0.385009,"PAB":1,"PEN":3.652,"PGK":3.527896,"PHP":48.634372,"PKR":159.1,"PLN":3.71045,"PYG":6620.813908,"QAR":3.641,"RON":4.0147,"RSD":96.634807,"RUB":73.9985,"RWF":982.5,"SAR":3.750668,"SBD":8.000512,"SCR":21.205385,"SDG":55.25,"SEK":8.294362,"SGD":1.320226,"SHP":0.708829,"SLL":10204.249948,"SOS":584,"SRD":14.154,"SSP":130.26,"STD":20337.466992,"STN":20.4,"STR":2.7841510856,"SVC":8.750422,"SYP":512.833906,"SZL":14.73,"THB":30.02,"TJS":11.395505,"TMT":3.5,"TND":2.7245,"TOP":2.288415,"TRY":7.109888,"TTD":6.791979,"TWD":27.855999,"TZS":2319.107,"UAH":27.930631,"UGX":3670.21493,"USD":1,"UYU":43.053599,"UZS":10542.480586,"VEF_BLKMKT":1900251.91,"VEF_DICOM":1803699.72,"VEF_DIPRO":98988526.49,"VES":1754923.732456,"VND":23051.491528,"VUV":107.611294,"WST":2.504587,"XAF":540.136827,"XAG":0.03624509,"XAU":0.00055435,"XCD":2.70255,"XDR":0.692055,"XMR":0.0050490789,"XOF":540.136827,"XPD":0.00042344,"XPF":98.261728,"XPT":0.00080906,"XRP":2.204236906,"YER":250.349961,"ZAR":14.56125,"ZMW":21.743298,"ZWL":322}}'
  end

  def request
    @request ||= mock.tap do |req|
      req.stubs(:params).returns({})
      req.stubs(:headers).returns({ "HTTP_ACCEPT_LANGUAGE" => "pt-BR" })
      req.stubs(:remote_ip).returns("the-remote_ip")
    end
  end
end
