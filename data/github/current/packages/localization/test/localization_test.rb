# typed: true
# frozen_string_literal: true

require_relative "./fast_test_helper"

class LocalizationTest < GitHub::TestCase
  def _(key, options = {})
    Localization._(key, options)
  end

  def setup
    FastGettext.add_text_domain("testing", path: File.join(Rails.root, "test/fixtures/localization/config"), type: :po)
    enable_feature_flag(:pt_br_homepage_translation)
  end

  def localize(locale: "pt-BR", domain: "testing", raise_errors: false, &block)
    Localization.with_domain(domain) do
      Localization.with_locale_from_http_accept_language_header(locale) do
        Localization.with_raise_on_missing_translations(raise_errors, &block)
      end
    end
  end

  test "temporarily swiches locale with #with_locale" do
    assert_equal :en, I18n.locale.to_sym
    assert_equal :en, FastGettext.locale.to_sym

    Localization.with_locale("pt") do
      assert_equal :pt, I18n.locale.to_sym
      assert_equal :pt, FastGettext.locale.to_sym
    end

    assert_equal :en, I18n.locale.to_sym
    assert_equal :en, FastGettext.locale.to_sym
  end

  test "with locale leaves restores locale even if an error is raised" do
    assert_equal :en, I18n.locale.to_sym
    assert_equal :en, FastGettext.locale.to_sym

    error = assert_raises do
      Localization.with_locale("pt") { raise "Not a bug. A feature" }
      fail "This line should not have been executed"
    end

    assert_equal "Not a bug. A feature", error.message
    assert_equal :en, I18n.locale.to_sym
    assert_equal :en, FastGettext.locale.to_sym
  end

  test "it handles locale: pt-BR" do
    localize do
      assert_equal :pt, I18n.locale
      assert_equal "pt", FastGettext.locale
    end
  end

  test "it handles locale: ja" do
    localize(locale: "ja") do
      assert_equal :ja, I18n.locale
      assert_equal "ja", FastGettext.locale
    end
  end

  test "it translates string" do
    localize do
      actual = _("A plain message")
      expected = "Uma mensagem simples"

      assert_equal expected, actual
    end
  end

  test "it translates strings to japanese" do
    localize(locale: "ja") do
      actual = _("I love Tokyo")
      expected = "東京が大好き"

      assert_equal expected, actual
    end
  end

  test "it raises when translation is missing and configuration is set to raise" do
    localize(raise_errors: true) do
      key = "xz.xpto.yada-yada"

      error = assert_raises(Localization::MissingTranslationData) do
        _(key)
      end

      assert_equal "translation missing: #{key}", error.message
    end
  end

  test "it returns key by default" do
    localize do
      key = "xz.xpto.yada-yada"

      actual = _(key)
      expected = key

      assert_equal expected, actual
    end
  end

  test "it interpolates with % sign" do
    localize do
      key = "Hi %{name}. This is an interpolated message."

      actual = _(key) % { name: "Ronaldinho Gaúcho" }
      expected = "Olá Ronaldinho Gaúcho. Esta mensagem contém interpolações."

      assert_equal expected, actual
    end
  end

  test "it interpolates using options param" do
    localize do
      key = "Hi %{name}. This is an interpolated message."

      actual = _(key, name: "Ronaldinho Gaúcho")
      expected = "Olá Ronaldinho Gaúcho. Esta mensagem contém interpolações."

      assert_equal expected, actual
    end
  end

  test "treats translation as unsafe html by default" do
    localize do
      refute _("Message with HTML").html_safe?
    end
  end

  test "handles strings that include %t or % t" do
    localize do
      expected = "100% to developers"
      actual = _("100% to developers")

      assert_equal expected, actual
    end
  end

  test "handles strings that end in %" do
    localize do
      expected = "50%"
      actual = _("50%")

      assert_equal expected, actual
    end
  end
end
