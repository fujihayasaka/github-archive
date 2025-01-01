# typed: false
# frozen_string_literal: true

class Profile < ApplicationRecord::Domain::Users

  include Spam::Spammable
  include GitHub::Validations

  BIO_MAX_LENGTH = 160
  STRING_ATTRS = [:name, :email, :blog, :company, :location]

  # https://help.twitter.com/en/managing-your-account/twitter-username-rules
  TWITTER_USERNAME_MAX_LENGTH = 15
  TWITTER_USERNAME_FORMAT = /\A\w+\z/

  PRONOUNS_MAX_LENGTH = 48
  PRONOUNS_OPTIONS = %w(
    they/them
    she/her
    he/him
  ).freeze

  MAX_SOCIAL_ACCOUNTS = 4

  include Profile::PinsDependency

  belongs_to :user, touch: true
  has_one :user_status, through: :user
  has_one :sponsors_listing_stafftools_metadata, foreign_key: "sponsorable_id", primary_key: "user_id",
    inverse_of: :sponsorable_profile

  setup_spammable(:user)

  after_commit :enqueue_check_for_spam, if: :persisted?
  after_save :synchronize_search_index
  after_save :instrument_update
  after_save :alert_sponsors_listing_of_profile_change, if: -> { GitHub.sponsors_enabled? }
  after_save :update_business_user_account_profile_name, if: :saved_change_to_name?

  validates *STRING_ATTRS, length: { maximum: 255 }
  validates :email, unicode3: true
  validates :bio, length: { maximum: BIO_MAX_LENGTH }, allow_blank: true
  validates :pronouns, length: { maximum: PRONOUNS_MAX_LENGTH }, allow_nil: true
  validates :mobile_time_zone_name, length: { maximum: 40 } # Longest known value is 28, giving some buffer
  validate :time_zone_has_mapping
  validates :user, presence: true, uniqueness: true
  validate :social_accounts_are_valid

  delegate :hide_from_user?, to: :user

  before_validation :normalize_string_attributes

  attribute :bio, StringFromBinary.new

  # Check the profile for spam
  #
  # options - currently unused
  def check_for_spam(options = {})
    reason = GitHub::SpamChecker.test_profile(self)
    user.safer_mark_as_spammy(reason: reason) if reason
  end

  def synchronize_search_index
    user.synchronize_search_index
  end

  CHANGED_ATTRIBUTES_TO_IGNORE = %w[id created_at updated_at user_id user_hidden]

  # Public: Instrument changes after save.
  def instrument_update
    changed_attribute_names = saved_changes.keys - CHANGED_ATTRIBUTES_TO_IGNORE
    return if changed_attribute_names.empty?

    previous_profile = self.previous_instance

    previous_social_accounts = previous_profile.social_accounts.to_set
    created_social_accounts = social_accounts.reject { |account| previous_social_accounts.delete?(account) }
    destroyed_social_accounts = previous_social_accounts.to_a

    GlobalInstrumenter.instrument "profile.update", {
      actor: user,
      previous_profile: previous_profile,
      current_profile: self,
      changed_attribute_names: changed_attribute_names,
      created_social_accounts: created_social_accounts,
      destroyed_social_accounts: destroyed_social_accounts,
    }
  end

  def normalize_string_attributes
    STRING_ATTRS.each do |field|
      next if self[field].present?

      self[field] = self.class.column_defaults[field.to_s]
    end
  end

  def social_accounts
    # Memoized by hand so we can reset the memoized value with #social_accounts=.
    return @social_accounts unless @social_accounts.nil?
    @social_accounts = SocialAccount.extract(encoded_social_accounts)
  end

  def social_accounts=(accounts)
    self.encoded_social_accounts = accounts.any? ? accounts.map(&:encode) : nil
    @social_accounts = accounts
  end

  def twitter_url
    social_accounts.find(&:twitter?)&.url
  end

  def twitter_username
    social_accounts.find(&:twitter?)&.username
  end

  def twitter_username=(username)
    normalized_username = username&.gsub(/\A@/, "")&.strip
    if normalized_username.blank?
      # Deletion. Delete any Twitter social accounts.
      self.social_accounts = social_accounts.reject(&:twitter?)
    else
      # Addition or update. Mirror the change to the (first) Twitter social account.
      twitter_url = "https://twitter.com/#{normalized_username}"
      twitter_account = SocialAccount.create(key: "twitter", url: twitter_url)

      first_twitter_account = social_accounts.find(&:twitter?)
      if first_twitter_account
        # Update: Modify the first Twitter social account to match the incoming username.
        self.social_accounts = social_accounts.map do |account|
          if account == first_twitter_account
            twitter_account
          else
            account
          end
        end
      elsif social_accounts.size < Profile::MAX_SOCIAL_ACCOUNTS
        # Addition: Add the new Twitter social account to the end of the list.
        self.social_accounts = social_accounts + [twitter_account]
      end
    end
  end

  # Public: Common ActiveRecord validation logic shared between Profile and User to ensure that social accounts
  # are well-formed.
  #
  # model - The ActiveRecord model to attach validation errors to. This is either a Profile or a User.
  # accounts - An Array of social accounts to validate.
  # field - Symbol describing the ActiveRecord field to attach validation errors to.
  def self.social_account_validation(model, accounts, field)
    return if accounts.blank?

    if accounts.size > MAX_SOCIAL_ACCOUNTS
      model.errors.add(field, "cannot have more than #{MAX_SOCIAL_ACCOUNTS} social accounts")
    end

    accounts.select(&:url_too_long?).each do |invalid_account|
      model.errors.add(field, "#{invalid_account.url.first(20)}... is too long")
    end

    accounts.reject(&:valid?).each do |invalid_account|
      model.errors.add(field, "#{invalid_account.url} is not a valid #{invalid_account.title} profile URL")
    end
  end

  def target_for_conditional_access
    user
  end

  private

  def alert_sponsors_listing_of_profile_change
    unless SponsorsListingStafftoolsMetadata.profile_changes_can_affect_has_customized_user_profile?(saved_changes)
      return
    end
    return unless sponsors_listing_stafftools_metadata

    new_value = SponsorsListingStafftoolsMetadata.profile_customized_for_sponsors?(self)
    return if sponsors_listing_stafftools_metadata.has_customized_user_profile? == new_value

    sponsors_listing_stafftools_metadata.update_column(:has_customized_user_profile, new_value)
  end

  def update_business_user_account_profile_name
    return if GitHub.single_business_environment?
    return unless saved_change_to_name?
    # the profile name is not updated when emu users is being provisioned
    return if user.provisioning_an_emu_user

    BusinessUserAccount.where(user_id: self.user_id).update_all(profile_name: self.name)
  end

  def previous_instance
    # .without call to be removed in https://github.com/github/github/pull/262432 when column is properly ignored
    safe_attributes = (attributes.keys & self.class.column_names).without("twitter_username")

    self.class.new(
      attributes.slice(*safe_attributes).merge(saved_changes.transform_values(&:first)),
    ).tap do |instance|
      instance.id = id
      instance.readonly!
    end
  end

  def time_zone_has_mapping
    return if mobile_time_zone_name.nil?

    unless ActiveSupport::TimeZone[mobile_time_zone_name]
      errors.add(:mobile_time_zone_name, "is invalid")
    end
  end

  def social_accounts_are_valid
    self.class.social_account_validation(self, social_accounts, :encoded_social_accounts)
  end

  def reset_memoized_attributes
    @social_accounts = nil
  end
end
