# typed: strict
# frozen_string_literal: true

# Shared accessor for marketing locale configuration.
# Loads config/localization/marketing_locales.yml once and caches the result.
# To add a new locale, edit config/localization/marketing_locales.yml only.
module MarketingLocales

  STRING_KEYS = T.let(%w[accept_header contentful_locale display_name analytics_label selector_locale].freeze, T::Array[String])
  BOOLEAN_KEYS = T.let(%w[ugct_enabled].freeze, T::Array[String])
  OPTIONAL_STRING_KEYS = T.let(%w[feature_flag].freeze, T::Array[String])
  REQUIRED_KEYS = T.let((STRING_KEYS + BOOLEAN_KEYS).freeze, T::Array[String])

  # Returns the raw hash of locale data keyed by locale short code (String).
  # The returned hash is deep-frozen to prevent accidental mutation of cached data.
  sig { returns(T::Hash[String, T::Hash[String, T.untyped]]) }
  def self.data
    @data ||= T.let(
      begin
        config_root = defined?(Rails) && Rails.respond_to?(:root) && Rails.root ? Rails.root : Pathname.new(File.expand_path("../..", __FILE__))
        config_path = config_root.join("config/localization/marketing_locales.yml")
        parsed = YAML.safe_load(config_path.read)
        raise ArgumentError, "#{config_path}: expected a Hash, got #{parsed.class}" unless parsed.is_a?(Hash)
        raise ArgumentError, "#{config_path}: missing top-level 'locales' key" unless parsed.key?("locales")

        raw = parsed.fetch("locales")
        validate_config!(raw)
        deep_freeze(raw)
      end,
      T.nilable(T::Hash[String, T::Hash[String, T.untyped]]),
    )
  end

  # Returns locale short codes, e.g. ["en", "pt", "es", "ja", "ko"].
  sig { returns(T::Array[String]) }
  def self.available_locales
    @available_locales ||= T.let(data.keys.freeze, T.nilable(T::Array[String]))
  end

  # Returns Accept-Language header values, e.g. ["en-US", "ja", "ko-KR", "pt-BR", "es-419"].
  sig { returns(T::Array[String]) }
  def self.accept_headers
    @accept_headers ||= T.let(
      data.values.map { |v| T.cast(v.fetch("accept_header"), String) }.freeze,
      T.nilable(T::Array[String]),
    )
  end

  # Returns a Symbol-keyed hash mapping locale codes to Contentful locale strings.
  # e.g. { en: "en-US", ja: "ja", ko: "ko-KR", pt: "pt-BR", es: "es-419" }
  sig { returns(T::Hash[Symbol, String]) }
  def self.contentful_mapping
    @contentful_mapping ||= T.let(
      data.each_with_object({}) { |(k, v), h| h[k.to_sym] = T.cast(v.fetch("contentful_locale"), String) }.freeze,
      T.nilable(T::Hash[Symbol, String]),
    )
  end

  # Returns an array of hashes for the locale selector UI.
  # Each hash has :display_name, :selector_locale, and :analytics_label.
  sig { returns(T::Array[{ display_name: String, selector_locale: String, analytics_label: String }]) }
  def self.selector_links
    @selector_links ||= T.let(
      begin
        links = data.values.map do |v|
          { display_name: T.cast(v.fetch("display_name"), String), selector_locale: T.cast(v.fetch("selector_locale"), String), analytics_label: T.cast(v.fetch("analytics_label"), String) }.freeze
        end
        links.freeze
      end,
      T.nilable(T::Array[{ display_name: String, selector_locale: String, analytics_label: String }]),
    )
  end

  # Returns a String-keyed hash mapping short locale codes to accept_header values.
  # e.g. { "en" => "en-US", "ja" => "ja", "ko" => "ko-KR", "pt" => "pt-BR", "es" => "es-419" }
  sig { returns(T::Hash[String, String]) }
  def self.normalize_mapping
    @normalize_mapping ||= T.let(
      data.each_with_object({}) { |(k, v), h| h[k] = T.cast(v.fetch("accept_header"), String) }.freeze,
      T.nilable(T::Hash[String, String]),
    )
  end

  # Returns locale short codes where ugct_enabled is true, e.g. ["en", "ko", "pt", "es"].
  sig { returns(T::Array[String]) }
  def self.ugct_languages
    @ugct_languages ||= T.let(data.select { |_k, v| v["ugct_enabled"] }.keys.freeze, T.nilable(T::Array[String]))
  end

  # Returns whether a locale is enabled for the given user.
  # Locales without a feature_flag are always enabled.
  sig { params(locale_code: String, user: T.untyped).returns(T::Boolean) }
  def self.locale_enabled?(locale_code, user)
    config = data[locale_code]
    return false unless config

    flag = config["feature_flag"]
    return true if flag.nil?

    FeatureFlag.vexi.enabled?(flag.to_sym, user, default: false)
  end

  # Returns selector_links filtered to only locales enabled for the given user.
  sig { params(user: T.untyped).returns(T::Array[{ display_name: String, selector_locale: String, analytics_label: String }]) }
  def self.enabled_selector_links(user)
    data.each_with_object([]) do |(locale_code, v), links|
      next unless locale_enabled?(locale_code, user)

      links << { display_name: T.cast(v.fetch("display_name"), String), selector_locale: T.cast(v.fetch("selector_locale"), String), analytics_label: T.cast(v.fetch("analytics_label"), String) }
    end
  end

  sig { params(raw: T.untyped).void }
  private_class_method def self.validate_config!(raw)
    raise ArgumentError, "marketing_locales.yml: 'locales' must be a Hash, got #{raw.class}" unless raw.is_a?(Hash)
    raise ArgumentError, "marketing_locales.yml: 'en' locale must be present and must be the first entry" unless raw.keys.first == "en"

    raw.each do |locale, config|
      raise ArgumentError, "marketing_locales.yml: locale '#{locale}' must be a Hash, got #{config.class}" unless config.is_a?(Hash)

      REQUIRED_KEYS.each do |key|
        unless config.key?(key)
          raise ArgumentError, "marketing_locales.yml: locale '#{locale}' is missing required key '#{key}'"
        end
      end

      STRING_KEYS.each do |key|
        value = config[key]
        unless value.is_a?(String)
          raise ArgumentError, "marketing_locales.yml: locale '#{locale}' key '#{key}' must be a String, got #{value.class}"
        end
      end

      BOOLEAN_KEYS.each do |key|
        value = config[key]
        unless value == true || value == false
          raise ArgumentError, "marketing_locales.yml: locale '#{locale}' key '#{key}' must be true or false, got #{value.inspect}"
        end
      end

      OPTIONAL_STRING_KEYS.each do |key|
        value = config[key]
        if value && !value.is_a?(String)
          raise ArgumentError, "marketing_locales.yml: locale '#{locale}' key '#{key}' must be a String if present, got #{value.class}"
        end
      end
    end
  end

  # Resets all memoized state. Only for use in tests.
  sig { void }
  def self.reset!
    @data = T.let(nil, T.nilable(T::Hash[String, T::Hash[String, T.untyped]]))
    @available_locales = T.let(nil, T.nilable(T::Array[String]))
    @accept_headers = T.let(nil, T.nilable(T::Array[String]))
    @contentful_mapping = T.let(nil, T.nilable(T::Hash[Symbol, String]))
    @selector_links = T.let(nil, T.nilable(T::Array[{ display_name: String, selector_locale: String, analytics_label: String }]))
    @normalize_mapping = T.let(nil, T.nilable(T::Hash[String, String]))
    @ugct_languages = T.let(nil, T.nilable(T::Array[String]))
  end

  sig { params(obj: T.untyped).returns(T.untyped) }
  private_class_method def self.deep_freeze(obj)
    case obj
    when Hash
      obj.each { |k, v| deep_freeze(k); deep_freeze(v) }
    when Array
      obj.each { |v| deep_freeze(v) }
    end
    obj.freeze
  end
end
