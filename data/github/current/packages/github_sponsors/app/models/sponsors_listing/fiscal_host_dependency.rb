# typed: strict
# frozen_string_literal: true

module SponsorsListing::FiscalHostDependency
  extend ActiveSupport::Concern
  extend T::Sig
  extend T::Helpers

  requires_ancestor { SponsorsListing }

  OPEN_SOURCE_COLLECTIVE_LOGIN = "Open-Source-Collective"
  OPEN_COLLECTIVE_FOUNDATION = "Open-Collective-Foundation"
  SOFTWARE_FREEDOM_CONSERVANCY = "conservancy"
  USER_HIDDEN_FISCAL_HOSTS = T.let([OPEN_COLLECTIVE_FOUNDATION, SOFTWARE_FREEDOM_CONSERVANCY].freeze, T::Array[String])

  FISCALLY_HOSTED_PROJECT_PROFILE_QUESTION_SLUG = "fiscally_hosted_project_profile_url"
  FISCALLY_HOSTED_PROJECT_PROFILE_QUESTION_TEXT = "Fiscally Hosted Project URL"

  class_methods do
    extend T::Sig

    # Public: Constructs a new instance of SponsorsListing using a fiscal host
    sig { params(attrs: T::Hash[T.any(String, Symbol), T.untyped]).returns(SponsorsListing) }
    def new_with_fiscal_host(attrs)
      T.bind(self, T.class_of(SponsorsListing))

      new(attrs).tap do |listing|
        listing.state = :waitlisted

        if listing.parent_listing # supported fiscal host
          listing.billing_country = listing.parent_listing.billing_country
        end

        listing.billing_country_validation_enabled = true
      end
    end

    # Public: Get the display name for a particular fiscal host.
    #
    # fiscal_host - a String like "Open-Collective-Foundation", the login of the fiscal host's Organization
    sig { params(fiscal_host: String).returns(T.nilable(String)) }
    def human_fiscal_host(fiscal_host)
      if %w(none other).include?(fiscal_host.to_s.downcase)
        fiscal_host.to_s.downcase
      else
        org = fiscal_host_organization(fiscal_host)
        org&.safe_profile_name
      end
    end

    # Public: Get a count of how many Sponsors listings use a fiscal host for their payouts.
    #
    # fiscal_hosts - a list of String fiscal host org logins whose usage counts should be returned, e.g.,
    #                ["Open-Collective-Foundation", "conservancy"]
    #
    # Returns a Hash[String] => Integer where each key is the organization login of the
    # fiscal host and the value is how many Sponsors listings are using that fiscal host.
    sig { params(fiscal_hosts: T::Array[String]).returns(T::Hash[String, Integer]) }
    def fiscal_host_usage_counts(fiscal_hosts)
      T.bind(self, T.class_of(SponsorsListing))

      fiscal_host_slugs = fiscal_hosts.map { |f| slug_for(f) }
      child_listings = joins(:parent_listing)
        .with_parent_slug(fiscal_host_slugs)
        .select("parent_listings_sponsors_listings.slug AS parent_listing_slug")
      result = Hash.new(0)
      child_listings.each do |child_listing|
        fiscal_host_login = login_from_slug(child_listing.parent_listing_slug)
        result[fiscal_host_login] += 1
      end
      result
    end

    # Public: Get the organization for a particular fiscal host.
    #
    # fiscal_host - a String like "Open-Collective-Foundation" that's an Organization's login
    sig { params(fiscal_host: String).returns(T.nilable(GitHubSponsors::Types::Sponsorable)) }
    def fiscal_host_organization(fiscal_host)
      sponsors_listing = fiscal_host_listing(fiscal_host)
      sponsors_listing&.sponsorable
    end

    # Public: Get the Sponsors listing for a particular fiscal host.
    #
    # fiscal_host - a String like "Open-Collective-Foundation" that's an Organization's login
    sig { params(fiscal_host: String).returns(T.nilable(SponsorsListing)) }
    def fiscal_host_listing(fiscal_host)
      T.bind(self, T.class_of(SponsorsListing))

      fiscal_hosts.with_sponsorable_logins(fiscal_host).first
    end
  end

  included do
    T.bind(self, T.class_of(SponsorsListing))

    sig { returns T::Boolean }
    def fiscal_host?
      is_fiscal_host?
    end

    # Public: The SponsorsListing of the fiscal host this listing uses, if this listing is fiscally hosted.
    belongs_to :parent_listing, class_name: "SponsorsListing"

    has_one :parent_listing_sponsorable, through: :parent_listing, disable_joins: true, source: :sponsorable

    has_one :fiscally_hosted_project_profile_survey_question,
      -> { T.bind(self, T.untyped); sponsors_fiscally_hosted_project_profile },
      through: :survey,
      class_name: "SurveyQuestion",
      source: :questions

    has_one :first_fiscally_hosted_project_profile_survey_choice,
      through: :fiscally_hosted_project_profile_survey_question,
      class_name: "SurveyChoice",
      source: :first_choice

    has_one :fiscally_hosted_project_profile_survey_answer, ->(sponsors_listing) do
      where(user_id: sponsors_listing.sponsorable_id)
    end, through: :first_fiscally_hosted_project_profile_survey_choice, class_name: "SurveyAnswer",
      source: :answers

    has_many :child_listings, class_name: "SponsorsListing", inverse_of: :parent_listing,
      foreign_key: "parent_listing_id"

    validate :parent_listing_is_fiscal_host
    validate :not_fiscal_host_when_is_child_listing
    validate :fiscal_host_sponsorable_is_org
    validate :not_a_grandchild_listing

    scope :with_parent_slug, ->(slug) { where(parent_listings_sponsors_listings: { slug: slug }) }

    # Public: Get Sponsors listings that are either using no fiscal host at all or are using
    # an unsupported fiscal host.
    scope :without_parent_listing, -> do
      left_joins(:parent_listing).where(parent_listings_sponsors_listings: { id: nil })
    end

    # Public: Get all listings that are marked as fiscal hosts.
    scope :fiscal_hosts, -> { where(is_fiscal_host: true) }

    scope :fiscal_hosts_visible_for_signup, -> do
      hidden_fiscal_host_slugs = USER_HIDDEN_FISCAL_HOSTS.map { |h| slug_for(h) }
      fiscal_hosts.where.not(slug: hidden_fiscal_host_slugs)
    end

    # Public: Filter listings based on what fiscal host they use, if any.
    #
    # filter - a String or Array of Strings; each String can be the Organization login of a fiscal host, such as
    #          "numfocus"; "other" to get listings where the maintainer gave a custom fiscal host name at signup time;
    #          or "none" to get listings where no custom fiscal host name was specified nor is a supported fiscal host
    #          being used.
    scope :filter_by_fiscal_host, ->(filter) do
      base_query = left_joins(:parent_listing)
      if filter.is_a?(Array)
        first_filter, *remaining_filters = filter.flatten
        queries = base_query.filter_by_fiscal_host(first_filter)
        if remaining_filters.present?
          remaining_filters.each do |fiscal_host|
            queries = queries.or(filter_by_fiscal_host(fiscal_host))
          end
        end
        queries
      elsif filter == "none"
        without_parent_listing
      elsif filter
        base_query.with_parent_slug(slug_for(filter))
      end
    end
  end

  # Public: Returns the display name of the fiscal host this listing uses for payouts, if any.
  sig { returns String }
  def human_fiscal_host
    parent_listing&.sponsorable_name || "none"
  end

  sig { returns T.nilable(String) }
  def parent_sponsorable_login
    parent_listing&.sponsorable_login
  end

  # Public: Saves the fiscally hosted project profile URL into a SurveyAnswer
  sig { params(url: T.nilable(String)).void }
  def fiscally_hosted_project_profile_url=(url)
    return unless can_use_fiscal_host?
    if fiscally_hosted_project_profile_survey_answer&.update(other_text: url) || new_record?
      @fiscally_hosted_project_profile_url = T.let(url, T.nilable(String)) # Update memoized value
    end
  end

  sig { returns T.nilable(String) }
  def fiscally_hosted_project_profile_url
    return @fiscally_hosted_project_profile_url if defined?(@fiscally_hosted_project_profile_url)
    @fiscally_hosted_project_profile_url = if can_use_fiscal_host?
      answer = fiscally_hosted_project_profile_survey_answer
      answer.other_text.to_s if answer
    end
  end

  sig { returns T::Boolean }
  def can_use_fiscal_host?
    return false if fiscal_host? # fiscal hosts can't be fiscally hosted themselves
    !!sponsorable&.can_use_fiscal_host_for_sponsors?
  end

  sig { returns T::Boolean }
  def uses_fiscal_host?
    parent_listing.present?
  end

  sig { returns T::Boolean }
  def uses_open_source_collective_as_fiscal_host?
    parent_sponsorable_login == OPEN_SOURCE_COLLECTIVE_LOGIN
  end

  sig { params(old_fiscal_host: String, actor: User).void }
  def instrument_fiscal_host_change(old_fiscal_host:, actor:)
    actor_hash = GitHub.guarded_audit_log_staff_actor_entry(actor)

    # Audit log
    instrument :fiscal_host_change, actor_hash.merge(
      prefix: :sponsors,
      old_fiscal_host: old_fiscal_host,
      new_fiscal_host: human_fiscal_host,
    )
  end

  sig { returns ActiveRecord::Relation }
  def survey_answers_without_fiscal_host
    survey_answers.joins(:question).where.not(survey_questions: {
      short_text: SponsorsListing::FiscalHostDependency::FISCALLY_HOSTED_PROJECT_PROFILE_QUESTION_SLUG,
    })
  end

  private

  sig { void }
  def ensure_fiscal_host_survey_answers
    return unless uses_fiscal_host?
    return unless can_use_fiscal_host? && survey

    unless fiscally_hosted_project_profile_survey_answer
      create_survey_answer_for_choice(first_fiscally_hosted_project_profile_survey_choice,
        other_text: @fiscally_hosted_project_profile_url)
      reload_fiscally_hosted_project_profile_survey_answer
    end
  end

  sig do
    params(
      survey_choice: T.nilable(SurveyChoice),
      other_text: T.nilable(String)
    ).returns(T.nilable(SurveyAnswer))
  end
  def create_survey_answer_for_choice(survey_choice, other_text: nil)
    return unless survey_choice

    survey_choice.answers.create!(
      user_id: sponsorable_id,
      survey_id: survey_id,
      question_id: survey_choice.question_id,
      other_text: other_text,
    )
  end

  sig { void }
  def parent_listing_is_fiscal_host
    parent = parent_listing
    return unless parent

    unless parent.fiscal_host?
      errors.add(:parent_listing, "must be a fiscal host listing")
    end
  end

  sig { void }
  def not_fiscal_host_when_is_child_listing
    return unless fiscal_host? && parent_listing_id
    errors.add(:parent_listing_id, "must be nil for fiscal host listing")
  end

  sig { void }
  def fiscal_host_sponsorable_is_org
    maintainer = sponsorable
    return unless fiscal_host? && maintainer

    unless maintainer.organization?
      errors.add(:sponsorable, "must be an organization for fiscal host listing")
    end
  end

  sig { void }
  def set_billing_country_based_on_fiscal_host
    parent = parent_listing
    self.billing_country = parent.billing_country if parent
  end

  sig { void }
  def not_a_grandchild_listing
    parent = parent_listing
    return unless parent

    if parent.parent_listing
      errors.add(:parent_listing, "is already a child listing")
    end
  end
end
