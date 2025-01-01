# typed: strict
# frozen_string_literal: true

class SponsorsListing::SponsorshipsExport
  include ActiveModel::Validations
  include GitHub::Memoizer

  # We have Sponsors transaction records starting this year.
  START_YEAR = 2018

  DEFAULT_TIMEFRAME = "month"

  sig { returns SponsorsListing }
  attr_reader :sponsors_listing

  sig { returns T.nilable(Integer) }
  attr_reader :year

  sig { returns T.nilable(String) }
  attr_reader :month, :contact_email

  sig { returns String }
  attr_reader :format, :content, :timeframe

  sig { returns T.nilable(GitHubSponsors::Types::Sponsorable) }
  def sponsorable
    sponsors_listing.sponsorable
  end

  validates :sponsors_listing, presence: true
  validates :sponsorable, presence: true
  validates :year, inclusion: {
    in: Date.today.year.downto(START_YEAR),
    message: "%{value} is not a valid year"
  }, allow_blank: true
  validates :month, inclusion: {
    in: Date::MONTHNAMES[1..12],
    message: "%{value} is not a valid month"
  }, allow_blank: true
  validates :timeframe, inclusion: {
    in: %w(month year all),
    message: "%{value} is not a valid timeframe"
  }
  validates :format, inclusion: { in: %w(json csv), message: "%{value} is not a valid format" }
  validates :contact_email, presence: { message: "no contact email for your Sponsors account" }
  validate :month_present_if_necessary
  validate :year_present_if_necessary

  # sponsors_listing - a SponsorsListing record whose sponsorships should be exported
  # format - the data format to export sponsorships in; choose from json, csv
  # timeframe - how long of a span of time should be exported; determines which of the `year`
  #             and `month` parameters are necessary, if any
  # year - optional year to use with `month` for limiting the sponsorships to a certain time
  #        range; omit along with `month` to get all sponsorships
  # month - optional month to use with `year`; omit while omitting `year` to get all
  #         sponsorships; omit while still passing `year` to get all sponsorships in a particular
  #         year
  sig do
    params(
      sponsors_listing: SponsorsListing,
      format: T.any(String, Symbol),
      timeframe: T.nilable(String),
      year: T.nilable(T.any(String, Integer)),
      month: T.nilable(T.any(Symbol, String))
    ).void
  end
  def initialize(sponsors_listing:, format:, timeframe: nil, year: nil, month: nil)
    @sponsors_listing = sponsors_listing
    @timeframe = T.let(timeframe || DEFAULT_TIMEFRAME, String)
    @year = T.let(year&.to_i, T.nilable(Integer))
    @month = T.let(month&.to_s&.capitalize, T.nilable(String))
    @format = T.let(format.to_s.downcase, String)
    @contact_email = T.let(sponsors_listing.contact_email_address, T.nilable(String))
    @transaction_line_items_by_sponsor_id = T.let({},
      T::Hash[Integer, T::Array[Billing::BillingTransaction::LineItem]])
    @content = T.let("", String)
  end

  sig { params(actor: T.nilable(User)).void }
  def start_export_job(actor:)
    return unless valid?

    ExportSponsorshipsJob.perform_later(
      T.must_because(sponsorable) { "#valid? ensures non-nil" },
      year: year,
      month: month,
      format: format,
      timeframe: timeframe,
      actor: actor,
    )
  end

  sig { returns T.nilable(String) }
  def fetch_content
    return unless valid?
    json? ? fetch_content_as_json : fetch_content_as_csv
  end

  sig { returns String }
  def filename
    extension = json? ? "json" : "csv"
    "#{base_filename}.#{extension}"
  end

  sig { returns String }
  def description
    case timeframe
    when "all"
      "all time"
    when "year"
      year.to_s
    else
      "#{month} #{year}"
    end
  end

  sig { returns String }
  def mime_type
    if json?
      "application/json"
    else
      "text/csv"
    end
  end

  private

  # Update the order of values in #transaction_line_item_lists_for and #legacy_transfer_lists_for if this changes
  CSV_HEADERS = T.let([
    "Sponsor Handle",
    "Sponsor Profile Name",
    "Sponsor Public Email",
    "Sponsorship Started On",
    "Is Public?",
    "Is Yearly?",
    "Transaction ID",
    "Payment Source",
    "Tier Name",
    "Tier Monthly Amount",
    "Processed Amount",
    "Is Prorated?",
    "Status",
    "Transaction Date",
    "Metadata",
    "Country",
    "Region",
    "VAT"
  ].freeze, T::Array[String])

  CsvRowType = T.type_alias do
    [
      String, # sponsor login
      T.nilable(String), # sponsor display name
      T.nilable(String), # sponsor email
      ActiveSupport::TimeWithZone, # sponsorship time
      T::Boolean, # public sponsorship?
      T::Boolean, # yearly sponsor?
      T.nilable(String), # transaction ID
      String, # payment source
      T.nilable(String), # tier name
      T.nilable(String), # formatted tier price
      String, # formatted processed amount
      T.nilable(T::Boolean), # prorated?
      T.nilable(String), # billing status
      ActiveSupport::TimeWithZone, # transaction time
      T.any(T::Hash[String, T.untyped], String), # metadata
      T.nilable(String), # billing country
      T.nilable(String), # billing region
      T.nilable(String) # VAT
    ]
  end

  sig { returns String }
  def fetch_content_as_json
    sponsorships.map { |sponsorship| sponsorship_hash_for(sponsorship) }.to_json
  end

  SponsorshipHashType = T.type_alias do
    {
      sponsor_handle: String,
      sponsor_profile_name: T.nilable(String),
      sponsor_public_email: T.nilable(String),
      sponsorship_started_on: ActiveSupport::TimeWithZone,
      is_public: T::Boolean,
      is_yearly: T::Boolean,
      transactions: T::Array[TransactionHashType],
      payment_source: String,
      metadata: T.any(T::Hash[String, T.untyped], String),
    }
  end

  sig { params(sponsorship: Sponsorship).returns(SponsorshipHashType) }
  def sponsorship_hash_for(sponsorship)
    sponsor = T.let(sponsorship.sponsor || User.ghost, GitHubSponsors::Types::Sponsor)
    sponsorable = T.must_because(self.sponsorable) { "#valid? ensures non-nil" }
    result = {
      sponsor_handle: sponsor.login,
      sponsor_profile_name: sponsor.profile_name,
      sponsor_public_email: sponsor_email_from(sponsorship),
      sponsorship_started_on: sponsorship.activated_at || T.must(sponsorship.created_at),
      is_public: sponsorship.privacy_public?,
      is_yearly: sponsor.yearly_sponsors_plan?,
      transactions: transaction_hashes_for(sponsor),
      payment_source: sponsorship.payment_source.to_s,
      metadata: sponsorable_metadata(sponsorable, sponsor),
    }
    T.let(result, SponsorshipHashType)
  end

  sig { returns String }
  def fetch_content_as_csv
    CSV.generate(encoding: Encoding::UTF_8) do |csv|
      csv << CSV_HEADERS

      sponsorships.each do |sponsorship|
        line_item_lines = transaction_line_item_lists_for(sponsorship)
        legacy_transfer_lines = legacy_transfer_lists_for(sponsorship)
        lines = line_item_lines.concat(legacy_transfer_lines)
        lines.each { |line| csv << line }
      end
    end
  end

  sig { returns T::Array[Integer] }
  memoize def tier_ids
    sponsors_listing.sponsors_tier_ids
  end

  sig { returns T::Array[Sponsorship] }
  memoize def sponsorships
    sponsor_relations_to_preload = [:profile, :primary_user_email_role, :sponsors_business_tax_identifiers]
    sponsorships = sponsors_listing.sponsorships.includes(sponsor: sponsor_relations_to_preload).newest_first.to_a
    sponsors = sponsorships.map(&:sponsor)
    GitHub::PrefillAssociations.prefill_batch_method(sponsors, :async_business)
    sponsorships
  end

  sig { returns T::Array[Integer] }
  memoize def sponsorable_ids
    sponsorships.map(&:sponsorable_id)
  end

  sig { returns T::Array[Integer] }
  memoize def sponsor_ids
    sponsorships.map(&:sponsor_id)
  end

  # Private: Get the ID pairs of sponsorables and sponsors according to the sponsorships
  #
  # Returns an Array of Arrays of format [[sponsorable_id, sponsor_id], [sponsorable_id_2, sponsor_id_2]]
  sig { returns T::Array[[Integer, Integer]] }
  memoize def sponsorable_and_sponsor_pairs
    T.cast(sponsorable_ids.zip(sponsor_ids), T::Array[[Integer, Integer]])
  end

  sig { params(sponsor: GitHubSponsors::Types::Sponsor).returns(T::Array[Billing::BillingTransaction::LineItem]) }
  def transaction_line_items_for(sponsor)
    sponsor_id = T.must(sponsor.id)
    cached_line_items = @transaction_line_items_by_sponsor_id[sponsor_id]
    return cached_line_items unless cached_line_items.nil?

    user_line_items = Billing::BillingTransaction::LineItem
      .sponsorships
      .includes(:billing_transaction)
      .preload(:subscribable)
      .for_subscribable_and_user(tier_ids, sponsor_id)
      .created_during(time_range)
      .select { |line_item| !line_item.sponsors_fee? && line_item.billing_transaction.success? }
      .to_a

    business_line_items = if sponsor.business.present?
      Billing::BillingTransaction::LineItem
        .sponsorships
        .includes(:billing_transaction)
        .preload(:subscribable)
        .for_subscribable(tier_ids)
        .for_business(sponsor.business)
        .created_during(time_range)
        .select { |line_item| !line_item.sponsors_fee? && line_item.billing_transaction.success? }
        .select { |line_item| line_item.sponsor_id == sponsor_id }
        .to_a
    else
      []
    end

    line_items = user_line_items + business_line_items
    line_items_newest_first = line_items.uniq
      .sort_by { |line_item| line_item.created_at }
      .reverse

    @transaction_line_items_by_sponsor_id[sponsor_id] = line_items_newest_first
  end

  sig { params(sponsor_id: Integer).returns(T::Array[InvoicedSponsorshipTransfer]) }
  def legacy_transfers_for(sponsor_id)
    legacy_transfers[sponsor_id] || []
  end

  sig { returns T::Hash[Integer, T::Array[InvoicedSponsorshipTransfer]] }
  memoize def legacy_transfers
    InvoicedSponsorshipTransfer
      .for_sponsors_listing(sponsors_listing)
      .completed
      .not_fully_reversed
      .created_between(time_range.begin, time_range.end)
      .group_by(&:sponsor_id)
  end

  sig do
    params(
      line_item: Billing::BillingTransaction::LineItem,
      sponsor: GitHubSponsors::Types::Sponsor
    ).returns({ billing_country: T.nilable(String), billing_region: T.nilable(String), vat: T.nilable(String) })
  end
  def sales_tax_info(line_item, sponsor)
    business_tax_identifier = sponsor.sponsors_business_tax_identifier_at(line_item.created_at)
    if business_tax_identifier
      {
        billing_country: business_tax_identifier.human_country,
        billing_region: business_tax_identifier.human_region,
        vat: business_tax_identifier.vat_code
      }
    else
      {
        billing_country: line_item.billing_country,
        billing_region: line_item.billing_region,
        vat: nil,
      }
    end
  end

  TransactionHashType = T.type_alias do
    {
      transaction_id: T.nilable(String),
      tier_name: T.nilable(String),
      tier_monthly_amount: T.nilable(String),
      processed_amount: String,
      is_prorated: T.nilable(T::Boolean),
      status: T.nilable(String),
      transaction_date: T.nilable(ActiveSupport::TimeWithZone),
      billing_country: T.nilable(String),
      billing_region: T.nilable(String),
      vat: T.nilable(String),
    }
  end

  # Private: Used for JSON generation.
  sig { params(sponsor: GitHubSponsors::Types::Sponsor).returns(T::Array[TransactionHashType]) }
  def transaction_hashes_for(sponsor)
    line_items = transaction_line_items_for(sponsor)
    line_item_data = line_items.map do |line_item|
      {
        transaction_id: line_item.billing_transaction&.transaction_id,
        tier_name: line_item.subscribable_name,
        tier_monthly_amount: line_item.subscribable_money&.format,
        processed_amount: line_item.to_money.format,
        is_prorated: line_item.prorated_charge?,
        status: line_item.last_billing_status,
        transaction_date: line_item.created_at,
      }.merge(sales_tax_info(line_item, sponsor))
    end

    legacy_transfers = legacy_transfers_for(T.must(sponsor.id))
    legacy_transfer_data = legacy_transfers.map do |transfer|
      {
        transaction_id: nil,
        tier_name: nil,
        tier_monthly_amount: nil,
        processed_amount: Billing::Money.new(transfer.amount_in_cents).format,
        is_prorated: nil,
        status: nil,
        transaction_date: transfer.transfer_created_at,
        billing_country: nil,
        billing_region: nil,
        vat: nil,
      }
    end

    line_item_data.concat(legacy_transfer_data)
  end

  # Private: Used for CSV generation.
  sig { params(sponsorship: Sponsorship).returns(T::Array[CsvRowType]) }
  def transaction_line_item_lists_for(sponsorship)
    sponsor = sponsorship.sponsor
    return [] unless sponsor

    line_items = transaction_line_items_for(sponsor)
    sponsor_email = sponsor_email_from(sponsorship)
    is_yearly_sponsor = sponsor.yearly_sponsors_plan?
    sponsorable = T.must_because(self.sponsorable) { "#valid? ensures non-nil" }

    line_items.map do |line_item|
      tax_info = sales_tax_info(line_item, sponsor)
      # This list should be kept in the same order as `csv_headers`
      [
        sponsor.login, # sponsor login
        sponsor.profile_name, # sponsor display name
        sponsor_email, # sponsor email
        sponsorship.activated_at || T.must(sponsorship.created_at), # sponsorship time
        sponsorship.privacy_public?, # public sponsorship?
        is_yearly_sponsor, # yearly sponsor?
        line_item.billing_transaction&.transaction_id, # transaction ID
        sponsorship.payment_source.to_s, # payment source
        line_item.subscribable_name, # tier name
        line_item.subscribable_money&.format, # formatted tier price
        line_item.to_money.format, # formatted processed amount
        line_item.prorated_charge?, # prorated?
        line_item.last_billing_status, # billing status
        line_item.created_at, # transaction time
        sponsorable_metadata(sponsorable, sponsor), # sponsorable metadata
        tax_info[:billing_country], # billing country
        tax_info[:billing_region], # billing region
        tax_info[:vat] # VAT
      ]
    end
  end

  sig { params(sponsorship: Sponsorship).returns(T.nilable(String)) }
  def sponsor_email_from(sponsorship)
    sponsor = sponsorship.sponsor
    return unless sponsor
    sponsor.publicly_visible_email(logged_in: true)
  end

  # Private: Used for CSV generation.
  sig { params(sponsorship: Sponsorship).returns(T::Array[CsvRowType]) }
  def legacy_transfer_lists_for(sponsorship)
    sponsor = sponsorship.sponsor
    return [] unless sponsor

    sponsorable = T.must_because(self.sponsorable) { "#valid? ensures non-nil" }
    legacy_transfers = legacy_transfers_for(sponsorship.sponsor_id)
    sponsor_email = sponsor_email_from(sponsorship)
    is_yearly_sponsor = sponsor.yearly_sponsors_plan?

    legacy_transfers.map do |legacy_transfer|
      # This list should be kept in the same order as `csv_headers`
      [
        sponsor.login, # sponsor login
        sponsor.profile_name, # sponsor display name
        sponsor_email, # sponsor email
        sponsorship.activated_at || T.must(sponsorship.created_at), # sponsorship time
        sponsorship.privacy_public?, # public sponsorship?
        is_yearly_sponsor, # yearly sponsor?
        nil, # transaction ID
        sponsorship.payment_source.to_s, # payment source
        nil, # tier name
        nil, # formatted tier price
        Billing::Money.new(legacy_transfer.amount_in_cents).format, # formatted processed amount
        nil, # prorated?
        nil, # billing status
        legacy_transfer.transfer_created_at || legacy_transfer.created_at, # transaction time
        sponsorable_metadata(sponsorable, sponsor), # sponsorable metadata
        nil, # billing country
        nil, # billing region
        nil, # VAT
      ]
    end
  end

  # Private: Memoizable method for checking if sponsorable has feature
  # flag enabled.
  #
  # Returns Hash of Hashes with SponsorActivity by sponsorable and sponsor
  # ids with format `{ sponsorableID => { sponsorID => SponsorsActivity } }`
  sig { returns T::Hash[Integer, T::Hash[Integer, T::Array[SponsorsActivity]]] }
  memoize def sponsors_activities
    SponsorsActivity.for_sponsorables_and_sponsors(sponsorable_and_sponsor_pairs, time_range: time_range)
  end

  # Private: Returns sponsorable metadata for sponsorable and sponsor pair
  #
  # Returns sponsorable metadata as JSON or string per format requested.
  sig do
    params(
      sponsorable: GitHubSponsors::Types::Sponsorable,
      sponsor: GitHubSponsors::Types::Sponsor
    ).returns(T.any(String, T::Hash[String, T.untyped]))
  end
  def sponsorable_metadata(sponsorable, sponsor)
    empty_value = json? ? {} : ""

    sponsorable_activities = sponsors_activities[T.must(sponsorable.id)]
    return empty_value unless sponsorable_activities.present?

    sponsorable_sponsor_activities = sponsorable_activities[T.must(sponsor.id)]

    return empty_value unless sponsorable_sponsor_activities.present?

    metadata_list = T.let(sponsorable_sponsor_activities.map(&:sponsorable_metadata),
      T::Array[T::Hash[String, T.untyped]])
    if json?
      # it's possible to have nil metadata, so we call `compact` to filter those out before sorting
      sponsorable_metadata_by_keys = metadata_list.compact.each_with_object({}) do |metadata, hash|
        metadata.each do |key, value|
          hash[key] ||= []
          hash[key] << value
        end
      end
      sponsorable_metadata_by_keys.each_value(&:sort!).sort.to_h
    else
      metadata_list.flat_map(&:to_a).sort.map { |(key, value)| "#{key}: #{value}" }.join(", ")
    end
  end

  sig { returns T::Boolean }
  def all_time?
    timeframe == "all"
  end

  sig { returns T::Boolean }
  def full_year?
    timeframe == "year"
  end

  sig { returns String }
  def base_filename
    prefix = "#{sponsors_listing.sponsorable_login}-sponsorships-"
    if all_time?
      "#{prefix}all-time"
    elsif full_year?
      "#{prefix}#{year}"
    else
      "#{prefix}#{month}-#{year}"
    end
  end

  sig { returns T::Range[DateTime] }
  memoize def time_range
    if all_time?
      earliest_time = DateTime.new(START_YEAR, 1)
      now = DateTime.now
      earliest_time.beginning_of_month..now.end_of_month
    elsif full_year?
      year_start = DateTime.new(T.must(year), 1)
      year_start.beginning_of_month..year_start.end_of_year
    else
      parsed_date = DateTime.strptime("#{month} #{year}", "%B %Y")
      parsed_date.beginning_of_month..parsed_date.end_of_month
    end
  end

  sig { returns T::Boolean }
  def json?
    format == "json"
  end

  sig { void }
  def month_present_if_necessary
    return if month.present?

    if timeframe == "month"
      errors.add(:month, "is required")
    end
  end

  sig { void }
  def year_present_if_necessary
    return if year.present?

    unless all_time?
      errors.add(:year, "is required")
    end
  end
end
