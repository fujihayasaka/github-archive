# typed: strict
# frozen_string_literal: true

module Sponsors
  # Public: Represents a sponsorship row for a Bulk Sponsorship.
  #
  # The row can be valid or invalid depending on whether the `amount` and passed in `sponsorable_login`
  # represent a valid sponsors listing that can be sponsored at the given amount.
  class BulkSponsorshipRow
    extend T::Sig
    include GitHub::BatchMethod
    include GitHub::Memoizer

    MAX_INVALID_SPONSORSHIP_AMOUNT_IN_DOLLARS = 99999 # The maximum amount we allow to display for invalid sponsorships

    FormData = T.type_alias { T::Hash[Symbol, T.untyped] }

    # Public: Process user-provided sponsorship amounts. Prefills necessary data to avoid N+1s.
    #
    # This method should almost always be used instead of initializing rows directly with `new` since this method
    # prefills data and limits maximimum number of rows we process at a time.
    #
    # amounts_by_sponsorable_login_array - the maintainers to be sponsored and the USD amount like "2" for $2.00
    # sponsor - who is doing the sponsoring
    # recurring - whether this is for a recurring versus a one-time sponsorship
    sig do
      params(
        amounts_by_sponsorable_login_array: T::Array[{
          sponsorable_login: T.nilable(String),
          amount: T.any(String, Integer, Billing::Money)
        }],
        sponsor: GitHubSponsors::Types::Sponsor,
        recurring: T::Boolean,
      ).returns(T::Array[Sponsors::BulkSponsorshipRow])
    end
    def self.build_rows_from_params(amounts_by_sponsorable_login_array:, sponsor:, recurring:)
      normalized_sponsorable_logins = amounts_by_sponsorable_login_array.map do |element|
        self.normalize_login(element.with_indifferent_access[:sponsorable_login]).downcase
      end
      usage_counts_by_login = normalized_sponsorable_logins.tally

      limited_amounts_by_sponsorable_login = amounts_by_sponsorable_login_array
        .take(Sponsors::BulkSponsorshipValidator::MAX_SPONSORABLES)

      rows = limited_amounts_by_sponsorable_login.map do |element|
        sponsorable_login = element.with_indifferent_access[:sponsorable_login]
        amount = element.with_indifferent_access[:amount]
        normalized_sponsorable_login = normalize_login(sponsorable_login).downcase
        usage_count = usage_counts_by_login[normalized_sponsorable_login] || 0
        is_duplicate = usage_count > 1

        Sponsors::BulkSponsorshipRow.new(
          sponsorable_login: sponsorable_login,
          amount: amount,
          is_duplicate: is_duplicate,
          sponsor: sponsor,
          recurring: recurring,
        )
      end

      prefill_necessary_data(rows)
      rows
    end

    sig { params(login: T.nilable(String)).returns(String) }
    def self.normalize_login(login)
      login ? login.strip.delete_prefix("@") : ""
    end

    # Public: Prefill the data necessary to use methods on this object without N+1 queries.
    sig { params(rows: T::Array[BulkSponsorshipRow]).void }
    def self.prefill_necessary_data(rows)
      GitHub::PrefillAssociations.prefill_batch_method(rows, :approved_sponsors_listing)
      GitHub::PrefillAssociations.prefill_batch_method(rows, :exact_and_lower_price_tiers)
      GitHub::PrefillAssociations.prefill_batch_method(rows, :non_sponsorable_user_or_organization)
      GitHub::PrefillAssociations.prefill_batch_method(rows, :locked_sponsorship?)
      GitHub::PrefillAssociations.prefill_batch_method(rows, :blocked?)
      GitHub::PrefillAssociations.prefill_batch_method(rows, :conflicting_recurring_sponsorship?)
    end

    # Public: Get data for use in generating form fields that will represent the same data as some valid
    # sponsorship rows. Form data will be appropriate for use with bulk_sponsorship_imports#create endpoint.
    #
    # rows - Array of BulkSponsorshipRow objects
    # file_uploaded - whether these rows were provided via a CSV file upload
    #
    # Returns a Hash.
    sig do
      params(
        rows: T::Array[BulkSponsorshipRow],
        file_uploaded: T.nilable(T::Boolean),
        for_checkout: T::Boolean
      ).returns(FormData)
    end
    def self.form_data_for(rows, file_uploaded: false, for_checkout: false)
      valid_sponsorship_rows = rows.select(&:valid?)
      {
        sponsorables: valid_sponsorship_rows.map(&:sponsorable_login),
        bulk_sponsorship: valid_sponsorship_rows.each_with_object({}) do |row, hash|
          value = { amount: row.dollars, amount_with_fee: row.dollars_with_fee }
          value[:include] = 1 if for_checkout

          hash[row.sponsorable_login.downcase] = value
        end,
        file_uploaded: file_uploaded
      }
    end

    # Public: Initialize a BulkSponsorshipRow. Generally you should use `.build_rows_from_params` instead to prefill
    # data and limit the amount of data rows that are allowed at once.
    #
    # sponsorable_login - login of the owner of a SponsorsListing.
    # amount - the amount in USD that the sponsorship should be for, e.g., "2", "$2.00", or "$2" to represent $2 USD
    # is_duplicate - whether the maintainer in this row is a duplicate of another row.
    # sponsor - who is paying for the sponsorship
    # recurring - whether this is for a recurring versus a one-time sponsorship
    sig do
      params(
        sponsorable_login: T.nilable(String),
        amount: T.nilable(T.any(String, Billing::Money, Integer)),
        is_duplicate: T::Boolean,
        sponsor: GitHubSponsors::Types::Sponsor,
        recurring: T::Boolean,
      ).void
    end
    def initialize(sponsorable_login:, amount:, is_duplicate:, sponsor:, recurring:)
      @sponsorable_login = sponsorable_login
      @amount = amount
      @is_duplicate = is_duplicate
      @sponsor = sponsor
      @recurring = recurring
    end

    sig { returns GitHubSponsors::Types::Sponsor }
    attr_reader :sponsor

    delegate :for_organization?, :for_user?, :sponsorable, to: :approved_sponsors_listing, allow_nil: true

    sig { returns T::Boolean }
    def recurring?
      @recurring
    end

    sig { returns T::Boolean }
    def duplicate?
      @is_duplicate
    end

    # Public: Returns an Integer number of US dollars.
    sig { returns Integer }
    def dollars
      amount.dollars.to_i
    end

    # Public: Returns a BigDecimal number of US dollars.
    sig { returns BigDecimal }
    def dollars_with_fee
      BigDecimal(amount_with_fee.dollars)
    end

    sig { returns Billing::Money }
    memoize def amount
      amount_from_import = Billing::Money.parse(@amount)
      max_displayable_amount = Billing::Money.parse(MAX_INVALID_SPONSORSHIP_AMOUNT_IN_DOLLARS)
      if amount_from_import > max_displayable_amount
        max_displayable_amount
      else
        amount_from_import
      end
    end

    sig { returns Billing::Money }
    memoize def amount_with_fee
      amount + Sponsorship.fee_at_sponsorship_payment_time_for(sponsor: sponsor, flat_price: amount)
    end

    sig { returns String }
    memoize def sponsorable_login
      Sponsors::BulkSponsorshipRow.normalize_login(@sponsorable_login)
    end

    sig { returns String }
    memoize def sponsor_login
      Sponsors::BulkSponsorshipRow.normalize_login(sponsor.login)
    end

    # Public: Is there a problem with this bulk sponsorship row that can be fixed by the sponsor?
    sig { returns T::Boolean }
    def has_correctable_error?
      return false if duplicate?
      return false if self_dealing?
      return false if login_missing?
      return false if non_sponsorable?
      return false if locked_sponsorship?
      return false if conflicting_recurring_sponsorship?
      true
    end

    sig { returns T.nilable(GitHubSponsors::Types::Sponsorable) }
    def user_or_organization
      sponsorable || non_sponsorable_user_or_organization
    end

    # Public: Gets an Array of User objects for a login that does not have an approved SponsorsListing.
    #
    # This should be preloaded using .prefill_necessary_data.
    #
    # Returns a User object, or nil if the User/Organization does not exist or the User/Organization doesn't have an
    # approved SponsorsListing.
    batch_method :non_sponsorable_user_or_organization do |rows|
      logins_without_approved_sponsors_listing = rows.reject(&:approved_sponsors_listing).map(&:sponsorable_login)
      users_by_lower_login = User.with_logins(*logins_without_approved_sponsors_listing)
        .index_by { |user| user.login.downcase }

      rows.each_with_object({}) do |row, hash|
        # Downcase the login here to match the downcased Hash key above. That way the case people use in params
        # does not affect whether we can find the user/organization.
        hash[row] = users_by_lower_login[row.sponsorable_login.downcase]
      end
    end

    # Public: Gets the SponsorsListing associated with the sponsorable_login if it is approved.
    #
    # This should be preloaded using .prefill_necessary_data.
    #
    # Returns a SponsorsListing.
    batch_method :approved_sponsors_listing do |rows|
      sponsorable_logins = rows.map(&:sponsorable_login)
      listings_by_lower_login = SponsorsListing
        .with_approved_state
        .with_sponsorable_logins(sponsorable_logins)
        .includes(:sponsorable)
        .select(&:sponsorable) # ensure user still exists
        .index_by { |listing| listing.sponsorable_login.downcase }

      rows.each_with_object({}) do |row, hash|
        # Downcase the login here to match the downcased Hash key above. That way the case people use in params
        # does not affect whether we can find the user/organization.
        hash[row] = listings_by_lower_login[row.sponsorable_login.downcase]
      end
    end

    # Public: Gets an Array of SponsorsTier at the given amount and lower, matching the row's sponsorship frequency.
    #
    # This should be preloaded using .prefill_necessary_data.
    #
    # Returns an Array of SponsorsTier objects.
    batch_method :exact_and_lower_price_tiers do |rows|
      sponsorable_rows = T.let(rows.select(&:approved_sponsors_listing), T::Array[BulkSponsorshipRow])

      tiers = T.let([], T::Array[SponsorsTier])
      base_query = SponsorsTier.with_published_state.joins(:sponsors_listing).highest_monthly_price_first

      if sponsorable_rows.any?
        first_row = T.must(sponsorable_rows.first)
        tiers_query = T.let(base_query
          .for_listing(first_row.approved_sponsors_listing.id)
          .monthly_price_in_dollars_at_most(first_row.dollars)
          .where(frequency: first_row.recurring? ? :recurring : :one_time), ActiveRecord::Relation)

        sponsorable_rows.drop(1).each do |row|
          tiers_query = tiers_query.or(
            base_query
              .for_listing(row.approved_sponsors_listing.id)
              .monthly_price_in_dollars_at_most(row.dollars)
              .where(frequency: row.recurring? ? :recurring : :one_time)
          )
        end

        tiers = tiers_query.to_a
      end

      tiers_by_sponsorable_login = tiers.each_with_object({}) do |tier, hash|
        hash[tier.sponsors_listing_id] ||= []
        hash[tier.sponsors_listing_id] << tier
      end

      rows.each_with_object({}) do |row, hash|
        hash[row] = tiers_by_sponsorable_login[row.approved_sponsors_listing&.id] || []
      end
    end

    # Public: Gets whether the sponsorship is locked because the maintainer has a sponsorship being processed
    #   from the sponsor.
    #
    # This should be preloaded using .prefill_necessary_data.
    #
    # Returns a Boolean.
    batch_method :locked_sponsorship? do |rows|
      sponsorables = rows.map(&:sponsorable)

      # Can use the sponsor from any row because a bulk sponsorship can only
      # be made from a single sponsor at once:
      sponsor = rows.first&.sponsor

      locked_sponsorships_by_sponsorable_id = Sponsorship.from_sponsor(sponsor)
        .with_user_or_org_sponsorable(sponsorables)
        .locked
        .index_by(&:sponsorable_id)

      rows.each_with_object({}) do |row, hash|
        sponsorable_id = row.sponsorable&.id
        locked_sponsorship = locked_sponsorships_by_sponsorable_id[sponsorable_id]
        hash[row] = locked_sponsorship.present?
      end
    end

    # Public: Check whether an existing, active recurring sponsorship exists for the sponsorable and would be replaced
    # by this sponsorship. Only applicable for recurring bulk sponsorship rows.
    #
    # This should be preloaded using .prefill_necessary_data.
    #
    # Returns a Boolean.
    batch_method :conflicting_recurring_sponsorship? do |rows|
      sponsorables = rows.select(&:recurring?).map(&:sponsorable)

      # Can use the sponsor from any row because a bulk sponsorship can only
      # be made from a single sponsor at once:
      sponsor = rows.first&.sponsor

      recurring_sponsorships_by_sponsorable_id = if sponsorables.any?
        Sponsorship.active
          .from_sponsor(sponsor)
          .with_user_or_org_sponsorable(sponsorables)
          .recurring
          .index_by(&:sponsorable_id)
      else
        {}
      end

      rows.each_with_object({}) do |row, hash|
        sponsorable_id = row.sponsorable&.id
        recurring_sponsorship = recurring_sponsorships_by_sponsorable_id[sponsorable_id]
        hash[row] = row.recurring? && recurring_sponsorship.present?
      end
    end

    # Public: Gets whether the sponsor or the sponsorable has blocked the other.
    #
    # This should be preloaded using .prefill_necessary_data.
    #
    # Returns a Boolean.
    batch_method :blocked? do |rows|
      sponsorable_ids = rows.map { |row| row.sponsorable&.id }.compact

      # Can use the sponsor from any row because a bulk sponsorship can only
      # be made from a single sponsor at once:
      sponsor_id = rows.first&.sponsor.id

      ignored_relationships = IgnoredUser.blocking(sponsor_id).blocked_by(sponsorable_ids)
        .or(IgnoredUser.blocking(sponsorable_ids).blocked_by(sponsor_id))

      ignored_relationships_by_sponsorable_id = ignored_relationships.each_with_object({}) do |relationship, hash|
        sponsorable_id = relationship.user_id == sponsor_id ? relationship.ignored_id : relationship.user_id
        hash[sponsorable_id] = relationship
      end

      rows.each_with_object({}) do |row, hash|
        sponsorable_id = row.sponsorable&.id
        hash[row] = sponsorable_id.present? && ignored_relationships_by_sponsorable_id[sponsorable_id].present?
      end
    end

    # Public: Get a published tier that can be used for a one-time payment of the specified maintainer that will
    # be no more than the specified amount. Will return nil when a lesser-value tier exists but the maintainer
    # also allows custom one-time payments, so that you can create a custom SponsorsTier for the exact amount.
    sig { returns T.nilable(SponsorsTier) }
    memoize def published_tier
      tier = exact_and_lower_price_tiers.first

      if tier.nil?
        nil # No valid tier exists
      elsif tier.base_price == amount
        tier # Exact match for desired sponsorship amount
      elsif custom_one_time_payment_allowed?
        nil # Indicate we should create a new custom SponsorsTier for the exact amount
      else
        tier # Selected custom amount is disallowed by the maintainer, so use the closest published tier
      end
    end

    # Public: Get a list of the US dollar values for published tiers the maintainer has that are lower-priced than the
    # bulk sponsorship amount.
    sig { returns T::Array[Integer] }
    def lower_published_tier_amounts
      exact_and_lower_price_tiers
        .select { |tier| tier.to_money < amount }
        .map { |tier| tier.monthly_price_in_dollars.to_i }
    end

    # Public: Can the specified maintainer be sponsored with a one-time payment of the specified amount (either
    # through a new custom tier at that amount or via an existing published tier at that amount) or a lesser
    # amount (via an existing published tier)?
    sig { returns T::Boolean }
    def valid?
      error_message.blank?
    end

    # Public: Is the maintainer trying to sponsor themselves?
    sig { returns T::Boolean }
    memoize def self_dealing?
      sponsor_login.downcase == sponsorable_login.downcase
    end

    # Public: Does the maintainer have a Sponsors listing that cannot be sponsored by the given sponsor?
    sig { returns T::Boolean }
    memoize def non_sponsorable?
      return false if login_missing?
      return true if user_or_organization.nil?
      return true if approved_sponsors_listing.nil?
      return true if blocked?
      false
    end

    # Public: Is the maintainer login present and non-empty?
    sig { returns T::Boolean }
    memoize def login_missing?
      !sponsorable_login.present?
    end

    # Public: Get an error message about the amount for the maintainer.
    #
    # Returns a human-readable error message as a String, or nil if there's no error for the maintainer.
    sig { returns T.nilable(String) }
    memoize def error_message
      message = if self_dealing?
        "You cannot sponsor yourself"
      elsif login_missing?
        "No maintainer username given"
      elsif non_sponsorable?
        "Cannot be sponsored"
      elsif duplicate?
        "Maintainer is listed multiple times"
      elsif locked_sponsorship?
        from_whom = sponsor.organization? ? "@#{sponsor}" : "you"
        "A sponsorship is being processed from #{from_whom} to this maintainer"
      elsif amount_over_limit?
        "Custom amount must be at most #{SponsorsTier::MAX_SPONSORSHIP_AMOUNT_HUMAN}"
      elsif amount_under_minimum?
        self.class.min_custom_amount_error_for(min_amount.dollars)
      elsif conflicting_recurring_sponsorship?
        sponsor_and_verb = sponsor.organization? ? "@#{sponsor} is" : "You are"
        "#{sponsor_and_verb} already sponsoring this maintainer"
      end
    end

    # Public: Get an error message about the minimum custom sponsorship amount not being met.
    #
    # min_custom_amount_in_dollars - amount in US dollars
    sig { params(min_custom_amount_in_dollars: T.any(Integer, BigDecimal)).returns(String) }
    def self.min_custom_amount_error_for(min_custom_amount_in_dollars)
      "Custom amount must be at least $#{min_custom_amount_in_dollars.to_i}"
    end

    # Public: Get the published tier that should be used as the parent tier for the new custom tier that should
    # be made to create a one-time payment for the maintainer.
    #
    # Returns a SponsorsTier or nil, where nil implies it's not necessary to make a new custom tier for the
    # specified maintainer or not allowed.
    sig { returns T.nilable(SponsorsTier) }
    memoize def parent_tier_for_custom_tier
      return unless needs_custom_tier?
      exact_and_lower_price_tiers.first
    end

    # Public: Is the amount for the maintainer more than the maximum sponsorship amount allowed?
    sig { returns T::Boolean }
    def amount_over_limit?
      amount > max_amount
    end

    # Public: Is the amount for the maintainer less than the minimum custom amount allowed?
    sig { returns T::Boolean }
    def amount_under_minimum?
      amount < min_amount
    end

    # Public: Gets the lowest minimum custom amount, or $1.00 if no minimum is set.
    sig { returns Billing::Money }
    def min_amount
      min_amount_in_cents = approved_sponsors_listing&.min_custom_tier_amount_in_cents || 1_00
      Billing::Money.new(min_amount_in_cents)
    end

    private

    delegate :min_custom_tier_amount_in_cents, to: :approved_sponsors_listing

    sig { returns Billing::Money }
    def max_amount
      Billing::Money.parse(SponsorsTier::MAX_SPONSORSHIP_AMOUNT_IN_DOLLARS)
    end

    sig { returns T::Boolean }
    def custom_one_time_payment_allowed?
      if approved_sponsors_listing && amount
        min_custom_tier_amount_in_cents.nil? || min_custom_tier_amount_in_cents <= amount.cents
      else
        false
      end
    end

    sig { returns T::Boolean }
    def needs_custom_tier?
      published_tier.nil? && custom_one_time_payment_allowed?
    end
  end
end
