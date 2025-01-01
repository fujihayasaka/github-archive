# typed: strict
# frozen_string_literal: true

# Non-ActiveRecord model used by Profile#encoded_social_accounts to represent a social media account associated with
# a User.
#
# This is an abstract superclass with a subclass for each recognized account type within the SocialAccounts module,
# including SocialAccounts::Generic as a catch-all.
class SocialAccount
  extend T::Helpers
  abstract!

  MAX_URL_LENGTH = T.let(1024, Integer)

  META_NAME_OVERRIDE = T.let("name_override", String)

  sig { params(url: String, meta: T::Hash[String, String]).void }
  def initialize(url:, meta: {})
    @url = url
    @meta = meta
  end

  sig { returns(String) }
  attr_reader :url

  sig { returns(T::Hash[String, String]) }
  attr_reader :meta

  # Return a String uniquely identifying this social account type. This is used to identify account type when stored
  # in a JSON column and in form submission from the frontend.
  sig { abstract.returns(String) }
  def self.key ; end

  # Return a String used to accessibly describe this account type. This controls how the account type icon is
  # presented to screen readers.
  sig { overridable.returns(String) }
  def self.title
    T.must(T.must(name).split("::").last)
  end

  # Return a String used to describe this account type in a form dropdown. This defaults to #title.
  sig { overridable.returns(String) }
  def self.option
    title
  end

  # Return a Symbol choosing an octicon to use as the visual representation of this account type.
  #
  # Subclasses must override exactly one of #octicon_name and #svg_path.
  #
  # See https://primer.style/octicons/
  sig { overridable.returns(T.nilable(Symbol)) }
  def self.octicon_name
    nil
  end

  # Return a String locating the asset path to the SVG file to use as the visual representation of this account type.
  #
  # Subclasses must override exactly one of #octicon_name and #svg_path.
  sig { overridable.returns(T.nilable(String)) }
  def self.svg_path
    nil
  end

  # Return true if this is the catch-all Generic account type.
  sig { overridable.returns(T::Boolean) }
  def self.generic?
    false
  end

  # Return true only if this account is a recognized Twitter account. Used for special-casing Twitter accounts during
  # double writing.
  sig { overridable.returns(T::Boolean) }
  def self.twitter?
    false
  end

  sig { overridable.returns(T::Boolean) }
  def self.mastodon?
    false
  end

  # Specify the regular expression that may be used to recognize and validate URLs belonging to this account
  # provider.
  sig { params(patterns: Regexp, nodeinfo: T.nilable(String)).void }
  def self.recognize_with(*patterns, nodeinfo: nil)
    # Anchor Ruby regular expressions with \A and \z to avoid erroneous matches on newlines. JavaScript regular
    # expressions do not support \A and \z, so we anchor them with ^ and $ instead. In JavaScript, ^ and $ match
    # string start and end as long as the expression is not in multiline mode, which ours are not.
    az_patterns = patterns.map { |rx| Regexp.new("\\A#{rx.source}\\z", Regexp::IGNORECASE) }
    carat_dollar_patterns = patterns.map { |rx| "^#{rx.source}$" }

    @server_recognition_patterns = T.let(az_patterns, T.nilable(T::Array[Regexp]))
    @client_recognition_patterns = T.let(carat_dollar_patterns, T.nilable(T::Array[String]))
    @nodeinfo_software = T.let(nodeinfo, T.nilable(String))
  end

  # Return the regular expressions used for server-side validation.
  sig { returns(T::Array[Regexp]) }
  def self.server_recognition_patterns
    @server_recognition_patterns || []
  end

  # Return an Array of JavaScript-compatible regular expression sources that can be used by the frontend to
  # automatically recognize URLs. This will be empty if the provider requires a Nodeinfo probe for account
  # recognition.
  sig { overridable.returns(T::Array[String]) }
  def self.js_recognition_patterns
    if needs_nodeinfo_recognition?
      []
    else
      @client_recognition_patterns || []
    end
  end

  # Return the JavaScript-compatible regular expression source that can be used by the frontend to determine if this
  # Nodeinfo-compatible provider is a possible match for a URL.
  sig { returns(T::Array[String]) }
  def self.js_nodeinfo_patterns
    if needs_nodeinfo_recognition?
      @client_recognition_patterns || []
    else
      []
    end
  end

  # Return the name of the software this provider reports in its Nodeinfo protocol response.
  sig { returns(T.nilable(String)) }
  def self.nodeinfo_software
    @nodeinfo_software
  end

  # Return true if this provider is Nodeinfo-compatible and requires server-side recognition.
  sig { returns(T::Boolean) }
  def self.needs_nodeinfo_recognition?
    !nodeinfo_software.nil?
  end

  delegate :key, :title, :option, :server_recognition_patterns,
    :nodeinfo_software, :needs_nodeinfo_recognition?, :octicon_name, :svg_path,
    :generic?, :twitter?, :mastodon?, to: :class

  sig { returns(T.nilable(String)) }
  def name_override
    meta[META_NAME_OVERRIDE]
  end

  # If possible, extract information from the account URL and reformat it to generate a provider-conventional
  # representation of an account. For example, Mastodon accounts are commonly written as `@username@host.com`.
  # If the URL does not follow the expected format, or no such custom exists, return nil.
  sig { overridable.returns(T.nilable(String)) }
  def pretty_account_name
    nil
  end

  # Return detailed match data for the result of applying server-side recognition patterns to the URL, or nil if none
  # are available.
  sig { returns(T.nilable(MatchData)) }
  def url_match
    server_recognition_patterns.each do |rx|
      md = rx.match(url)
      return md if md
    end
    nil
  end

  # Return a conventional representation of this account as derived from its URL if possible. Otherwise, return the
  # URL itself.
  sig { returns(String) }
  def format_account_name
    name_override || pretty_account_name || url
  end

  # Return true if the URL meets our expectations of what a profile URL from this provider should look like.
  #
  # By default, this uses the regular expression provided to the .recognize method to validate the URL. If no such
  # pattern has been defined, we test our ability to extract a "nice" account name from the URL. Subclasses may
  # override to provider arbitrary logic instead if necessary.
  sig { overridable.returns(T::Boolean) }
  def valid?
    if server_recognition_patterns.any?
      server_recognition_patterns.any? { |rx| rx.match?(url) }
    else
      !pretty_account_name.nil?
    end
  end

  # Return true if the URL is too long.
  sig { returns(T::Boolean) }
  def url_too_long?
    url.size > MAX_URL_LENGTH
  end

  # Wrapper struct to hold the results of a call to #recognize.
  class RecognitionResult < T::Struct
    # The new social account. This may be an instance of a different subclass than the caller if further recognition
    # was accomplished, or it may be the caller.
    const :account, SocialAccount

    # If defer_expensive was true, indicate whether or not further background recognition is necessary for this
    # account.
    const :deferred, T::Boolean, default: false

    # If a Nodeinfo probe was performed, the direct Result from that probe.
    const :nodeinfo_probe_result, T.nilable(SocialAccounts::NodeinfoProbe::Result)
  end

  # Trigger server-side recognition of social accounts that the frontend missed and left as #generic? for whatever
  # reason. Return a result containing a possibly new instance of a class in this hierarchy that represents the
  # account, and an indication of whether or not further, more expensive recognition could be helpful.
  #
  # If defer_expensive is false, expensive (network-reliant) recognition techniques will be performed inline.
  sig { overridable.params(defer_expensive: T::Boolean).returns(RecognitionResult) }
  def recognize(defer_expensive:)
    RecognitionResult.new(account: self)
  end

  # Construct a new instance with additional metadata.
  sig { params(metadata: T::Hash[String, String]).returns(T.self_type) }
  def with_meta(metadata)
    self.class.new(url:, meta: meta.merge(metadata))
  end

  # Construct a new instance with an overridden display name.
  sig { params(name: String).returns(T.self_type) }
  def with_name_override(name)
    with_meta(META_NAME_OVERRIDE => name)
  end

  # Extract the hostname from our URL, if present. Returns nil if the URL is invalid.
  sig { returns(T.nilable(String)) }
  def url_host
    URI(url).host
  rescue URI::Error
    nil
  end

  # Convert this account to storage format. A sequence of accounts encoded in this format may be reconstructed by a
  # call to `.extract`.
  sig { returns(T::Hash[String, T.any(String, T::Hash[String, String])]) }
  def encode
    result = { "key" => key, "url" => url }
    result["meta"] = meta if meta.any?
    result
  end

  sig { params(other: T.untyped).returns(T.nilable(T::Boolean)) }
  def ==(other)
    other.is_a?(SocialAccount) && other.key == key && other.url == url
  end

  sig { returns(T.untyped) }
  def hash
    [key, url].hash
  end

  # Register known subclasses here. The order in which they appear will also be used by the frontend.
  KNOWN_PROVIDERS = T.let([
    SocialAccounts::Facebook,
    SocialAccounts::Hometown,
    SocialAccounts::Instagram,
    SocialAccounts::LinkedIn,
    SocialAccounts::Mastodon,
    SocialAccounts::Reddit,
    SocialAccounts::Twitch,
    SocialAccounts::Twitter,
    SocialAccounts::YouTube,
    SocialAccounts::Bluesky,
    SocialAccounts::Generic,
    SocialAccounts::Npm,
  ], T::Array[T.class_of(SocialAccount)])

  PROVIDERS_BY_KEY = T.let(
    KNOWN_PROVIDERS.to_h { |provider| [provider.key, provider] },
    T::Hash[String, T.class_of(SocialAccount)])

  # Return #key values for all known account types.
  sig { returns(T::Enumerable[String]) }
  def self.all_provider_names
    KNOWN_PROVIDERS.map(&:key)
  end

  # Return subclasses for all registered account types.
  sig { returns(T::Enumerable[T.class_of(SocialAccount)]) }
  def self.all_providers
    KNOWN_PROVIDERS
  end

  sig { params(encoded_social_accounts: T.untyped).returns(T::Array[SocialAccount]) }
  def self.extract(encoded_social_accounts)
    return [] if encoded_social_accounts.nil?
    return [] unless encoded_social_accounts.is_a?(Array)

    encoded_social_accounts.filter_map do |account_data|
      next unless account_data.is_a?(Hash)

      key = account_data["key"]
      url = account_data["url"]
      next unless key.is_a?(String) && url.is_a?(String)

      meta = account_data.fetch("meta", {})
      meta = {} unless meta.is_a?(Hash)

      create(key:, url:, meta:)
    end
  end

  sig { params(key: String, url: String, meta: T::Hash[String, String]).returns(SocialAccount) }
  def self.create(key:, url:, meta: {})
    subclass = PROVIDERS_BY_KEY.fetch(key, SocialAccounts::Generic)
    subclass.new(url:, meta:)
  end

  sig { overridable.returns(T.nilable(Symbol)) }
  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
