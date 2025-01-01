# typed: true
# frozen_string_literal: true

class FundingLinks
  extend T::Sig
  include EscapeHelper
  include GitHub::Memoizer

  DIRECTORY = ".github"
  FILENAME = "FUNDING.yml"
  PATH = "#{DIRECTORY}/#{FILENAME}"

  # The maximum number of users to show in the funding links modal
  MAX_GITHUB_USER_SPONSORABLES = 4
  # Users can specify 1 organization in FUNDING.yml
  MAX_GITHUB_SPONSORABLES = MAX_GITHUB_USER_SPONSORABLES + 1
  MAX_CUSTOM_URLS = 4

  INVALID_FORMAT_ERROR = "Invalid format provided for '%s'."
  UNKNOWN_PLATFORM_ERROR = "Unknown funding platform '%s'."
  NON_SPONSORABLE_ERROR = "Some users provided are not enrolled in GitHub Sponsors."
  SPONSORABLE_LIMIT_EXCEEDED_ERROR = "You can specify up to 1 organization and #{MAX_GITHUB_USER_SPONSORABLES} users."

  sig { returns FundingLinks }
  def self.empty
    new({})
  end

  sig { params(repository: T.nilable(Repository), blob: T.nilable(String)).returns(FundingLinks) }
  def self.for(repository: nil, blob: nil)
    if repository.present?
      self.new(FundingLinks::FileParser.load(repository, path: FILENAME, directory: DIRECTORY))
    elsif blob.present?
      self.new(FundingLinks::BlobParser.load(blob: blob))
    else
      self.empty
    end
  end

  sig { returns String }
  def self.template
    FundingPlatforms::ALL.values.each_with_object({}) do |platform, structure|
      structure[platform.key.to_s] = platform.template_placeholder
      # YAML is too quick to add unnecessary quotes everywhere so strip these out.
    end.to_yaml
       .gsub(/: "(.*)"/, ": \\1")
       .sub(/---/, "# These are supported funding model platforms\n")
  end

  sig { returns T::Hash[T.any(String, Symbol), T.untyped] }
  attr_reader :config

  sig { params(config: T.untyped).void }
  def initialize(config)
    @config = config.is_a?(Hash) ? config.compact : Hash.new

    # Modify @config hash by limiting the number of "custom" entries
    # to MAX_CUSTOM_URLS
    if @config.has_key?("custom") && @config["custom"].is_a?(Array)
      @config["custom"] = @config["custom"].take(MAX_CUSTOM_URLS)
    end

    @errors = []
  end

  sig { returns T::Boolean }
  def has_multiple_sponsorables_or_external_links?
    sponsorable_ids.size > 1 || external_funding_accounts.any?
  end

  # Public: Get the database IDs for users and organizations specified in the funding file who have a public
  # GitHub Sponsors profile.
  #
  # Returns a sorted Array of Integers in ascending order.
  sig { returns T::Array[Integer] }
  memoize def sponsorable_ids
    result = all_sponsorables.map(&:id).sort

    # First check the size to ensure there are not too many logins.
    if sponsors_logins.size > MAX_GITHUB_SPONSORABLES
      @errors << SPONSORABLE_LIMIT_EXCEEDED_ERROR
    # Then check if the sponsorable ids is smaller. If the sponsorsable_ids is smaller
    # than the login size that means that the at least 1 of the given logins is not sponsorable
    elsif result.size < sponsors_logins.size
      @errors << NON_SPONSORABLE_ERROR
    end

    result
  end

  sig { returns T::Array[String] }
  memoize def sponsorable_users_ids
    sponsorable_users.map(&:global_relay_id)
  end

  sig { returns T.nilable(String) }
  memoize def sponsorable_org_id
    sponsorable_org&.global_relay_id
  end

  # Public: Get the one sponsorable user or organization the file specifies. Returns nil if there is more than one
  # sponsorable user/org in the file.
  sig { returns T.nilable(GitHubSponsors::Types::Sponsorable) }
  def lone_sponsorable
    return if sponsorable_ids.size > 1
    all_sponsorables.first
  end

  # Public: The sponsorable users that can be displayed in the modal.
  sig { returns T::Array[User] }
  memoize def sponsorable_users
    all_sponsorables_by_type[:users]
  end

  # Public: The sponsorable org that can be displayed in the modal.
  sig { returns T.nilable(Organization) }
  def sponsorable_org
    all_sponsorables_by_type[:org]
  end

  sig { returns(T::Hash[T.any(String, Symbol), T.untyped]) }
  memoize def external_funding_config
    config.except(FundingPlatform::GitHub.key.to_s)
  end

  sig { returns T::Hash[T.any(String, Symbol), T.untyped] }
  memoize def external_funding_accounts
    external_funding_config.select do |platform, account|
      unless FundingPlatforms.find(platform).present?
        @errors << UNKNOWN_PLATFORM_ERROR % platform
        next false
      end

      next false unless validate_accounts_for_platform(account, platform)

      true
    end
  end

  sig { returns T::Hash[T.any(String, Symbol), T.untyped] }
  def validated_config
    return {} unless has_valid_platform?
    { github: all_sponsorables.map(&:login) }.merge(external_funding_accounts)
  end

  # True if there is at least one valid funding platform
  sig { returns T::Boolean }
  def has_valid_platform?
    sponsorable_ids.any? || external_funding_accounts.any?
  end

  sig { returns T::Boolean }
  def has_errors?
    errors.any?
  end

  def errors
    run_validations

    @errors
  end

  # Public: Creates a payload for the React view that includes the sponsorable users/orgs and external funding
  # accounts. Also includes any errors that were encountered while parsing the funding file and if the platform is
  # valid.
  #
  # Returns a Hash with all of the information mentioned above.
  sig { returns T::Hash[Symbol, T.untyped] }
  def funding_payload
    external_accounts = []

    external_funding_accounts.each do |name, account|
      Array(account).each do |url_or_account|
        platform = FundingPlatforms.find(name)

        url = platform.url

        if url.present?
          url += url_or_account
        else
          url = url_or_account
        end

        external_accounts << {
          platform: platform,
          link: url
        }
      end
    end

    {
      externalAccounts: external_accounts,
      sponsorableOrg: sponsorable_org&.display_login,
      sponsorableUsers: sponsorable_users.map(&:display_login),
      errors: errors,
      hasValidPlatform: has_valid_platform?,
    }
  end

  private

  # Private: Get a list of the GitHub user and org logins specified in the funding file. They are not necessarily
  # valid logins (the users/orgs might not exist) nor are they necessarily for users/orgs who have public GitHub
  # Sponsors profiles.
  sig { returns T::Array[String] }
  memoize def sponsors_logins
    return [] if config.empty?
    Array(config[FundingPlatform::GitHub.key.to_s]).map(&:to_s)
  end

  memoize def all_sponsorables
    downcased_sponsors_logins = sponsors_logins.map(&:downcase).take(MAX_GITHUB_SPONSORABLES)
    User.sponsorable_users_from_logins(downcased_sponsors_logins)
      .sort_by { |sponsorable| downcased_sponsors_logins.index(sponsorable.login.downcase).to_s }
  end

  sig { returns({ org: T.nilable(Organization), users: T::Array[User] }) }
  memoize def all_sponsorables_by_type
    {
      users: all_sponsorables.select(&:user?).take(MAX_GITHUB_USER_SPONSORABLES),
      org: all_sponsorables.detect(&:organization?),
    }
  end

  # Ensures that funding platforms are validated
  sig { void }
  def run_validations
    sponsorable_ids
    external_funding_accounts
  end

  # Returns true if all accounts pass validation
  #
  # accounts - Either a single string, or an array of strings
  #            representing a funding platform account
  # platform - The name of the platform
  sig { params(accounts: T.untyped, platform: T.any(String, Symbol)).returns(T::Boolean) }
  def validate_accounts_for_platform(accounts, platform)
    custom_key = FundingPlatform::Custom.key.to_s

    # All non-custom platforms must contains a single string value
    if platform != custom_key && !accounts.is_a?(String)
      @errors << INVALID_FORMAT_ERROR % platform
      return false
    end

    Array(accounts).all? do |acc|
      if !acc.is_a?(String)
        @errors << INVALID_FORMAT_ERROR % platform
        next false
      end

      next false unless acc.encoding == Encoding::UTF_8

      if platform == custom_key && safe_uri(acc).blank?
        @errors << INVALID_FORMAT_ERROR % platform
        next false
      end

      true
    end
  end
end
