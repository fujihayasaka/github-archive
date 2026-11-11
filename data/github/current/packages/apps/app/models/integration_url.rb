# typed: true
# frozen_string_literal: true

class IntegrationUrl
  # list of callback url schemes we don't allow
  BLOCKED_SCHEMES = %w(javascript data file ssh).freeze

  # list of valid "http" schemes
  URL_HTTP_SCHEMES = %w(http https).freeze

  # regex pattern for a valid URL scheme
  URL_SCHEME_PATTERN = /\A[a-z][a-z0-9\.\+\-]*\z/i

  # regex pattern for valid userinfo
  URL_USERINFO_PATTERN = /\A[[:graph:]]+\z/

  attr_reader :url, :blocked_schemes, :allowed_schemes,
    :blocked_query_keys, :allow_fragment

  # Public: Creates an instance of IntegratorUrl which can be validated
  # based on its scheme and format.
  #
  # Optionally a list of (dis)allowed schemes may be provided.
  #
  # url - The String url to validate.
  # blocked_schemes - Optional Array of String schemes that are not allowed; all
  # other schemes are allowed.
  # allowed_schemes - Optional Array of String schemes that are allowed; all other
  # schemes are not allowed.
  # blocked_query_keys - Optional Array of String query parameter
  # key names that are reserved and not allowed.
  # allow_fragment - Optional Boolean that determines if the url can contain
  # a fragment.
  #
  # Returns an instance of IntegratorUrl.
  def initialize(url, blocked_schemes: [], allowed_schemes: [],
                 blocked_query_keys: [], allow_fragment: true)
    @url = url
    @blocked_schemes = blocked_schemes
    @allowed_schemes = allowed_schemes
    @blocked_query_keys = blocked_query_keys
    @allow_fragment = allow_fragment
  end

  def self.valid_callback_url?(url, options = {})
    options = options.reverse_merge(
      blocked_schemes: BLOCKED_SCHEMES,
    )
    valid_url?(url, options)
  end

  def self.valid_application_url?(url, options = {})
    options = options.reverse_merge(
      allowed_schemes: URL_HTTP_SCHEMES,
    )
    valid_url?(url, options)
  end

  def self.valid_url?(url, options = {})
    new(url, **options).valid?
  end

  # Public: Does some basic sanity checking for any URL associated with an
  # OAuthApplication using the passed in String.
  #
  # Return a Boolean.
  def valid?
    return false unless url && url.is_a?(String)
    return false unless url.valid_encoding? && uri = Addressable::URI.parse(url)

    absolute_url = uri.absolute?

    valid_scheme = uri.scheme =~ URL_SCHEME_PATTERN &&
      blocked_schemes.exclude?(uri.scheme.downcase) &&
      (allowed_schemes.empty? || allowed_schemes.include?(uri.scheme.downcase))

    valid_userinfo = uri.userinfo.nil? || uri.userinfo =~ URL_USERINFO_PATTERN

    valid_host = if valid_scheme && URL_HTTP_SCHEMES.include?(uri.scheme.downcase)
      UrlHelper.valid_host?(uri.host)
    else
      # Custom schemes often have an empty host (ex some-app:///). Just to be
      # paranoid we won't allow a nil host.
      uri.host == "" || UrlHelper.valid_host?(uri.host)
    end

    valid_query = true
    query_keys = uri.query_values && uri.query_values.keys
    if query_keys
      valid_query = query_keys.none? do |query_key|
        blocked_query_keys.include?(query_key)
      end
    end

    valid_fragment = allow_fragment ? true : uri.fragment.nil?

    valid_url = absolute_url &&
      valid_scheme &&
      valid_userinfo &&
      valid_host &&
      valid_query &&
      valid_fragment

    valid_url
  rescue Addressable::URI::InvalidURIError
    false
  end
end
