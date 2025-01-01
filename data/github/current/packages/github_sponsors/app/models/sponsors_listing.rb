# typed: true
# frozen_string_literal: true

class SponsorsListing < ApplicationRecord::Domain::Sponsors
  extend GitHub::Encoding
  force_utf8_encoding :short_description, :featured_description, :full_description, :banned_reason

  include Workflow
  include GitHub::Relay::GlobalIdentification
  include UserHovercard::SubjectDefinition
  include Instrumentation::Model
  include GitHub::Validations
  include SponsorsListing::AbuseDependency
  include SponsorsListing::CustomTierDependency
  include SponsorsListing::FiscalHostDependency
  include SponsorsListing::HovercardDependency
  include SponsorsListing::HydroDependency
  include SponsorsListing::StateDependency
  include SponsorsListing::StripeDependency
  include SponsorsListing::ZuoraDependency

  include Permissions::Attributes::Wrapper
  self.permissions_wrapper_class = Permissions::Attributes::SponsorsListing

  enum :featured_state, {
    disabled: 0, # the owner of the account has not granted permission to be featured
    allowed:  1, # the owner of the account has opted-in to be featured
    active:   2, # this account _is_ featured
  }, prefix: :featured

  MATCHING_LIMIT_AMOUNT_IN_CENTS = 5000_00
  MAX_FULL_DESCRIPTION_LENGTH = 5_000
  PAYOUT_TRANSFER_THRESHOLD = 5000_00
  MAX_FEATURED_DESCRIPTION_LENGTH = 250
  MAX_SHORT_DESCRIPTION_LENGTH = 250
  PAYOUT_PROBATION_DAYS = 60
  MANUAL_PAYOUT_NEW_USER_THRESHOLD = 30.days
  ACCOUNT_AGE_CUTOFF_FOR_AUTO_BAN = 6.months
  MONTHLY_PAYOUT_DAY = 22
  JOINED_WAITLIST_MATCH_DEADLINE = Date.new(2020, 1, 1)
  ACCEPTED_WAITLIST_MATCH_DEADLINE = Date.new(2022, 9, 30)
  DEFAULT_MATCHING_PERIOD_IN_MONTHS = 14
  DEFAULT_MATCHING_PERIOD = DEFAULT_MATCHING_PERIOD_IN_MONTHS.months
  SLUG_PREFIX = "sponsors-"
  SUSPENDED_SPONSORABLE_IDS_BATCH_SIZE = 1000

  SPONSORABLE_FLAG_FILTERS = {
    no_time_zone: "T",
    unsupported_time_zone: "T",
    mismatched_time_zone: "T",
    no_public_non_fork_repos: "R",
    recently_created_github_account: "A",
    uncustomized_github_profile: "P",
  }.freeze
  SPONSORABLE_TIME_ZONE_FLAGS = %i(no_time_zone unsupported_time_zone mismatched_time_zone).freeze

  belongs_to :sponsorable, class_name: "User", required: true, inverse_of: :sponsors_listing
  belongs_to :survey
  belongs_to :contact_email, class_name: "UserEmail"
  belongs_to :created_by, class_name: "User"

  has_one :stafftools_metadata, class_name: :SponsorsListingStafftoolsMetadata, dependent: :destroy
  has_one :sponsors_patreon_user, foreign_key: :user_id, primary_key: :sponsorable_id, inverse_of: :sponsors_listing

  # rubocop:todo Rails/InverseOf
  has_many :sponsorship_match_bans, foreign_key: :sponsorable_id, primary_key: :sponsorable_id, dependent: :destroy
  # rubocop:enable Rails/InverseOf
  has_many :survey_answers,
    ->(listing) { where(user_id: listing.sponsorable_id) },
    through: :survey,
    source: :answers
  has_many :staff_notes, as: :notable, dependent: :destroy
  has_one :active_goal, -> do
    T.bind(self, T.untyped)
    active
  end, class_name: :SponsorsGoal
  has_one :trade_screening_record, through: :sponsorable, disable_joins: true
  has_many :goals, class_name: :SponsorsGoal, dependent: :destroy
  has_many :sponsors_tiers
  has_many :subscription_items, through: :sponsors_tiers, disable_joins: true
  has_many :active_subscription_items, through: :sponsors_tiers,
    disable_joins: true
  has_many :sponsorships, foreign_key: :sponsorable_id, primary_key: :sponsorable_id, inverse_of: :sponsors_listing do
    def ranked(for_user:)
      T.bind(self, T.untyped)
      ranked_by_sponsor(for_user: for_user)
    end
  end
  # rubocop:todo Rails/InverseOf
  has_many :active_sponsorships, -> do
    T.bind(self, T.untyped)
    active
  end, foreign_key: :sponsorable_id, primary_key: :sponsorable_id,
    class_name: :Sponsorship do
    def ranked(for_user:)
      T.bind(self, T.untyped)
      ranked_by_sponsor(for_user: for_user)
    end
  end
  has_many :active_recurring_sponsorships, -> do
    T.bind(self, T.untyped)
    active.recurring
  end, foreign_key: :sponsorable_id, primary_key: :sponsorable_id, class_name: :Sponsorship do
    def ranked(for_user:)
      T.bind(self, T.untyped)
      ranked_by_sponsor(for_user: for_user)
    end
  end
  has_many :activities, class_name: "SponsorsActivity", foreign_key: :sponsorable_id,
    primary_key: :sponsorable_id
  # rubocop:enable Rails/InverseOf
  has_many :invoiced_sponsorship_transfers, inverse_of: :sponsors_listing
  # rubocop:todo Rails/InverseOf
  has_many :newsletters, class_name: "SponsorshipNewsletter", foreign_key: :sponsorable_id,
    primary_key: :sponsorable_id
  # rubocop:enable Rails/InverseOf
  has_many :published_sponsors_tiers, -> do
    T.bind(self, T.untyped)
    with_published_state
  end, class_name: :SponsorsTier
  has_many :retired_sponsors_tiers, -> do
    T.bind(self, T.untyped)
    with_retired_state
  end, class_name: :SponsorsTier
  has_many :featured_items, class_name: :SponsorsListingFeaturedItem, dependent: :destroy
  has_many :fraud_reviews, class_name: "SponsorsFraudReview"
  has_many :featured_users, -> do
    T.bind(self, T.untyped)
    for_users.ordered_by_position
  end, class_name: :SponsorsListingFeaturedItem
  accepts_nested_attributes_for :featured_users, allow_destroy: true, limit: SponsorsListingFeaturedItem::FEATURED_USERS_LIMIT_PER_LISTING
  has_many :featured_repos, -> do
    T.bind(self, T.untyped)
    for_repos.ordered_by_position
  end, class_name: :SponsorsListingFeaturedItem
  accepts_nested_attributes_for :featured_repos, allow_destroy: true, limit: SponsorsListingFeaturedItem::FEATURED_REPOS_LIMIT_PER_LISTING
  has_many :featured_sponsorships, -> do
    T.bind(self, T.untyped)
    for_sponsorships.ordered_by_position
  end, class_name: :SponsorsListingFeaturedItem
  accepts_nested_attributes_for :featured_sponsorships, allow_destroy: true, limit: SponsorsListingFeaturedItem::FEATURED_SPONSORSHIPS_LIMIT_PER_LISTING

  # Public: The listing's default plan, which is any published plan.
  has_one :default_tier, -> do
    T.bind(self, T.untyped)
    with_published_state.order("id ASC")
  end, class_name: :SponsorsTier

  has_many :hooks, as: :installation_target
  destroy_dependents_in_background :hooks

  has_many :sponsors_memberships_criteria,
    class_name: "SponsorsMembershipsCriterion",
    dependent: :destroy,
    autosave: true

  scope :for_tier, ->(sponsors_tier) do
    joins(:sponsors_tiers).where(sponsors_tiers: { id: sponsors_tier })
  end

  scope :with_min_sponsorship_amount_since_last_payout, ->(min_cents) do
    listing_ids = sponsors_listing_ids_with_min_sponsorship_amount_since_last_payout(
      min_cents: min_cents,
      scope: scoped,
    )
    where(id: listing_ids)
  end

  scope :without_fraud_review_since_last_payout, -> do
    conditions = <<~SQL
      sponsors_fraud_reviews.id IS NULL OR
      (
        last_payout_at IS NOT NULL AND
        NOT EXISTS (SELECT 1 FROM sponsors_fraud_reviews WHERE sponsors_fraud_reviews.created_at > last_payout_at)
      )
    SQL
    left_joins(:fraud_reviews).where(conditions).distinct
  end

  scope :without_current_pending_or_flagged_fraud_review, -> do
    left_join_most_recent_fraud_review = <<~SQL
    LEFT JOIN sponsors_fraud_reviews ON sponsors_fraud_reviews.sponsors_listing_id = sponsors_listings.id
      AND sponsors_fraud_reviews.id =
        (
          SELECT MAX(id) FROM sponsors_fraud_reviews fr WHERE fr.sponsors_listing_id = sponsors_listings.id
        )
    SQL
    joins(left_join_most_recent_fraud_review)
      .where("(sponsors_fraud_reviews.id IS NULL OR sponsors_fraud_reviews.state = 1)")
      .distinct
  end

  # Public: Select SponsorsListing for a sponsorable whose login starts with the given query.
  #
  # query - the query string, e.g., "chesh" to match a SponsorsListing with slug="sponsors-cheshire137"
  scope :matches_sponsorable_login, ->(query) do
    if query.present?
      sanitized_slug = sanitize_sql_like(slug_for(query))
      where("sponsors_listings.slug LIKE :sanitized_query", sanitized_query: "#{sanitized_slug}%")
    else
      scoped
    end
  end

  # Public: Select SponsorsListing with a slug, short_description, or full_description that
  # matches a query.
  #
  # query - the query string
  scope :matches_slug_or_description, ->(query) do
    if query.present?
      sanitized_query = "%#{self.sanitize_sql_like(query)}%"

      where(<<-SQL, sanitized_query: sanitized_query)
        sponsors_listings.slug LIKE :sanitized_query OR
        sponsors_listings.short_description LIKE :sanitized_query OR
        sponsors_listings.full_description LIKE :sanitized_query
      SQL
    end
  end

  # Public: Get all listings whose sponsorable has one of the given user/org logins.
  #
  # logins - a String or an Array of String user/organization logins
  #
  # Returns an ActiveRecord::Relation of SponsorsListing.
  scope :with_sponsorable_logins, ->(logins) { with_slug(Array.wrap(logins).map { |login| slug_for(login) }) }

  scope :with_slug, ->(slug) { where(slug: slug) }
  scope :with_slug_like, ->(slug_query) do
    sanitized_query = "#{ActiveRecord::Base.sanitize_sql_like(slug_query.strip)}%"
    where("sponsors_listings.slug LIKE ?", sanitized_query)
  end

  # Public: Filter listings by the login of the sponsorable user or org they're for.
  #
  # query - nil or String; use nil to not filter, pass a String to match the start
  #         of the user or organization's login
  scope :filter_by_sponsorable_login, ->(query) do
    with_slug_like(slug_for(query)) if query.present?
  end

  # Public: Filter listings by billing countries if any filter is given.
  #
  # filter - nil or an Array of Strings; Strings can be two-character country
  #          codes like "US", or "supported" for all supported billing
  #          countries, or "unsupported" for all unsupported billing countries
  scope :filter_by_billing_country, ->(filter) do
    countries = filter&.flatten&.compact

    if countries.present?
      if countries.include?("supported")
        with_supported_billing_country
      elsif countries.include?("unsupported")
        with_unsupported_billing_country
      else
        with_billing_country(countries)
      end
    end
  end

  # Public: Filter listings by countries of residence if any filter is given.
  #
  # filter - nil or an Array of Strings; Strings can be two-character country
  #          codes like "US", or "supported" for all supported countries, or
  #          "unsupported" for all unsupported countries
  scope :filter_by_country_of_residence, ->(filter) do
    countries = filter&.flatten&.compact

    if countries.present?
      if countries.include?("supported")
        with_supported_country_of_residence
      elsif countries.include?("unsupported")
        with_unsupported_country_of_residence
      elsif countries.include?("none")
        with_no_country_of_residence
      else
        with_country_of_residence(countries)
      end
    end
  end

  # Public: Filter listings by flags if any filter is given.
  #
  # filter - nil or an Array of Strings; Strings can be:
  #          * recently_created_github_account
  #          * no_time_zone
  #          * unsupported_time_zone
  #          * mismatched_time_zone
  #          * no_public_non_fork_repos
  #          * uncustomized_github_profile
  scope :filter_by_flags, ->(filter) do
    flags = filter&.flatten&.compact&.map(&:to_sym) || []

    filtered_listings = scoped
    if flags.include?(:recently_created_github_account)
      filtered_listings = filtered_listings.only_newly_created_sponsorables
    end
    if flags.include?(:uncustomized_github_profile)
      filtered_listings = filtered_listings.uncustomized_github_profile
    end
    if flags.include?(:no_time_zone)
      filtered_listings = filtered_listings.without_time_zone
    end
    if flags.include?(:no_public_non_fork_repos)
      filtered_listings = filtered_listings.without_public_non_fork_repository
    end
    if flags.include?(:unsupported_time_zone)
      filtered_listings = filtered_listings.with_unsupported_time_zone
    end
    if flags.include?(:mismatched_time_zone)
      filtered_listings = filtered_listings.mismatched_time_zone
    end
    filtered_listings
  end

  # Public: Filter listings by young github account (>= 60 days ago)
  scope :only_newly_created_sponsorables, -> do
    joins(:stafftools_metadata).merge(SponsorsListingStafftoolsMetadata.newly_created_sponsorables)
  end

  scope :uncustomized_github_profile, -> do
    joins(:stafftools_metadata).merge(SponsorsListingStafftoolsMetadata.uncustomized_github_profile)
  end

  scope :without_time_zone, -> do
    joins(:stafftools_metadata).merge(SponsorsListingStafftoolsMetadata.without_time_zone)
  end

  scope :with_unsupported_time_zone, -> do
    joins(:stafftools_metadata)
      .merge(SponsorsListingStafftoolsMetadata.unsupported_time_zone)
  end

  scope :with_sponsorable_time_zone_and_country_of_residence, ->(country_code) do
    joins(:stafftools_metadata)
      .where(country_of_residence: country_code)
      .merge(SponsorsListingStafftoolsMetadata.with_time_zone_matching_country(country_code))
  end

  scope :without_sponsorable_time_zone_or_country_of_residence, -> do
    joins(:stafftools_metadata)
      .with_no_country_of_residence
      .merge(SponsorsListingStafftoolsMetadata.without_time_zone)
  end

  # Public: Get listings where the country of residence corresponds to the sponsorable's time zone, either because
  # both are unknown, or because the sponsorable's time zone is a valid one for the country of residence.
  scope :sponsorable_time_zone_matches_country_of_residence, -> do
    countries_of_residence = scoped.where.not(country_of_residence: [nil, ""])
      .select(:country_of_residence).distinct.pluck(:country_of_residence)
    if countries_of_residence.any?
      country_code = countries_of_residence.first
      has_matching_country_and_tz = with_sponsorable_time_zone_and_country_of_residence(country_code)

      countries_of_residence.drop(1).each do |country_code|
        has_matching_country_and_tz = has_matching_country_and_tz.or(
          with_sponsorable_time_zone_and_country_of_residence(country_code)
        )
      end

      has_matching_country_and_tz.or(without_sponsorable_time_zone_or_country_of_residence)
    else
      without_sponsorable_time_zone_or_country_of_residence
    end
  end

  # Public: Get listings for user sponsorables where the Sponsors country of residence is unspecifed while we do know
  # the user's time zone, or the user's time zone is not one that exists within their country of residence.
  scope :mismatched_time_zone, -> do
    joins(:stafftools_metadata)
      .where.not(id: sponsorable_time_zone_matches_country_of_residence.select(:id))
      .merge(SponsorsListingStafftoolsMetadata.with_time_zone)
  end

  scope :without_public_non_fork_repository, -> do
    joins(:stafftools_metadata).merge(SponsorsListingStafftoolsMetadata.without_public_non_fork_repository)
  end

  scope :with_supported_billing_country, -> do
    with_billing_country(Billing::StripeConnect::Account.supported_countries)
  end

  scope :with_auto_acceptable_billing_country, -> { with_billing_country(auto_acceptable_countries) }

  scope :with_supported_country_of_residence, -> do
    with_country_of_residence(Billing::StripeConnect::Account.supported_countries)
  end

  scope :with_unsupported_billing_country, -> do
    with_billing_country([nil, ""]).or(
      where.not(billing_country: Billing::StripeConnect::Account.supported_countries)
    )
  end

  scope :with_unsupported_country_of_residence, -> do
    with_country_of_residence([nil, ""]).or(
      where.not(country_of_residence: Billing::StripeConnect::Account.supported_countries)
    )
  end

  scope :with_billing_country, ->(country) { where(billing_country: country) }
  scope :with_no_country_of_residence, -> { with_country_of_residence([nil, ""]) }

  # Public: Filter listings by whether they're for a user or an organization.
  #
  # user_type - nil or String, either "user" or "organization"; use nil to avoid
  #             filtering
  scope :filter_by_user_type, ->(user_type) do
    if user_type
      candidate_user_ids = get_sponsorable_ids_of_type(scoped, user_type: user_type)
      for_sponsorable_user_or_org(candidate_user_ids)
    end
  end

  # Public: Filter listings by whether or not the sponsorable is marked as spammy.
  #
  # spammy - nil, true, or false; nil to skip filtering, true to get only spammy
  #          sponsorable listings, false to get only non-spammy sponsorable
  #          listings
  scope :filter_by_sponsorable_spamminess, ->(spammy) do
    unless spammy.nil?
      if spammy
        spammy_user_ids = get_spammy_sponsorable_ids(scoped)
        for_sponsorable_user_or_org(spammy_user_ids)
      else
        not_spammy
      end
    end
  end

  # Public: Filter listings by whether or not the sponsorable is suspended.
  #
  # suspended - nil, true, or false; nil to skip filtering, true to get only suspended
  #             sponsorable listings, false to get only non-suspended sponsorable
  #             listings
  scope :filter_by_sponsorable_suspendedness, ->(suspended) do
    unless suspended.nil?
      suspended_user_ids = get_suspended_sponsorable_ids(scoped)
      if suspended
        for_sponsorable_user_or_org(suspended_user_ids)
      else
        where.not(sponsorable_id: suspended_user_ids)
      end
    end
  end

  scope :waitlist_queue, -> do
    with_waitlisted_state.not_ignored.oldest_join_date_first
      .not_spammy
      .filter_by_sponsorable_suspendedness(false)
  end

  scope :after_listing, ->(listing_or_id) do
    id = listing_or_id.respond_to?(:id) ? listing_or_id.id : listing_or_id
    where(arel_table[:id].gt(id))
  end

  scope :on_payout_probation, -> {
    where("payout_probation_started_at IS NOT NULL")
      .where("payout_probation_ended_at IS NULL")
  }

  scope :for_sponsorable_user_or_org, ->(ids) do
    if ids.any?
      where(sponsorable_id: ids)
    else
      none
    end
  end

  scope :without_sponsorable_users, ->(ids) { where.not(sponsorable_id: ids) }

  # Public: Sort listings alphabetically by sponsorable login.
  scope :ordered_by_sponsorable_login, -> { order(:slug) }

  # Public: Filter listings by whether they have been ignored or not.
  #
  # ignored_only - nil, true, or false; pass nil to not filter, true to return only
  #                listings that have been ignored, and false to return only
  #                listings that have not been ignored
  scope :filter_by_ignored_status, ->(ignored_only) do
    unless ignored_only.nil?
      ignored_only ? ignored : not_ignored
    end
  end

  scope :ignored, -> { joins(:stafftools_metadata).merge(SponsorsListingStafftoolsMetadata.ignored) }
  scope :not_ignored, -> { joins(:stafftools_metadata).merge(SponsorsListingStafftoolsMetadata.not_ignored) }

  scope :filter_by_user_type, ->(type) do
    if type
      sponsorable_ids = pluck(:sponsorable_id)
      candidate_user_ids = User.where(id: sponsorable_ids, type: type).pluck(:id)

      if candidate_user_ids.any?
        for_sponsorable_user_or_org(candidate_user_ids)
      else
        none
      end
    end
  end

  # Public: Get all listings that have the given country of residence.
  scope :with_country_of_residence, ->(country) { where(country_of_residence: country) }

  # Public: Get all listings that have a country of residence specified that is not the
  # given country. Will exclude listings that have no country of residence at all.
  scope :without_country_of_residence, ->(country) do
    where.not(country_of_residence: [nil, "", country])
  end

  scope :not_spammy, -> { filter_spam_for(nil) }

  # Public: Filter listings so those with spammy sponsorables are excluded. Include
  # this scope last in your query chain so that the smallest possible
  # set of user IDs has to be filtered.
  #
  # viewer - the currently authenticated User; may be nil
  #
  # Returns an ActiveRecord::Relation of SponsorsListing.
  scope :filter_spam_for, ->(viewer) do
    if viewer && viewer.site_admin?
      # Spammy sponsorables can be see by staff, so don't bother filtering
      scoped
    else
      # Works with the already scoped query to further refine it and grab just the
      # sponsorable IDs:
      spammy_sponsorable_ids = get_spammy_sponsorable_ids(scoped)
      spammy_sponsorable_ids -= [viewer.id] if viewer
      where.not(sponsorable_id: spammy_sponsorable_ids)
    end
  end

  scope :featured, -> do
    base_query = with_approved_state.joins(:stafftools_metadata)
    base_query.featured_active.or(base_query.featured_allowed.not_ignored)
  end

  scope :not_featured, -> { where.not(id: featured) }

  scope :filter_by_featured, ->(filter) do
    unless filter.nil? # if explicitly true or false, then apply the filter:
      filter ? featured : not_featured
    end
  end

  scope :filter_by_matchableness, ->(only_matchable) do
    if only_matchable.nil?
      scoped
    elsif only_matchable
      matchable
    else
      not_matchable
    end
  end

  scope :matchable, -> do
    match_enabled
      .accepted_in_match_period
      .published_in_last_year
      .joined_before_match_deadline
      .filter_by_user_type("user")
      .match_limit_not_met
  end

  scope :not_matchable, -> do
    match_disabled
      .or(accepted_after_match_period)
      .or(published_prior_to_this_last_year)
      .or(joined_after_match_deadline)
      .or(filter_by_user_type("organization"))
      .or(match_limit_met)
  end

  scope :match_enabled, -> { where(match_disabled: false) }
  scope :match_disabled, -> { where(match_disabled: true) }

  scope :joined_before_match_deadline, -> { where("joined_at < ?", JOINED_WAITLIST_MATCH_DEADLINE) }
  scope :joined_after_match_deadline, -> { where("joined_at >= ?", JOINED_WAITLIST_MATCH_DEADLINE) }

  scope :published_in_last_year, -> { where("published_at >= ? OR published_at IS NULL", 1.year.ago) }

  scope :accepted_in, ->(time_range) { where(accepted_at: time_range) }

  scope :accepted_in_match_period, -> do
    if in_match_period?
      where("accepted_at IS NOT NULL")
    else
      where("accepted_at > ?", DEFAULT_MATCHING_PERIOD.ago)
    end
  end

  scope :accepted_after_match_period, -> do
    if in_match_period?
      where("accepted_at IS NULL")
    else
      where("accepted_at <= ?", DEFAULT_MATCHING_PERIOD.ago)
    end
  end

  scope :published_prior_to_this_last_year, -> { where("published_at < ?", 1.year.ago) }

  scope :match_limit_met, -> do
    ids = Billing::PayoutsLedgerEntry.sponsors_listing_ids_with_transfer_sum(
      scoped.pluck(:id),
      :gteq,
      MATCHING_LIMIT_AMOUNT_IN_CENTS,
    )

    where(id: ids)
  end

  scope :match_limit_not_met, -> do
    ids = Billing::PayoutsLedgerEntry.sponsors_listing_ids_with_transfer_sum(
      scoped.pluck(:id),
      :lt,
      MATCHING_LIMIT_AMOUNT_IN_CENTS,
    )

    where(id: ids)
  end

  scope :over_transfer_threshold, -> do
    ids = Billing::PayoutsLedgerEntry.sponsors_listing_ids_with_transfer_sum(
      scoped.pluck(:id),
      :gteq,
      PAYOUT_TRANSFER_THRESHOLD,
    )
    where(id: ids)
  end

  before_validation :set_slug
  before_validation :set_joined_at
  before_create :build_manual_criteria

  # Used to perform conditional validations
  attr_accessor :billing_country_validation_enabled, :skip_criteria_creation, :deletion_confirmation

  # NOTE: the order of these two callbacks matter so that orgs with
  #       fiscal hosts have their country of residence set correctly
  before_validation :set_billing_country_based_on_fiscal_host
  before_validation :set_country_of_residence_for_orgs, on: :create

  def self.valid_country_codes
    TradeControls::Countries.currently_unsanctioned.map { |_, alpha2, _| alpha2 }
  end

  validates :sponsorable_id, uniqueness: true
  validates :slug, presence: true, uniqueness: { case_sensitive: false }, unicode3: true
  validates :full_description, presence: true, if: :full_description_required?
  validates :full_description, length: { maximum: MAX_FULL_DESCRIPTION_LENGTH }
  validates :short_description,
    bytesize: {
      maximum: MAX_SHORT_DESCRIPTION_LENGTH,
      message: "is too long (maximum is #{MAX_SHORT_DESCRIPTION_LENGTH} characters)",
    },
    allow_blank: true
  validates :billing_country, inclusion: {
    in: valid_country_codes,
    allow_nil: true,
    message: "is not a valid code",
  }
  validates :country_of_residence, inclusion: {
    in: valid_country_codes,
    allow_nil: true,
    message: "is not a valid code",
  }
  validate :validate_can_be_featured, if: :featured_state_changed?
  validates :featured_description,
    bytesize: {
      maximum: MAX_FEATURED_DESCRIPTION_LENGTH,
      message: "is too long (maximum is #{MAX_FEATURED_DESCRIPTION_LENGTH} characters)",
    },
    allow_blank: true
  validates :country_of_residence, presence: true, on: :create
  validates :joined_at, presence: true
  validates :legal_name, presence: true, if: -> do
    T.bind(self, SponsorsListing)
    legal_name_was.present?
  end
  validates :legal_name, unicode3: true
  validate :billing_country_required
  validate :legal_name_change_permitted
  validate :validate_contact_email, if: :contact_email_id_changed?
  validate :validate_contact_email_verified_if_necessary, if: :contact_email_id_or_state_changed?
  validate :country_of_residence_matches_active_stripe_connect_account_country, on: :update
  validate :billing_country_matches_active_stripe_connect_account_billing_country, on: :update

  delegate :w8_or_w9_verified?, :automated_payouts_disabled?,
    to: :stripe_transfer_account, prefix: :stripe, allow_nil: true

  # Public: Used to specify who is updating the listing.
  sig { params(actor: T.nilable(User)).returns(T.nilable(User)) }
  attr_writer :actor

  sig { returns T.nilable(User) }
  def actor
    return @actor if @actor
    actor_id = GitHub.context[:actor_id]
    if actor_id.present?
      @actor = User.find_by(id: actor_id)
    end
  end

  before_destroy :ensure_deletable
  after_destroy :mark_stripe_accounts_as_deleted
  after_commit :record_match_limit_reached, if: :match_limit_reached_at_previously_changed?
  after_commit :instrument_create, on: :create
  after_commit :instrument_update, on: :update
  after_commit :enqueue_repository_sponsorables_job, on: :destroy, if: :approved?
  after_commit :ensure_fiscal_host_survey_answers, on: [:create, :update]
  after_commit :destroy_unused_tiers, on: :destroy

  alias_attribute :name, :slug
  alias_attribute :owner_id, :sponsorable_id

  sig { returns T.nilable(T.any(User, Organization)) }
  def listable
    sponsorable
  end

  sig { returns T.nilable(T.any(User, Organization)) }
  def owner
    sponsorable
  end

  sig { returns Promise[T.nilable(T.any(User, Organization))] }
  def async_owner
    async_sponsorable
  end

  sig { returns String }
  def to_s
    slug
  end

  # Public: Check if the given URL slug represents a Sponsors listing.
  sig { params(listing_slug: T.nilable(String)).returns(T::Boolean) }
  def self.sponsors_slug?(listing_slug)
    !listing_slug.nil? && listing_slug.start_with?(SLUG_PREFIX)
  end

  # Public: Get a slug to represent a SponsorsListing for a user or organization that has the given username.
  #
  # login - String login (aka username) for a User or Organization that will have a SponsorsListing
  sig { params(login: String).returns(String) }
  def self.slug_for(login)
    "#{SLUG_PREFIX}#{login}"
  end

  # Public: Get a user/organization login from a Sponsors listing slug.
  #
  # slug - String slug for a SponsorsListing, e.g., "sponsors-someCoolMaintainer"
  #
  # Returns a String, e.g., "someCoolMaintainer".
  sig { params(slug: String).returns(String) }
  def self.login_from_slug(slug)
    slug.sub(SLUG_PREFIX, "")
  end

  # Public: Get a URL for a user to contact GitHub support about Sponsors.
  #
  # url_params - optional Hash of URL parameters to include; values do not need to be escaped
  #
  # Returns a String.
  sig { params(url_params: T::Hash[T.untyped, T.untyped]).returns(String) }
  def self.support_url(url_params = {})
    "#{GitHub.contact_support_url}/account?" + url_params.merge(type: "github_sponsors").to_param
  end

  # Public: Get the IDs of Sponsors listings who have received, since their last payout, new
  # sponsorships or existing sponsorship upgrades totalling at least the given amount in cents.
  #
  # min_cents - Integer amount of cents
  # scope - optional ActiveRecord::Relation for SponsorsListing
  #
  # Returns an ActiveRecord::Relation of SponsorsListing selecting particular listing IDs.
  def self.sponsors_listing_ids_with_min_sponsorship_amount_since_last_payout(min_cents:, scope: nil)
    scope ||= SponsorsListing
    scope.joins(sponsors_tiers: :sponsorships)
      .merge(Sponsorship.active.has_subscribable_selected_at.not_invoiced)
      .where("last_payout_at IS NULL OR subscribable_selected_at >= last_payout_at")
      .having("SUM(sponsors_tiers.monthly_price_in_cents) >= ?", min_cents)
      .group(:id)
      .select(:id)
  end

  # Public: Get IDs of users or organizations who are sponsored in the given listings,
  # based on what kind of user-ish, sponsorable record you're looking for.
  #
  # listings - a SponsorsListing ActiveRecord::Relation
  # user_type - either "user" or "organization"
  #
  # Returns an Array of User or Organization IDs.
  def self.get_sponsorable_ids_of_type(listings, user_type:)
    sponsorable_ids = listings.pluck(:sponsorable_id)
    User.where(id: sponsorable_ids, type: user_type).pluck(:id)
  end

  # Public: Get IDs of spammy users and organizations who are sponsored in the given listings.
  #
  # listings - a SponsorsListing ActiveRecord::Relation
  #
  # Returns an Array of User or Organization IDs.
  sig { params(listings: ActiveRecord::Relation).returns(T::Array[Integer]) }
  def self.get_spammy_sponsorable_ids(listings)
    sponsorable_ids = listings.pluck(:sponsorable_id)
    User.where(id: sponsorable_ids).spammy.pluck(:id)
  end

  # Public: Get IDs of suspended users or organizations who are sponsored in the given listings.
  #
  # listings - a SponsorsListing ActiveRecord::Relation
  #
  # Returns an Array of User or Organization IDs.
  sig { params(listings: T.any(ActiveRecord::Relation, T::Array[SponsorsListing])).returns(T::Array[Integer]) }
  def self.get_suspended_sponsorable_ids(listings)
    sponsorable_ids = listings.pluck(:sponsorable_id)

    suspended_sponsorable_ids = Set.new
    sponsorable_ids.each_slice(SUSPENDED_SPONSORABLE_IDS_BATCH_SIZE) do |sponsorable_ids_slice|
      ids = User.where(id: sponsorable_ids_slice).suspended.pluck(:id)
      suspended_sponsorable_ids.merge(ids)
    end

    suspended_sponsorable_ids.to_a
  end

  # Public: Constructs a new instance of SponsorsListing that uses its own bank
  sig { params(attrs: T::Hash[T.untyped, T.untyped]).returns(SponsorsListing) }
  def self.new_with_bank(attrs)
    new(attrs).tap do |listing|
      listing.parent_listing_id = nil
      listing.state = :waitlisted
      listing.billing_country_validation_enabled = true
    end
  end

  # Countries that we can auto accept eligible applicants from.
  sig { returns T::Array[String] }
  def self.auto_acceptable_countries
    Billing::StripeConnect::Account.supported_countries
  end

  # Public: Order listings by when the maintainer signed up for the Sponsors program.
  #
  # sort - either "oldest_first" or "most_recent"
  scope :ordered_by_join_date, ->(sort) do
    if sort == "oldest_first"
      oldest_join_date_first
    else
      most_recent_join_date_first
    end
  end

  scope :oldest_join_date_first, -> { order(joined_at: :asc) }
  scope :most_recent_join_date_first, -> { order(joined_at: :desc) }

  scope :ordered_by_named_sort, ->(sort_by) do
    case sort_by
    when "oldest_first", "most_recent"
      ordered_by_join_date(sort_by)
    when "approval_requested_at"
      ordered_by_approval_requested_at(:asc)
    when "most_recent_approval_requested"
      ordered_by_approval_requested_at(:desc)
    when "most_recent_published"
      order(published_at: :desc)
    when "oldest_published"
      order(:published_at)
    when "most_recent_status_change"
      ordered_by_reviewed_at(:desc)
    when "oldest_status_change"
      ordered_by_reviewed_at(:asc)
    when "newest_account_first"
      ordered_by_user_creation_time(:desc)
    when "oldest_account_first"
      ordered_by_user_creation_time(:asc)
    when "most_recent_payout"
      order(last_payout_at: :desc)
    when "least_recent_payout"
      order(last_payout_at: :asc)
    else
      oldest_join_date_first
    end
  end

  # Public: Sort Sponsors listings by when the sponsorable signed up for GitHub, or when the sponsorable organization
  # was created.
  #
  # direction - :asc or :desc
  #
  # Returns an ActiveRecord::Relation of SponsorsListing.
  scope :ordered_by_user_creation_time, ->(direction) do
    joins(:stafftools_metadata).merge(SponsorsListingStafftoolsMetadata.ordered_by_user_creation_time(direction))
  end

  # Public: Sort listings by when the maintainer requested approval.
  #
  # direction - :asc or :desc
  #
  # Returns an ActiveRecord::Relation of SponsorsListing.
  scope :ordered_by_approval_requested_at, ->(direction) do
    joins(:stafftools_metadata).merge(SponsorsListingStafftoolsMetadata.ordered_by_approval_requested_at(direction))
  end

  # Public: Sort listings by when the state last changed.
  #
  # direction - :asc or :desc
  #
  # Returns an ActiveRecord::Relation of SponsorsListing.
  scope :ordered_by_reviewed_at, ->(direction) do
    joins(:stafftools_metadata).merge(SponsorsListingStafftoolsMetadata.ordered_by_reviewed_at(direction))
  end

  sig { void }
  def reset_memoized_attributes
    super
    remove_instance_variable(:@is_for_organization) if defined?(@is_for_organization)
    remove_instance_variable(:@preferred_currency_code) if defined?(@preferred_currency_code)
    remove_instance_variable(:@total_match_in_cents) if defined?(@total_match_in_cents)
    if defined?(@country_of_residence_flag_emoji_alias)
      remove_instance_variable(:@country_of_residence_flag_emoji_alias)
    end
    remove_instance_variable(:@country_of_residence_name) if defined?(@country_of_residence_name)
    if defined?(@stripe_country_flag_emoji_alias)
      remove_instance_variable(:@stripe_country_flag_emoji_alias)
    end
    remove_instance_variable(:@billing_country_flag_emoji_alias) if defined?(@billing_country_flag_emoji_alias)
    remove_instance_variable(:@fiscally_hosted_project_profile_url) if defined?(@fiscally_hosted_project_profile_url)
  end

  # Public: Returns the combined monthly recurring value in cents of active sponsorships
  # for the Sponsors listing with the given ID. Does not include one-time payments.
  #
  # listing_id - SponsorsListing ID, integer
  sig { params(listing_id: Integer).returns(Integer) }
  def self.subscription_value_for(listing_id)
    sponsorships = Sponsorship.for_listing(listing_id).includes(:tier).recurring.active.paid.select(:subscribable_id)
    sponsorship_tiers = sponsorships.map(&:tier).compact
    sponsorship_tiers.inject(0) do |total, tier|
      total + tier.monthly_price_in_cents
    end
  end

  # Public: Returns the value in cents received for the past 30 days from recurring sponsorships
  # for the Sponsors listing with the given ID. Does not include one-time or prorated payments. Does include
  # sponsorships paid on Patreon.
  #
  # listing_id - SponsorsListing ID, integer
  sig { params(listing_id: Integer).returns(Integer) }
  def self.past_thirty_day_monthly_sponsorship_value_for(listing_id)
    sponsorships = Sponsorship.for_listing(listing_id).recurring.active.paid.to_a
    patreon_sponsorships, non_patreon_sponsorships = sponsorships.partition(&:patreon?)
    tier_ids_and_sponsor_ids = non_patreon_sponsorships.map { |s| [s.subscribable_id, s.sponsor_id] }
    tier_id, sponsor_id = tier_ids_and_sponsor_ids.first
    base_line_item_query = Billing::BillingTransaction::LineItem
    line_items = base_line_item_query.for_subscribable_and_user(tier_id, sponsor_id)
    tier_ids_and_sponsor_ids.drop(1).each do |tier_id, sponsor_id|
      line_items = line_items.or(base_line_item_query.for_subscribable_and_user(tier_id, sponsor_id))
    end
    line_items = line_items.created_during(30.days.ago..).successful
      .sponsorships_excluding_prorated
      .newest_first
      .includes(:billing_transaction)

    tier_id, sponsor_id = tier_ids_and_sponsor_ids.first
    annual_base_line_item_query = Billing::BillingTransaction::LineItem.joins(billing_transaction: :live_user)
    annual_line_items = annual_base_line_item_query.for_subscribable_and_user(tier_id, sponsor_id)
    tier_ids_and_sponsor_ids.drop(1).each do |tier_id, sponsor_id|
      annual_line_items = annual_line_items.or(
        annual_base_line_item_query.for_subscribable_and_user(tier_id, sponsor_id)
      )
    end
    annual_line_items = annual_line_items.created_during(365.days.ago...30.days.ago).successful
      .merge(User.yearly)
      .newest_first
      .includes(:billing_transaction)

    # Only keep most recent line item for each sponsor
    # Get the latest line item for each sponsor; depends on `newest_first` ordering above:
    all_line_items = line_items.to_a + annual_line_items.to_a
    all_line_items = all_line_items.uniq { |item| T.must(item.billing_transaction).user_id }

    tier_ids = (all_line_items.map(&:subscribable_id) + patreon_sponsorships.map(&:subscribable_id)).uniq
    tiers = SponsorsTier.where(id: tier_ids)
    GitHub::PrefillAssociations.prefill_associations(all_line_items, :subscribable, available_records: tiers)
    GitHub::PrefillAssociations.prefill_associations(patreon_sponsorships, :tier, available_records: tiers)

    github_paid_total = all_line_items.inject(0) do |total, line_item|
      # Get monthly price from tier so we don't count whole year amount for the annual sponsors
      line_item_tier = line_item.subscribable
      total + (line_item_tier&.monthly_price_in_cents || 0)
    end

    patreon_paid_total = patreon_sponsorships.inject(0) do |total, sponsorship|
      tier = sponsorship.tier
      total + (tier&.monthly_price_in_cents || 0)
    end

    github_paid_total + patreon_paid_total
  end

  # Public: Returns the login of the sponsorable user or organization this listing represents.
  sig { returns String }
  def sponsorable_login
    return @sponsorable_login if defined?(@sponsorable_login)
    @sponsorable_login = if association(:sponsorable).loaded? && sponsorable
      T.must(sponsorable).login
    else
      self.class.login_from_slug(slug)
    end
  end

  # Public: Indicates if the specified user/org is already sponsoring this listing's sponsorable, and
  # if the currently authenticated user is allowed to know this.
  #
  # sponsor_id - a User or Organization, or their ID
  # viewer - currently authenticated User, if any
  sig { params(sponsor_id: T.any(User, Organization, Integer), viewer: T.nilable(User)).returns(T::Boolean) }
  def sponsor_exists_and_is_visible_to?(sponsor_id, viewer:)
    Platform::Loaders::IsSponsoringCheck
      .load(sponsor_id: sponsor_id, sponsorable_id: sponsorable_id, viewer: viewer)
      .sync
  end

  sig { returns T::Boolean }
  def supports_payout_receipts?
    !uses_fiscal_host?
  end

  # Public: Is the currently authenticated user already sponsoring this account?
  #
  # viewer - currently authenticated User, if any
  #
  # Examples:
  #
  #   # To prevent N+1s when this method is called on a list of SponsorsListing records,
  #   # prefill it this way:
  #
  #   # Execute 1 query to preload (usually in a controller action):
  #   GitHub::PrefillAssociations.prefill_batch_method(sponsors_listings, :sponsored_by_viewer?, current_user)
  #
  #   sponsors_listings.each do |sponsors_listing|
  #     # Method is preloaded and memoized - no queries are executed here!
  #     sponsors_listing.sponsored_by_viewer?(current_user)
  #   end
  #
  # Returns a Boolean.
  batch_method :sponsored_by_viewer? do |listings, viewer|
    next Hash.new(false) unless viewer
    GitHub::PrefillAssociations.prefill_associations(listings, :sponsorable)
    sponsorables = listings.map(&:sponsorable)
    GitHub::PrefillAssociations.prefill_batch_method(sponsorables, :sponsored_by_viewer?, viewer)
    results = sponsorables.map { |s| s.sponsored_by_viewer?(viewer) }
    listings.zip(results).to_h
  end

  # Public: Returns the display name of the maintainer or organization this listing represents.
  sig { returns T.nilable(String) }
  def sponsorable_name
    sponsorable&.safe_profile_name
  end

  sig { returns T.nilable(String) }
  def sponsorable_time_zone_name
    return @sponsorable_time_zone_name if defined?(@sponsorable_time_zone_name)
    @sponsorable_time_zone_name = if association(:sponsorable).loaded? && sponsorable
      T.must(sponsorable).time_zone_name
    else
      stafftools_metadata&.sponsorable_time_zone_name
    end
  end

  # Public: Is this Sponsors listing ready to submit for approval?
  sig { returns T.nilable(T::Boolean) }
  def ready_for_submission?
    full_description.present? &&
      legal_name_present_if_necessary? &&
      contact_email_verified_if_necessary? &&
      billing_country.present? &&
      contact_email_address.present? &&
      !pending_approval? &&
      !requires_additional_review? &&
      (stripe_verified? || uses_fiscal_host?) &&
      sponsorable.present? &&
      !T.must(sponsorable).needs_billing_information? &&
      !T.must(sponsorable).spammy? &&
      stripe_w8_or_w9_verified_if_necessary?
  end

  # Public: For Sponsors listings that are pending approval, the datetime
  # approval was requested, if known.
  sig { returns T.nilable(T.any(DateTime, ActiveSupport::TimeWithZone)) }
  def pending_approval_since
    if (pending_approval? || requires_additional_review? || queued_for_auto_approval?) && persisted?
      stafftools_metadata&.approval_requested_at.presence
    end
  end

  # Public: Is this Sponsors listing ready to be approved?
  sig { returns T::Boolean }
  def ready_for_approval?
    return false unless pending_approval? || requires_additional_review? || queued_for_auto_approval?
    (stripe_verified? && stripe_w8_or_w9_verified?) || uses_fiscal_host?
  end

  sig { returns String }
  def short_description
    super || "Support @#{sponsorable_login}'s open source work on GitHub"
  end

  # Public: Strip trailing whitespaces on setting short_description and sync featured_description.
  sig { params(value: T.nilable(String)).void }
  def short_description=(value)
    if value
      value = value.strip
      self.featured_description = value
      super(value)
    end
  end

  # Public: The contact email address to use for this listing.
  sig { returns Promise[T.nilable(String)] }
  def async_contact_email_address
    async_sponsorable.then do |sponsorable|
      if T.must(sponsorable).organization? && T.must(sponsorable).billing_email.present?
        next T.must(sponsorable).billing_email
      end

      if contact_email_id
        async_contact_email.then do |user_email|
          user_email&.email
        end
      end
    end
  end

  sig { returns T.nilable(String) }
  def contact_email_address
    async_contact_email_address.sync
  end

  # Public: How many open source contributions has this user or org creator
  # made on GitHub?
  #
  # Returns an Integer.
  def public_contribution_count
    return 0 if sponsorable.blank?
    return @public_contribution_count if @public_contribution_count

    contributor = if T.must(sponsorable).user?
      sponsorable
    else
      created_by
    end
    return 0 unless contributor

    @public_contribution_count = contributor.public_contribution_count_for_sponsors
  end

  def published_one_time_tier_count
    published_sponsors_tiers.one_time.count
  end

  def published_recurring_tier_count
    published_sponsors_tiers.recurring.count
  end

  def country_of_residence_name
    @country_of_residence_name ||= Billing::StripeConnect::Account.country_name_for(country_of_residence)
  end

  # Public: Maps two-character country codes to the emoji alias that represents their flag. Only necessary for
  # countries and regions whose emoji alias is not a variation of their country code or name.
  FLAG_EMOJI_ALIAS_BY_COUNTRY_CODE = {
    "AX" => "aland_islands",
    "CC" => "cocos_islands",
    # Map Japan so the Japanese flag is used and not the "japan" emoji, which is the shape of the country:
    "JP" => "jp",
    "SH" => "st_helena",
    "TF" => "french_southern_territories",
    "TR" => "tr", # use flag for Türkiye the country instead of turkey the bird
  }.freeze

  def self.country_flag_emoji_alias_for(country_code)
    return if country_code.blank?

    normalized_country_code = country_code.downcase
    country_name = Billing::StripeConnect::Account.country_name_for(country_code) || ""
    normalized_country_name = country_name.downcase.gsub(/\s+/, "_")
    normalized_country_name_without_join_words = normalized_country_name.gsub(/_and_/, "_")
    explicitly_mapped_alias = FLAG_EMOJI_ALIAS_BY_COUNTRY_CODE[country_code.upcase]

    potential_emoji_aliases = [
      explicitly_mapped_alias,
      normalized_country_name,
      normalized_country_name_without_join_words,
      normalized_country_code,
    ].compact

    potential_emoji_aliases.each do |potential_emoji_alias|
      emoji = Emoji.find_by_alias(potential_emoji_alias)
      return potential_emoji_alias if emoji
    end

    nil
  end

  # Public: Get the emoji alias that represents this listing's maintainer's country of residence.
  #
  # When a non-nil value is returned, it can be used with Emoji#find_by_alias to get a flag's emoji.
  #
  # Returns a String like "us" or "canada", or nil.
  def country_of_residence_flag_emoji_alias
    return @country_of_residence_flag_emoji_alias if defined?(@country_of_residence_flag_emoji_alias)
    @country_of_residence_flag_emoji_alias = if has_country_of_residence?
      self.class.country_flag_emoji_alias_for(country_of_residence)
    end
  end

  def billing_country_flag_emoji_alias
    return @billing_country_flag_emoji_alias if defined?(@billing_country_flag_emoji_alias)
    @billing_country_flag_emoji_alias = if billing_country.present?
      self.class.country_flag_emoji_alias_for(billing_country)
    end
  end

  # Public: Returns an emoji to represent this account's country of residence, e.g., the
  # country's flag.
  def country_of_residence_emoji
    country = country_of_residence
    return unless country.present?

    emoji = Emoji.find_by_alias(country.downcase)
    return emoji if emoji

    full_name = country_of_residence_name
    return unless full_name

    Emoji.find_by_alias(full_name.downcase)
  end

  def full_billing_country
    return unless billing_country
    country_info = Braintree::Address::CountryNames.find do |_, alpha2, _, _|
      alpha2 == billing_country
    end
    TradeControls::Country.from_braintree(country_info).name
  end

  def has_country_of_residence?
    # Set from the active Stripe Connect account's `country` in Sponsors::SyncStripeAccountDetails:
    country_of_residence.present?
  end

  def encourage_setting_country_of_residence?
    return false if has_country_of_residence?

    # We set an organization's country of residence automatically to their billing country:
    return false if for_organization?

    # If they're spammy, disabled, SDN disabled, or banned, we don't care if they haven't set a country
    # of residence:
    draft? || waitlisted? || approved? || pending_approval? || requires_additional_review? || queued_for_auto_approval?
  end

  # Public: Strip carriage returns \r on setting full_description
  def full_description=(value)
    super(remove_windows_line_endings(value)) if value
  end

  def full_description_html(context = {})
    GitHub::Goomba::SponsorsListingPipeline.to_html(full_description, context)
  end

  def short_description_html(context = {})
    GitHub::Goomba::SponsorsListingPipeline.to_html(short_description, context)
  end

  # Public: sets the featured users' position based on the params array index
  def set_featured_users(featured_users_params)
    return true unless sponsorable&.organization?

    set_featured_items(
      items_params: featured_users_params,
      attributes_key: :featured_users,
    )
  end

  # Public: sets the featured repos' position based on the params array index
  def set_featured_repos(featured_repo_ids)
    featured_repos.destroy_all

    featureable_data = featured_repo_ids.map.with_index do |repo_id, index|
      { featureable_id: repo_id, position: index + 1 }
    end
    update("featured_repos_attributes": featureable_data)
  end

  # Public: sets the featured users' position based on the params array index
  def set_featured_sponsorships(featured_sponsorships_params)
    set_featured_items(
      items_params: featured_sponsorships_params,
      attributes_key: :featured_sponsorships,
    )
  end

  # Public: Find a published tier for this Sponsors listing that has the same price and frequency as specified.
  #
  # amount - Integer amount in USD
  # is_recurring - whether the tier is for a recurring sponsorship or a one-time payment
  #
  # Returns a SponsorsTier or nil.
  def colliding_published_tier(amount:, is_recurring:)
    monthly_price_in_cents = amount * 100
    frequency = is_recurring ? :recurring : :one_time
    published_sponsors_tiers.find_by(monthly_price_in_cents: monthly_price_in_cents, frequency: frequency)
  end

  # Public: Is this sponsor listing for a user?
  #
  # Returns a Boolean.
  def for_user?
    !for_organization?
  end

  # Public: Is this listing for an organization that can be sponsored?
  #
  # Returns a Boolean
  def for_organization?
    return @is_for_organization if defined?(@is_for_organization)
    @is_for_organization = sponsorable&.organization?
  end

  def sponsorable_primary_avatar_url(size = nil)
    if association(:sponsorable).loaded?
      sponsorable&.primary_avatar_url(size)
    else
      sponsorable_primary_avatar_path = User.primary_avatar_path_for_user_id(sponsorable_id)
      entity = GitHub.multi_tenant_enterprise? ? sponsorable : nil
      PrimaryAvatar.url_for(sponsorable_primary_avatar_path, size: size, entity: entity)
    end
  end

  # Public: Is this listing in a billable state?
  def billable?
    approved?
  end

  # Public: Check if the given actor has admin access to this listing.
  #
  # user - a User
  #
  # Returns a Promise that resolves to a Boolean.
  def async_adminable_by?(user)
    return Promise.resolve(false) unless user
    Platform::Loaders::Permissions::BatchAuthorize.load(
      action: :edit_sponsors_listing, # See https://github.com/github/authzd/blob/master/config/policies/sponsors.json
      actor: user,
      subject: self,
    ).then { |decision| decision.allow? }
  end

  # Public: Returns true if the given User has admin access to this listing.
  def adminable_by?(user)
    return false unless user
    decision = ::Permissions::Enforcer.authorize(
      action: :edit_sponsors_listing, # See https://github.com/github/authzd/blob/master/config/policies/sponsors.json
      actor: user,
      subject: self,
    )
    decision.allow?
  end

  # Public: Indicates if the listing is readable by an actor.
  #
  # user - a User or nil
  #
  # Returns a Boolean.
  def readable_by?(user)
    decision = ::Permissions::Enforcer.authorize(
      action: :read_sponsors_listing, # See https://github.com/github/authzd/blob/master/config/policies/sponsors.json
      actor: user,
      subject: self,
      context: {
        "user.biztools_user" => user&.biztools_user?,
        "considers_anonymous" => true,
      },
    )
    decision.allow?
  end

  # Public: Indicates if the listing is readable by an actor.
  #
  # user - a User or nil
  #
  # Returns a Promise<Boolean>.
  def async_readable_by?(user)
    Platform::Loaders::Permissions::BatchAuthorize.load(
      action: :read_sponsors_listing, # See https://github.com/github/authzd/blob/master/config/policies/sponsors.json
      actor: user,
      subject: self,
      context: {
        "user.biztools_user" => user&.biztools_user?,
        "considers_anonymous" => true,
      },
    ).then { |decision| decision.allow? }
  end

  # TODO: Need to confirm the logic here. Should we return false on any other states?
  # Public: Returns true if the given User has permission to change the listing.
  def editable_by?(user)
    adminable_by?(user)
  end

  # Public: Does this listing have a published tier? Can optionally check for the existence
  # of a specific tier if a monthly_price_in_cents and/or frequency are passed.
  #
  # monthly_price_in_cents - optional Integer monthly sponsorship amount in cents
  # frequency - optional String/Symbol describing the frequency (e.g. :recurring or :one_time)
  #
  # Returns a Boolean.
  def has_published_tier?(monthly_price_in_cents: nil, frequency: nil)
    tiers = published_sponsors_tiers
    tiers = tiers.where(monthly_price_in_cents: monthly_price_in_cents) if monthly_price_in_cents.present?
    tiers = tiers.where(frequency: frequency) if frequency.present?
    tiers.any?
  end

  # Public: Returns an integer count of how many more tiers can be added
  # to this listing.
  #
  # recurring - Boolean indicating whether you're checking the remaining tier count for recurring
  # tiers (true) or one-time tiers (false)
  #
  # Returns an Integer.
  def remaining_tier_count(recurring:)
    tiers_in_frequency = if recurring
      published_sponsors_tiers.recurring
    else
      published_sponsors_tiers.one_time
    end
    SponsorsTier::PUBLISHED_TIER_LIMIT_PER_FREQUENCY - tiers_in_frequency.count
  end

  # Public: Returns true if this listing has reached the maximum allowed number
  # of published tiers.
  #
  # recurring - Boolean indicating whether you're checking the remaining tier count for recurring
  # tiers (true) or one-time tiers (false)
  #
  # Returns a Boolean.
  def reached_maximum_tier_count?(recurring:)
    remaining_tier_count(recurring: recurring) <= 0
  end

  # Public: Returns the combined monthly recurring value in cents of active sponsorships
  # for this listing.
  #
  # Returns an Integer.
  def subscription_value
    return 0 unless persisted?
    self.class.subscription_value_for(T.must(id))
  end

  # Public: Returns the value in cents received for the past 30 days from recurring sponsorships.
  # Does not include one-time or prorated payments.
  #
  # Returns an Integer.
  def past_thirty_day_monthly_sponsorship_value
    return 0 unless persisted?
    self.class.past_thirty_day_monthly_sponsorship_value_for(T.must(id))
  end

  def enable_sponsors_match!
    update!(match_disabled: false)

    # Audit log
    instrument :enable_match, GitHub.guarded_audit_log_staff_actor_entry(actor)
  end

  def disable_sponsors_match!(reason:)
    transaction do
      update!(match_disabled: true)
      staff_notes.create!(
        note: "Matching was disabled by staff. Reason: #{reason}",
        user: actor,
      )
    end

    payload = GitHub.guarded_audit_log_staff_actor_entry(actor).merge(reason: reason)

    # Audit log
    instrument :disable_match, payload
  end

  # Public: Indicates if this sponsorable is currently within the payout
  #         probation period.
  #
  # Returns a Boolean.
  def on_payout_probation?
    payout_probation_started_at.present? && payout_probation_ended_at.nil?
  end

  # Public: Indicates if the payout probation period has ended for this listing.
  #
  # Returns a Boolean.
  def completed_payout_probation?
    payout_probation_ended_at.present?
  end

  def async_next_payout_date_for(viewer)
    async_adminable_by?(viewer).then do |can_admin|
      async_next_payout_date if can_admin
    end
  end

  def async_next_payout_date
    return Promise.resolve(nil) if payout_probation_started_at.nil?

    latest_payout_date_promise = if on_payout_probation?
      Promise.resolve(nil)
    else
      async_latest_payout_created
    end

    latest_payout_date_promise.then do |latest_payout_created|
      start_date = if on_payout_probation?
        [T.must(payout_probation_started_at) + PAYOUT_PROBATION_DAYS.days, Date.today].max
      else
        latest_payout_date = latest_payout_created
        DateTime.now
      end

      eligible_date = if start_date.day > MONTHLY_PAYOUT_DAY || start_date.month == latest_payout_date&.month
        start_date + 1.month
      else
        start_date
      end

      Date.new(eligible_date.year, eligible_date.month, MONTHLY_PAYOUT_DAY)
    end
  end

  # Public: The next date that this listing can receive a payout.
  #         Is nil if a sponsorable has not yet received a sponsorship.
  #
  # Returns a Date|nil.
  def next_payout_date
    async_next_payout_date.sync
  end

  # Public: The next date that this listing can receive a payout formatted as "month day".
  #         Is nil if a sponsorable has not yet received a sponsorship.
  #
  # Returns a String|nil.
  def next_payout_date_formatted
    return unless next_date = next_payout_date
    next_date.strftime("%B #{next_date.day.ordinalize}")
  end

  def payout_probation_end_date
    return if payout_probation_started_at.nil?
    return payout_probation_ended_at if completed_payout_probation?
    T.must(payout_probation_started_at) + PAYOUT_PROBATION_DAYS.days
  end

  def joined_waitlist_before_match_deadline?
    # `joined_at` is non-null in the database, but we could call this method on an unpersisted SponsorsListing
    # where it's not yet set, so fall back to current time to avoid a nil reference:
    (self[:joined_at] || Time.now).before?(JOINED_WAITLIST_MATCH_DEADLINE)
  end

  def matchable?
    return false unless matchable_when_waitlisted?
    return false if match_disabled?
    return false unless accepted_in_match_period?
    return false unless published_in_last_year?
    !reached_match_limit?
  end

  def reached_match_limit?
    total_match_in_cents >= MATCHING_LIMIT_AMOUNT_IN_CENTS
  end

  def reset_total_match_in_cents!
    @total_match_in_cents = nil
  end

  # Public: Can this listing be approved by an actor?
  #
  # actor - The User that wants to approve the listing.
  #
  # Returns a Boolean.
  def approvable_by?(actor)
    return false if actor.blank?
    return false unless ready_for_approval?

    actor.can_admin_sponsors_listings?
  end

  # Public: Can this listing be unpublished by an actor? Checks permission of
  # the given user and ensures the sponsorable has no active sponsorships so
  # we always cancel those before unpublishing. Does not consider whether the
  # sponsorable has a completed tax form or a balance in Stripe.
  #
  # actor - The User that wants to unpublish the listing.
  #
  # Returns a Boolean.
  def unpublishable_by?(actor)
    return false unless actor.present?
    return false if has_active_subscription_items?
    return false unless can_unpublish?

    actor.can_admin_sponsors_listings?
  end

  # Public: The total monthly income in dollars for this listing's sponsorable.
  #
  # Returns a Billing::Money.
  def total_monthly_pledged_in_dollars
    total_cents = active_recurring_sponsorships.joins(:tier).sum(:monthly_price_in_cents)
    Billing::Money.new(total_cents, Billing::Money.default_currency)
  end

  # Public: Should we allow users to disable this Sponsors listing without any manual
  # checks from GitHub staff?
  #
  # Returns a Boolean.
  def allow_self_service_disable?
    # Unpublishing a Sponsors listing means marking it 'disabled', so make sure
    # we're in the right state to do that.
    return false unless can_disable?

    # If the Sponsors listing is already in 'draft' state, we don't need to worry
    # about the sponsorable's tax form status, etc.
    return true if draft?

    # If the user has been paid out before, we're legally required to keep 30% to give
    # to the government. So don't allow this listing to be unpublished when we have
    # no tax form on file, for auditing purposes.
    return false if stripe_w8_or_w9_verification_required? && !stripe_w8_or_w9_verified?

    # Don't let someone unpublish the listing while there are active sponsorships
    # because we don't want the Sponsors page to just go away without saying something
    # to the sponsors. Could remove this check if we add a mailer such that we tell
    # sponsors "hey the person you were sponsoring unpublished their profile" and
    # also deactivate the sponsorships.
    return false if has_active_subscription_items?

    # Can't allow unpublishing the listing when there's money in Stripe because that
    # money either needs to be refunded to the sponsors or paid out to the
    # sponsorable user/org first.
    return false if has_balance_in_stripe?

    true
  end

  def ignore!(actor:)
    stafftools_metadata&.touch(:ignored_at)

    actor_hash = GitHub.guarded_audit_log_staff_actor_entry(actor)
    instrument :ignore, actor_hash.merge(prefix: :sponsors_membership)
  end

  def unignore!(actor:)
    stafftools_metadata&.update!(ignored_at: nil)

    actor_hash = GitHub.guarded_audit_log_staff_actor_entry(actor)
    instrument :unignore, actor_hash.merge(prefix: :sponsors_membership)
  end

  # Public: Indicates if this listing is eligible to be auto-accepted from state=waitlisted
  # to state=draft.
  #
  # Returns a Boolean.
  def auto_acceptable?
    return false unless SponsorsListing.auto_acceptable_countries.include?(billing_country)
    return false unless SponsorsListing.auto_acceptable_countries.include?(country_of_residence)
    return false if ignored?
    return false unless sponsorable
    return false if T.must(sponsorable).spammy?
    return false if sponsorable_has_any_trade_restrictions?

    for_organization? || !T.must(sponsorable).suspended?
  end

  # Public: Is this listing eligible to be auto approved?
  #
  # Returns a Boolean.
  def auto_approvable?
    if for_user?
      return false if sponsorable_time_zone_name.blank?
      return false unless sponsorable_timezone_matches_country_of_residence?
      return false unless sponsorable_has_customized_user_profile?
    end

    return false if banned?
    return false if full_description.blank?
    return false if uses_fiscal_host?
    return false unless eligible_for_stripe_connect?
    return false unless stripe_verified?
    return false unless stripe_w8_or_w9_verified?
    return false unless sponsorable_github_account_old_enough_for_auto_approval?
    return false unless sponsorable
    return false if T.must(sponsorable).has_sdn_auto_sponsorable_restrictions?

    true
  end

  # Public: Can this listing be in the Sponsors program?
  #
  # Returns a Boolean.
  def eligible_for_sponsors?
    return true if !sponsorable_young_enough_for_auto_ban?
    return true if sponsorable_has_customized_user_profile?
    return true if sponsorable_has_supported_timezone?

    public_contribution_count > 0
  end

  def self.auto_ban_reason
    "Account is less than #{ACCOUNT_AGE_CUTOFF_FOR_AUTO_BAN / 1.month} months old, does not " \
      "have a Sponsors profile description, does not use a supported " \
      "timezone, has not customized their GitHub profile, and has no " \
      "public contributions."
  end

  def self.auto_ban_halt_message
    "Account is not eligible to continue in the Sponsors program."
  end

  def published_in_last_year?
    return true if published_at.nil?
    T.must(published_at) >= 1.year.ago.to_date
  end

  # Public: Are we currently in a period where matching is allowed?
  # By default, all sponsors get 14 months deadline until
  # the matching period ends.
  # From 2021-07-30 to 2022-9-30
  # See more at https://github.com/github/sponsors/issues/2082
  def self.in_match_period?
    Date.current <= ACCEPTED_WAITLIST_MATCH_DEADLINE
  end

  def accepted_in_match_period?
    return false if accepted_at.nil?
    T.must(accepted_at) > DEFAULT_MATCHING_PERIOD.ago || self.class.in_match_period?
  end

  def milestone_email_sent?
    milestone_email_sent_at.present?
  end

  def milestone_email_sent!
    update!(milestone_email_sent_at: Time.zone.now)
  end

  def event_context(prefix: event_prefix)
    {
      prefix => slug,
      "#{prefix}_id".to_sym => id,
    }
  end

  def legal_name_changeable?
    !stripe_w8_or_w9_verified?
  end

  sig { returns(T.nilable(GitHubSponsors::Types::Sponsorable)) }
  def target_for_conditional_access
    sponsorable&.target_for_conditional_access
  end

  sig { returns(Promise[T.nilable(GitHubSponsors::Types::Sponsorable)]) }
  def async_target_for_conditional_access
    async_sponsorable.then do |sponsorable|
      next unless sponsorable.present?
      sponsorable.async_target_for_conditional_access
    end
  end

  # Public: Check if it's safe to call #update_slug on this listing. See
  # https://github.com/github/sponsors/issues/2820#issuecomment-905023761
  #
  # Returns a Boolean.
  def safe_to_update_slug?
    # The transition removed Billing::ProductUUID records for tiers that we’ve retired in Zuora, which happens during
    # migration. If any of a listing's tiers have product UUIDs, it should mean there are unmigrated subscriptions
    # subscribed to those tiers:
    any_tier_product_uuids = ::Billing::ProductUUID.sponsors_tiers.with_product_key(sponsors_tier_ids).any?
    all_subscriptions_migrated = !any_tier_product_uuids

    # It's only safe to do the listing slug rename + Zuora product rename if all the listing's subscriptions have
    # been migrated:
    all_subscriptions_migrated
  end

  def update_slug(new_login:)
    old_slug = slug
    new_slug = self.class.slug_for(new_login)
    return true if old_slug == new_slug

    transaction do
      success = update(slug: new_slug) && update_zuora_product_and_maintainer_name(
        old_slug: old_slug,
        new_slug: new_slug,
        new_login: new_login,
      )
      raise ActiveRecord::Rollback unless success
      success
    end
  end

  # Public: Sponsors listings are deletable if no payments have ever been made and the listing
  # doesn't represent a fiscal host.
  #
  # Returns a Boolean.
  def deletable?
    if fiscal_host?
      fiscal_host_error = "Fiscal host listings can't be deleted (should be disabled)"
      errors.add(:base, fiscal_host_error) unless errors[:base].include?(fiscal_host_error)
    end

    if active_subscription_items.any?
      active_sub_item_error = "Cannot delete Sponsors profile while it has active subscription items."
      errors.add(:base, active_sub_item_error) unless errors[:base].include?(active_sub_item_error)
    end

    if (deletion_confirmation&.downcase != sponsorable_login.downcase) && sponsorships.exists?
      previously_sponsored_error = "@#{sponsorable_login} has received sponsorships. Please confirm their financial " \
        "data from Stripe has been downloaded and github/revenue has saved the data before deleting the Sponsors " \
        "profile."
      errors.add(:base, previously_sponsored_error) unless errors[:base].include?(previously_sponsored_error)
    end

    errors.blank?
  end

  def ignored?
    persisted? && stafftools_metadata&.ignored?
  end

  def reviewed?
    persisted? && stafftools_metadata&.reviewed?
  end

  def sponsorable_has_any_trade_restrictions?
    sponsorable&.has_any_trade_restrictions?
  end

  def sponsorable_trade_screening_status
    sponsorable&.trade_screening_status
  end

  def instrument_auto_payouts_enabled(actor:, reason:)
    metadata = GitHub.guarded_audit_log_staff_actor_entry(actor)
    metadata = metadata.merge({ reason: reason }) if reason.present?
    instrument(:enable_payouts, metadata)
  end

  def instrument_auto_payouts_disabled(actor:, reason:)
    metadata = GitHub.guarded_audit_log_staff_actor_entry(actor)
    metadata = metadata.merge({ reason: reason }) if reason.present?
    instrument(:disable_payouts, metadata)
  end

  # Public: e-mail sponsors that this listing is no longer sponsorable
  #
  # sponsorships - Sponsorships where the sponsor will be notified
  #
  # Returns nothing
  def email_sponsors_no_longer_sponsorable(sponsorships)
    GitHub::PrefillAssociations.prefill_associations(sponsorships, [:sponsor, :tier])

    sponsorships.each do |sponsorship|
      sponsor = sponsorship.sponsor
      tier = sponsorship.tier
      SponsorsPrimerMailer.sponsorable_no_longer_sponsorable(
        sponsorable: sponsorable,
        sponsor: sponsor,
        tier: tier,
      ).deliver_later
    end
  end

  # Public: Update settings for past sponsorships visibility.
  #
  # hidden - Boolean describing whether past sponsorships should be hidden on the profile
  #
  # Returns nothing.
  def update_past_sponsorships_visibility!(hidden: false)
    sponsorable_settings.set!(:hide_past_sponsorships_on_sponsor_listing, hidden)
  end

  # Public: Should past sponsorships be hidden on the maintainer's profile?
  #
  # Returns a Boolean.
  def hide_past_sponsorships?
    sponsorable_settings.get(:hide_past_sponsorships_on_sponsor_listing)
  end

  # Public: Set featured sponsorship settings. Updates sponsorable's User Settings
  sig { params(enabled: T::Boolean, automatic: T::Boolean).void }
  def update_featured_sponsorships_settings(enabled: false, automatic: false)
    updated_settings = SponsorsFeaturedSponsorshipsSettings.new(bitmask: nil)
    updated_settings.enable if enabled
    updated_settings.automatic if automatic
    sponsorable_settings.set!(:sponsors_featured_sponsorships_settings, updated_settings.bitmask)
  end

  # Public: Get featured sponsorship settings for this sponsors listing
  sig { returns(SponsorsFeaturedSponsorshipsSettings) }
  def featured_sponsorships_settings
    bitmask = sponsorable_settings.get(:sponsors_featured_sponsorships_settings)
    SponsorsFeaturedSponsorshipsSettings.new(bitmask: bitmask)
  end

  # Public: Get sponsors email opt out settings for this sponsors listing
  sig { returns(SponsorsEmailOptOuts) }
  def email_opt_outs
    bitmask = sponsorable_settings.get(:sponsors_email_opt_outs)
    SponsorsEmailOptOuts.new(bitmask: bitmask)
  end

  # Public: Set sponsors email opt out settings. Updates sponsorable's User Settings
  sig { params(email_opt_outs: SponsorsEmailOptOuts).void }
  def update_email_opt_outs(email_opt_outs)
    sponsorable_settings.set!(:sponsors_email_opt_outs, email_opt_outs.bitmask)
  end

  # Public: Does the given amount in US cents meet or exceed any minimum required custom amount the maintainer of this
  # Sponsors profile has?
  sig { params(amount_in_cents: Integer).returns(T::Boolean) }
  def amount_meets_required_minimum?(amount_in_cents)
    min_cents = [min_custom_tier_amount_in_cents, SponsorsTier::MIN_PRICE_IN_CENTS].compact.max
    amount_in_cents >= T.must(min_cents)
  end

  sig { params(amount_in_cents: Integer).returns(T::Boolean) }
  def has_published_recurring_tier_with_monthly_price?(amount_in_cents)
    published_sponsors_tiers.recurring.with_monthly_price_in_cents(amount_in_cents).exists?
  end

  sig { returns Billing::Money }
  def min_custom_tier_amount_money
    return Billing::Money.zero unless min_custom_tier_amount_in_cents
    Billing::Money.new(min_custom_tier_amount_in_cents)
  end

  # Public: Enqueue a background job to sync our data with Patreon's for the maintainer of this Sponsors profile.
  sig { void }
  def sync_sponsors_patreon_user
    spu = sponsors_patreon_user
    if spu
      spu.actor = actor
      spu.sync_sponsors_patreon_user
    end
  end

  # Public: Does this listing have a sponsorable that's been flagged as potentially abusive?
  sig { returns T.nilable(T::Boolean) }
  def flagged_sponsorable?
    sponsorable&.spammy? || sponsorable&.suspended?
  end

  # Public: Serialize the listing data for use in the sponsors-signup react partial
  def serialize_for_signup
    {
      isWaitlisted: waitlisted?,
      contactEmail: contact_email_address,
      countryOfResidence: country_of_residence,
      billingCountry: billing_country,
      usesFiscalHost: uses_fiscal_host?,
      signupStatusPartialPath: UrlHelpers.sponsorable_signup_status_path(sponsorable_login),
    }
  end

  private

  delegate :w8_or_w9_verification_required?,
    to: :stripe_transfer_account, prefix: :stripe, allow_nil: true

  def stripe_w8_or_w9_verified_if_necessary?
    return true unless stripe_w8_or_w9_verification_required?
    stripe_w8_or_w9_verified? || uses_fiscal_host?
  end

  def enqueue_repository_sponsorables_job
    UpdateOwnerRepositorySponsorablesJob.perform_later(sponsorable_id: sponsorable_id)
  end

  def destroy_unused_tiers
    # If it's ever been used in a subscription item, whether that item is still active or not, we don't want to
    # delete it for billing history purposes:
    used_tier_ids = Billing::SubscriptionItem.for_sponsors_listing(id).distinct.pluck(:subscribable_id).to_set

    # If it's used in any sponsorships currently, whether they're active or not, we don't want to delete it:
    used_tier_ids.merge(Sponsorship.for_listing(id).distinct.paid.pluck(:subscribable_id).to_set)

    # If the tier was referenced in a SponsorsActivity, we will show it on sponsorship log pages and in the API
    # to provide historical context on tier changes, so we shouldn't delete:
    tier_ids_for_listing_activities = SponsorsActivity.for_sponsorable(sponsorable_id)
      .pluck(:sponsors_tier_id, :old_sponsors_tier_id).flatten.compact.to_set
    used_tier_ids.merge(tier_ids_for_listing_activities)

    # If it's mentioned in a SponsorshipNewsletterTier, it's in use because we don't delete SponsorshipNewsletter
    # records upon deleting the SponsorsListing:
    used_tier_ids.merge(SponsorshipNewsletterTier.joins(:sponsorship_newsletter)
      .merge(SponsorshipNewsletter.for_sponsorable(sponsorable_id)).distinct.pluck(:sponsors_tier_id).compact)

    sponsors_tiers.where.not(id: used_tier_ids).destroy_all
  end

  def contact_email_id_or_state_changed?
    contact_email_id_changed? || state_changed?
  end

  def legal_name_present_if_necessary?
    legal_name.present? ||
      for_organization? ||
      stripe_w8_or_w9_verification_required?
  end

  def contact_email_verified_if_necessary?
    # No contact_email_id required for orgs
    return true if for_organization?

    contact_email&.verified?
  end

  def ensure_deletable
    throw(:abort) unless deletable?
  end

  def set_joined_at
    if self[:joined_at].nil?
      self.joined_at = created_at || Time.current
    end
  end

  sig { params(automated: T::Boolean).void }
  def instrument_acceptance(automated:)
    GitHub.dogstats.increment("sponsors_membership.accept", tags: ["automated:#{automated}"])

    # Audit log
    actor_context = GitHub.guarded_audit_log_staff_actor_entry(actor)
    instrument :accept, actor_context.merge(automated: automated, prefix: :sponsors_membership)
  end

  def set_country_of_residence_for_orgs
    return unless for_organization?
    self.country_of_residence = self.billing_country
  end

  # Private: Builds the manual criteria records when creating a listing.
  #
  # Returns nothing.
  def build_manual_criteria
    return if skip_criteria_creation
    criteria = T.unsafe(SponsorsCriterion.for(sponsorable)).manual

    criteria.each do |criterion|
      self.sponsors_memberships_criteria.build(
        sponsors_criterion: criterion,
        sponsors_listing: self,
      )
    end
  end

  def full_description_required?
    return false if draft? || waitlisted? || banned? || disabled?
    true
  end

  def legal_name_change_permitted
    return if new_record? || !legal_name_changed? || legal_name_changeable?
    errors.add(:legal_name, "cannot be changed")
  end

  # Private: Used during state transition to ensure orgs have a supported country
  def country_supported?
    return true if sponsorable&.user?
    eligible_for_stripe_connect?
  end

  def validate_can_be_featured
    return unless featured_active?
    return if featured_state_was == "allowed" || new_record?
    errors.add(:base, "cannot be featured without the owner's approval")
  end

  def billing_country_required
    return unless billing_country_validation_enabled
    errors.add(:billing_country, "must be provided") if billing_country.blank?
  end

  def validate_contact_email_verified_if_necessary
    return unless contact_email && sponsorable
    return if for_organization?

    return unless approved? || pending_approval? || requires_additional_review? || queued_for_auto_approval?

    unless T.must(contact_email).verified?
      errors.add(:contact_email, "must be verified")
    end
  end

  def validate_contact_email
    return unless contact_email_id
    return if sponsorable.blank?

    if T.must(sponsorable).organization?
      errors.add(:contact_email, "must not be set for a sponsorable organization")
      return
    end

    valid_email_ids = T.must(sponsorable).emails.user_entered_emails.pluck(:id)
    unless valid_email_ids.include?(contact_email_id)
      errors.add(:contact_email, "is invalid for sponsorable")
    end
  end

  def country_of_residence_matches_active_stripe_connect_account_country
    return unless active_stripe_connect_account
    return if stripe_country.blank?

    normalized_stripe_country = stripe_country&.upcase
    normalized_listing_country = country_of_residence&.upcase
    unless normalized_stripe_country == normalized_listing_country
      errors.add(:country_of_residence, "(#{normalized_listing_country}) must match the active Stripe Connect " \
        "account's country or region (#{normalized_stripe_country})")
    end
  end

  def billing_country_matches_active_stripe_connect_account_billing_country
    return unless active_stripe_connect_account

    stripe_billing_country = T.must(active_stripe_connect_account).billing_country
    return if stripe_billing_country.blank?

    normalized_stripe_country = stripe_billing_country.upcase
    normalized_listing_country = billing_country&.upcase
    unless normalized_stripe_country == normalized_listing_country
      errors.add(:billing_country, "(#{normalized_listing_country}) must match the active Stripe Connect " \
        "account's billing country or region (#{normalized_stripe_country})")
    end
  end

  def instrument_create
    # Audit log
    instrument(:waitlist_join, prefix: :sponsors)
    instrument(:sponsored_developer_create, prefix: :sponsors)

    # Hydro
    GlobalInstrumenter.instrument("sponsors.waitlist_join", user: sponsorable)
    GlobalInstrumenter.instrument("sponsors.listing_state_change",
      user: sponsorable,
      action: :CREATED,
    )
  end

  def instrument_update
    # Audit log
    instrument(:sponsored_developer_profile_update, prefix: :sponsors,
      full_description: full_description, actor: actor)

    # Hydro
    GlobalInstrumenter.instrument("sponsors.sponsored_developer_profile_update",
      actor: actor,
      sponsorable: sponsorable,
      full_description: full_description,
      listing: self,
      listing_stafftools_metadata: stafftools_metadata,
      stripe_connect_account: active_stripe_connect_account,
    )
  end

  def has_active_subscription_items?
    subscription_items.active.exists?
  end

  # Private: Check if a Sponsors listing can be in the sdn_disabled state
  def sdn_disable_sponsors_listings_enabled?
    return false unless for_user?
    GitHub.flipper[:live_sdn_screening].enabled?(sponsorable)
  end

  # Private: Emit metrics for auto-approval
  #
  # success - Boolean describing auto-approval success
  #
  # Returns nothing.
  def instrument_auto_approval(success:)
    tags = ["success:#{!!success}"]
    GitHub.dogstats.increment("sponsors_listing.auto_approval", tags: tags)
    nil
  end

  sig { params(automated: T::Boolean).void }
  def instrument_approval(automated:)
    # Datadog
    instrument_auto_approval(success: true) if automated

    # Audit log
    context = {
      automated: automated,
      prefix: :sponsors,
    }.merge(GitHub.guarded_audit_log_staff_actor_entry(actor))
    instrument :sponsored_developer_approve, context

    # Hydro
    GlobalInstrumenter.instrument("sponsors.listing_state_change",
      action: "APPROVED",
      user: sponsorable,
      listing: self,
      listing_stafftools_metadata: self.stafftools_metadata,
      automated: automated
    )
  end

  def event_prefix() :sponsors_listing end

  def event_payload
    payload = {
      event_prefix => self,
      :state => current_state_name,
      :short_description => short_description,
    }
    payload[:created_by] = created_by if created_by
    payload.merge!(T.must(sponsorable).event_context) if sponsorable
    payload
  end

  # Internal: Set the slug based on sponsorable's login. This is assuming sponsorable is a User.
  #
  # Returns the slug that was set, or nil if slug was set to nil or not set.
  def set_slug
    return unless slug.blank?

    if sponsorable.nil?
      self.slug = ""
    elsif slug.blank? && sponsorable
      self.slug = self.class.slug_for(T.must(sponsorable).login)
    end
  end

  # Internal: Replaces any instances of \r\n with \n.
  # Need to do this because forms POST with \r\n and it breaks our character counts.
  #
  # string
  #
  # Returns filtered string.
  def remove_windows_line_endings(value)
    value.gsub("\r\n", "\n")
  end

  # Internal: Sets featured items based on their type and ordered by the array index.
  #
  # Returns true if it's successful, false otherwise.
  def set_featured_items(items_params: [], attributes_key:)
    to_remove = items_params.select { |item| item[:_destroy] }
    to_set = items_params.map(&:to_h) - to_remove.map(&:to_h)

    if to_remove.present?
      return false unless update("#{attributes_key}_attributes": to_remove)
    end

    items_params = Array(to_set).map.with_index do |params, index|
      params.merge(position: index + 1)
    end

    update("#{attributes_key}_attributes": items_params)
  end

  def record_match_limit_reached
    return if match_limit_reached_at.blank?

    # Hydro
    GlobalInstrumenter.instrument("sponsors.sponsors_listing_match_limit_reached", {
      listing: self,
    })

    return if email_opt_outs.opted_out_of_all? || email_opt_outs.opted_out_of_reached_match_cap?

    SponsorsPrimerMailer.reached_match_cap(sponsorable: sponsorable).deliver_later
  end

  # Private: Is this user matchable based on the date they signed up for the waitlist?
  #
  # This doesn't mean the user is still eligible to be matched, just that they
  # were eligible to be matched based on the date they signed up for the waitlist.
  sig { returns T.nilable(T::Boolean) }
  def matchable_when_waitlisted?
    sponsorable&.user? && joined_waitlist_before_match_deadline?
  end

  # Private: The user settings for the maintainer of this profile
  sig { returns SettingsCollection::Mixin }
  def sponsorable_settings
    user_settings = sponsorable ? T.must(sponsorable).settings : UserSettings.new
    T.let(user_settings, SettingsCollection::Mixin)
  end
end
