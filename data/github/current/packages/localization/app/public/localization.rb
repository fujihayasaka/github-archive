# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Localization
  MissingTranslationData = Class.new(RuntimeError)

  # Change the locale only within the scope of the &block
  def self.with_locale(locale, &block)
    old_locale = self.locale
    self.locale = locale
    block.call
  ensure
    self.locale = old_locale
  end

  # Change the raise flag only within the scope of the &block
  def self.with_raise_on_missing_translations(new_value = true, &block)
    old_value = raise_on_missing_translations
    self.raise_on_missing_translations = new_value
    block.call
    self.raise_on_missing_translations = old_value
  end

  # Not sure it should belong in this class, but this gives us the ability of
  # testing it more extensively than in the controller
  def self.with_locale_from_http_accept_language_header(header_string, &block)
    AcceptHeaderLocaleResolver.new.resolve(header_string).tap do |locale|
      with_locale(locale, &block)
    end
  end

  # @see FastGettext.with_domain
  def self.with_domain(domain, &block)
    FastGettext.with_domain(domain, &block)
  end

  def self.locale=(locale)
    FastGettext.set_locale(locale)
    I18n.locale = locale
  end

  def self.locale
    I18n.locale
  end

  def self.reset
    self.locale = I18n.default_locale
  end

  # This method is basically the same as the gettext gem `_` helper.
  # The only difference is that it checks whether or not the translation exists.
  # If it does not exist, and Localization.raise_on_missing_translations is on,
  # it will raise a Localization::MissingTranslationData error
  def self._(key, options = {})
    if raise_on_missing_translations && !FastGettext.key_exist?(key)
      raise MissingTranslationData.new("translation missing: #{key}")
    end

    raw_translation_without_interpolation = Object._(key)

    # replace single `%` with `%%`` to appease gettext,
    # ignoring patterns like `%{foo}`
    raw_translation_without_interpolation = raw_translation_without_interpolation
      .gsub("%%", "%")
      .gsub(/(%.?)/) { |x| x.end_with?("{") ? x : "%" + x }

    # This allows placeholders to be replaced with safe html
    if options.delete(:view_context)
      raw_translation_without_interpolation = ERB::Util.html_escape(raw_translation_without_interpolation)
    end

    raw_translation_without_interpolation % options

  # Since this code was written, fast_gettext now does raise an exception like our code does, but it is a different exception.
  # We rely on % not raising an exception as we test that `_(text) % options` works as well as `_(text, **options)`
  # This means that at least for now, we do expect % to not raise an exception as the second example calls % once in this method
  # and the first example above calls it twice (once in this method with nil and again on the result of `_`.
  rescue KeyError
    raw_translation_without_interpolation
  end

  # sets the raise flag
  def self.raise_on_missing_translations=(value)
    @raise_on_missing_translations = value
  end

  # gets the raise flag
  def self.raise_on_missing_translations
    @raise_on_missing_translations ||= false
  end
end
