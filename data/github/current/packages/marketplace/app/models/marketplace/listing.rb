# typed: false
# frozen_string_literal: true

class Marketplace::Listing < ApplicationRecord::Domain::Integrations
  extend GitHub::Encoding
  force_utf8_encoding :full_description, :extended_description

  include GitHub::Relay::GlobalIdentification
  include GitHub::Validations
  include Marketplace::FinancialOnboardingDependency
  include Marketplace::FreeOnboardingDependency

  self.table_name = "marketplace_listings"

  include Workflow
  include PrimaryAvatar::Model
  include Avatar::List::Model
  include Instrumentation::Model
  include ActionView::Helpers::OutputSafetyHelper

  include Permissions::Attributes::Wrapper
  self.permissions_wrapper_class = Permissions::Attributes::MarketplaceListing

  # Used to ignore the validation that normally ensures the listing is a draft
  # before allowing categories to be changed. Set to true to allow modifications
  # even when the listing is not a draft.
  attr_accessor :skip_draft_validation

  # Necessary to upload avatars for a listing. See UploadPoliciesController#deliver_policy.
  NAME_MAX_LENGTH = 255
  SHORT_DESCRIPTION_MAX_LENGTH = 125
  FULL_DESCRIPTION_MAX_LENGTH = 500
  EXTENDED_DESCRIPTION_MAX_LENGTH = 1_000
  MAX_SUPPORTED_LANGUAGES_COUNT = 10
  MAX_FEATURED_ORGANIZATIONS_COUNT = 8
  MAX_LISTING_RECOMMENDATIONS = 15
  URL_REGEX = %r{\Ahttps?://}.freeze
  MIN_INSTALLS_FOR_SOCIAL_PROOF = Rails.env.test? ? 2 : 10 #Use lesser threshold for tests to prevent CI slowdowns
  DEFAULT_NAMING_AND_LINKS_ATTRIBUTES = %i(name short_description privacy_policy_url support_url)
  NAMING_AND_LINKS_ATTRIBUTES_FOR_OAUTH_APPLICATION = DEFAULT_NAMING_AND_LINKS_ATTRIBUTES + %i(installation_url)
  CONTACT_INFO_ATTRIBUTES = %i(technical_email marketing_email finance_email security_email)
  LOGO_AND_FEATURE_CARD_ATTRIBUTES = %i(hero_card_background_image_id bgcolor primary_avatar_url)
  LISTING_DETAILS_ATTRIBUTES = %i(full_description extended_description)
  INTEGRATION_TYPE = Integration.name
  OAUTH_APPLICATION_TYPE = OauthApplication.name
  INTEGRATABLES = [INTEGRATION_TYPE, OAUTH_APPLICATION_TYPE]
  RESTRICTED_REGIONS = ["Russia", "Russian Federation", "Belarus"]
  DEFAULT_LOGO_SIZE = 400

  # We use separate constants for test because we need to create these apps to test.
  # Creating a large number of apps is causing a lot of slow downs in CI
  if Rails.env.test?
    REQUIRED_INSTALLS_FOR_OAUTH_APP = 4
    REQUIRED_INSTALLS_FOR_GITHUB_APP = 2
  else
    REQUIRED_INSTALLS_FOR_OAUTH_APP = 200
    REQUIRED_INSTALLS_FOR_GITHUB_APP = 100
  end

  PUBLICLY_LISTED_STATES = [:verified, :unverified, :verification_pending_from_unverified, :verified_creator]

  # A marketplace listing may belong to many things, including the existing OAuth and GitHub apps
  # and sponsorables.
  belongs_to :listable, polymorphic: true

  has_and_belongs_to_many :categories,
    -> { joins(:listings).order("marketplace_categories_listings.id ASC").distinct },
    class_name:              "Marketplace::Category",
    foreign_key:             "marketplace_listing_id",
    association_foreign_key: "marketplace_category_id"

  has_and_belongs_to_many :regular_categories,
    -> { joins(:listings).where(acts_as_filter: false).order("marketplace_categories_listings.id ASC").distinct },
    class_name:              "Marketplace::Category",
    foreign_key:             "marketplace_listing_id",
    association_foreign_key: :marketplace_category_id

  has_and_belongs_to_many :filter_categories,
    -> { joins(:listings).where(acts_as_filter: true).order("marketplace_categories_listings.id ASC").distinct },
    class_name:              "Marketplace::Category",
    foreign_key:             "marketplace_listing_id",
    association_foreign_key: :marketplace_category_id

  # rubocop:todo Rails/InverseOf
  has_many :supported_languages,
                                 class_name: "Marketplace::ListingSupportedLanguage",
                                 foreign_key: "marketplace_listing_id"
  # rubocop:enable Rails/InverseOf
  has_many :languages, through: :supported_languages, disable_joins: true

  # Marketplace::ListingPlans, not to be confused with GitHub::Plans
  # rubocop:todo Rails/InverseOf
  has_many :listing_plans, class_name: "Marketplace::ListingPlan",
                           foreign_key: "marketplace_listing_id",
                           dependent: :destroy
  # rubocop:enable Rails/InverseOf

  has_many :subscription_items, through: :listing_plans, disable_joins: true
  destroy_dependents_in_background :subscription_items

  # rubocop:todo Rails/InverseOf
  has_many :screenshots, class_name: "Marketplace::ListingScreenshot",
                         foreign_key: "marketplace_listing_id"
  # rubocop:enable Rails/InverseOf

  # rubocop:todo Rails/InverseOf
  has_many :insights, class_name: "Marketplace::ListingInsight",
                      foreign_key: "marketplace_listing_id"
  # rubocop:enable Rails/InverseOf

  belongs_to :hero_card_background_image, class_name: "Marketplace::ListingImage"
  # rubocop:todo Rails/InverseOf
  has_many :images, class_name: "Marketplace::ListingImage", foreign_key: "marketplace_listing_id"
  has_many :featured_organizations, class_name: "Marketplace::ListingFeaturedOrganization", foreign_key: "marketplace_listing_id", dependent: :destroy
  # rubocop:enable Rails/InverseOf

  has_many :hooks, as: :installation_target
  destroy_dependents_in_background :hooks

  has_one :webhook, -> { where("hooks.name" => "web") },
    class_name: "Hook",
    as: :installation_target

  # rubocop:todo Rails/InverseOf
  has_many :marketplace_order_previews, class_name: "Marketplace::OrderPreview", foreign_key: "marketplace_listing_id"
  # rubocop:enable Rails/InverseOf

  before_validation :set_slug
  after_commit :synchronize_search_index
  after_commit :update_trade_compliance_metadata
  after_destroy :opt_out_listable_proxima_sync

  NO_ENDING_PUNCTUATION_REGEX = /.*[^\.!?]\z/
  # Ruby and JavaScript regex's do not handle line endings the same.
  NO_ENDING_PUNCTUATION_REGEX_JS = Regexp.new(NO_ENDING_PUNCTUATION_REGEX.source.sub("\\z", "$"))

  # Fields required on create
  validates :slug, presence: true, uniqueness: { case_sensitive: false }
  # Other fields required to progress beyond a draft listing
  validates :short_description, :full_description, presence: true, unless: :draft?
  validates :support_url, :privacy_policy_url, presence: true, if: :urls_required?
  validates :installation_url, presence: true, if: ->(listing) { !listing.draft? && listing.requires_installation_url? }

  validates :name, presence: true, length: { in: 1..NAME_MAX_LENGTH }, unicode3: true
  validates :name, uniqueness: { case_sensitive: false }, if: -> { errors[:name].blank? }
  validates :full_description, length: { maximum: FULL_DESCRIPTION_MAX_LENGTH }
  validates :short_description, format: { with: NO_ENDING_PUNCTUATION_REGEX, message: "cannot end with punctuation." }, length: { maximum: SHORT_DESCRIPTION_MAX_LENGTH }, unicode3: true, allow_blank: true
  validates :extended_description, length: { maximum: EXTENDED_DESCRIPTION_MAX_LENGTH }
  validates :bgcolor, format: { with: /\A([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})\z/ },
                      length: { maximum: 6, minimum: 3 }
  validates :company_url, :documentation_url, :pricing_url, :installation_url,
    :privacy_policy_url, :status_url, :tos_url, :learn_more_url,
    format: URL_REGEX, allow_nil: true, allow_blank: true
  validates_format_of :technical_email, :marketing_email, :finance_email, :security_email,
    with: User::EMAIL_REGEX, message: "does not look like an email address", allow_nil: true, allow_blank: true

  validate :support_url_is_url_or_email
  validates :listable, presence: true
  validate :listable_is_not_already_listed
  validate :categories_must_be_different
  validate :categories_not_in_draft, on: :update
  validate :at_least_one_category_not_acting_as_filter
  validate :supported_languages_count_does_not_exceed_max
  validate :featured_organizations_count_does_not_exceed_max
  validate :integration_is_public
  validate :admin_email_is_not_a_support_email
  validate :owns_hero_image
  validate :verified_and_hero_card_present, if: :featured_at_changed?, on: :update
  validate :can_be_marked_as_copilot_app
  validates_with Marketplace::ListingSlugValidator, if: :slug_changed?

  workflow :state do
    state :draft, 0 do
      event :request_verified_approval,
        transitions_to: :verification_pending_from_draft,
        if: :ready_for_submission?
      event :request_unverified_approval,
        transitions_to: :unverified_pending,
        if: :ready_for_unverified_submission?
    end

    state :verification_pending_from_draft, 1 do
      event :approve, transitions_to: :verified
      event :approve_creator, transitions_to: :verified_creator
      event :reject, transitions_to: :rejected
      event :redraft, transitions_to: :draft
    end

    state :rejected, 2
    state :verified_creator, 8 do
      event :delist, transitions_to: :archived
      event :move_to_verified, transitions_to: :verified
    end
    state :verified, 3 do
      event :delist, transitions_to: :archived
    end

    state :archived, 4 do
      event :approve, transitions_to: :verified
      event :approve_creator, transitions_to: :verified_creator
    end

    state :unverified_pending, 5 do
      event :redraft, transitions_to: :draft
      event :approve, transitions_to: :unverified
    end

    state :unverified, 6 do
      event :request_verified_approval,
        transitions_to: :verification_pending_from_unverified,
        if: :ready_for_submission?
      event :delist, transitions_to: :archived
    end

    state :verification_pending_from_unverified, 7 do
      event :redraft, transitions_to: :unverified
      event :approve, transitions_to: :verified
      event :approve_creator, transitions_to: :verified_creator

    end

    on_transition do |from, to, event, *args, **_kwargs|
      mailer_params = { finance_email: self.finance_email, technical_email: self.technical_email, listing_name: self.name }

      user = args[0]
      if GitHub.flipper[:marketplace_create_free_app_verification_onboarding_issues].enabled?(user)
        if to == :unverified_pending
          #creates an issue in the marketplace repository and queues free onboarding job
          initiate_free_onboarding(LISTING_STATE[:new_listing], self.name, self.slug)
        end
      end

      if to == :verification_pending_from_draft && published_paid_plans?
        #creates an issue in the marketplace repository and queues financial onboarding job
        initiate_financial_onboarding(LISTING_STATE[:new_listing], self.name, self.slug, mailer_params)
      end

      if to == :verification_pending_from_unverified
        #creates an issue in the marketplace repository and queues financial onboarding job
        initiate_financial_onboarding(LISTING_STATE[:unverified_listing], self.name, self.slug, mailer_params)
      end

      if user = args[0]
        instrument_state_change(action: event, actor: user, state: to, orig_state: from)
      end

      update_category_counters(event: event)
      if subscription_item_destruction_required?(from: from, to: to)
        destroy_subscription_items
      end

      message = args[1]
      email_state_change(action: event, old_state: from, new_state: to, message: message)
    end

    after_transition do |from, _to, _event, *_args, **_kwargs|
      synchronize_search_index

      GlobalInstrumenter.instrument(::Marketplace::Events::LISTING_STATE_CHANGE, {
        listing_id: id,
        previous_state: from,
      })
    end
  end

  # overrides Workflow persistence to also update updated_at
  def persist_workflow_state(new_value)
    update_columns(updated_at: Time.current, state: new_value)
  end

  alias :disabled? :archived?

  # Public: Limits conditions against the primary category only
  scope :for_primary_category_only, -> {
    where(%q(
      marketplace_categories_listings.id = (
        SELECT MIN(marketplace_categories_listings.id)
        FROM marketplace_categories_listings
        WHERE marketplace_categories_listings.marketplace_listing_id = marketplace_listings.id
      )
    ))
  }

  # Public: Select Marketplace::Listings in the given category.
  #
  # category_slug - the slug of a Marketplace::Category. If present, only listings
  #                 for the specified category will be returned; otherwise listings
  #                 for all categories will be returned.
  # primary_category_only - whether to return only listings for which the specified
  #                         category is the primary category. Defaults to false.
  scope :with_category, -> (category_slug, primary_category_only: false) do
    relation = left_joins(categories: :parent_category)
    relation = relation.where(marketplace_categories: { slug: category_slug })
      .or(relation.where(parent_categories_marketplace_categories: { slug: category_slug }))
      .distinct

    if primary_category_only
      relation.for_primary_category_only
    else
      relation
    end
  end

  # Public: Select Marketplace::Listings with a name, short_description, or full_description that
  # matches a query.
  #
  # query - the query string
  scope :matches_name_or_description, ->(query) do
    if query.present?
      sanitized_query = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
      where("#{table_name}.name LIKE ? OR #{table_name}.short_description LIKE ? " +
            "OR #{table_name}.full_description LIKE ?", sanitized_query,
            sanitized_query, sanitized_query)
    else
      scoped
    end
  end

  # Public: Select Marketplace::Listings that contain a plan which has a free trial
  scope :with_free_trial, ->(state: nil) do
    joins(:listing_plans).merge(Marketplace::ListingPlan.with_free_trial(state: state)).distinct
  end

  # Public: Returns Marketplace::Listings in the draft state.
  scope :drafts, -> { where(state: state_value(:draft)) }

  # Public: Returns currently featured Marketplace::Listings.
  scope :featured, -> { where("featured_at <= ?", Time.zone.now).with_state("verified") }

  # Public: Returns Marketplace::Listings for the given OAuth and/or Integration IDs.
  scope :for_integratables, -> (oauth_app_ids, integration_ids) do
    where(listable_type: OAUTH_APPLICATION_TYPE, listable_id: oauth_app_ids).or(
      where(listable_type: INTEGRATION_TYPE, listable_id: integration_ids),
    )
  end

  scope :publicly_listed, -> { with_states(PUBLICLY_LISTED_STATES) }
  scope :listable_is_integration, -> { where(listable_type: INTEGRATION_TYPE) }

  # Public: Returns Marketplace::Listings where the given Organization owns the product
  # that is listed.
  scope :for_org, ->(org) do
    adminable_app_ids = OauthApplication.where(user_id: org).pluck(:id)
    adminable_integration_ids = Integration.where(owner_id: org).pluck(:id)

    for_integratables(adminable_app_ids, adminable_integration_ids)
  end

  # Public: Returns Marketplace::Listings where the given User has admin permission on them or that
  # are publicly visible.
  scope :visible_to, ->(actor) do
    publicly_listed.or(editable_by(actor))
  end

  # Public: Returns Marketplace::Listings where the given User has admin permission on them.
  scope :editable_by, ->(actor) do
    adminable_org_ids = Ability.user_admin_on_organizations(
      actor_id: actor.id,
    ).pluck(:subject_id)
    adminable_app_ids = adminable_app_ids_for(actor: actor, adminable_org_ids: adminable_org_ids)
    adminable_integration_ids =
      adminable_integration_ids_for(actor: actor, adminable_org_ids: adminable_org_ids)

    for_integratables(adminable_app_ids, adminable_integration_ids)
  end

  scope :with_state, ->(state) do
    with_states([state])
  end

  scope :with_states, ->(states) do
    state_values = states.map { |state| state_value(state) }
    where(state: state_values)
  end

  scope :quick_installable, -> { publicly_listed.listable_is_integration }

  scope :subscribed_by, ->(account) do
    joins(:subscription_items).
    joins("JOIN plan_subscriptions ON subscription_items.plan_subscription_id=plan_subscriptions.id").
    annotate("cross-schema-domain-query-exempted").
    where(plan_subscriptions: { user_id: account }).
    where("subscription_items.quantity > 0")
  end

  scope :with_installations_on, ->(account) do
    joins("JOIN integration_installations ON marketplace_listings.listable_id=integration_installations.integration_id").
    where(listable_type: INTEGRATION_TYPE, integration_installations: { target_id: account, target_type: "User" })
  end

  # Public: Returns Marketplace::Listings installed on the given repository.
  scope :installed_on_repo, ->(repo) do
    # NOTE: OAuth apps might be considered installed by this method even though
    # they might not have the necessary scopes. Filtering by scope is expensive.
    oauth_app_ids = OauthAuthorization.where(user_id: repo.all_member_and_owner_ids).pluck(:application_id)
    integration_ids = IntegrationInstallation.with_repository(repo).pluck(:integration_id)

    for_integratables(oauth_app_ids, integration_ids)
  end

  # Public: get Marketplace listings that:
  #   - are allowlisted for quick installation during repo creation
  #   - have an active subscription on the given account
  #   - have an installation for the listing's integration on the given account
  #
  # The listing's associated GitHub App can be configured either with access to
  # all repositories, in which case repo installation is automatic; or with access
  # to specific repositories, in which case repo installation is manual.
  #
  # Returns a Hash of Marketplace::Listing => Boolean, whether the listing will auto-install.
  def self.quick_installable_for(account)
    installable = quick_installable.subscribed_by(account).with_installations_on(account)
    auto_installs = account.installations_on_all_repositories.pluck(:integration_id)

    installable.inject({}) do |hash, listing|
      hash.merge!(listing => auto_installs.include?(listing.listable_id))
    end
  end

  def self.verified_and_shuffled(limit: MAX_LISTING_RECOMMENDATIONS)
    with_state(:verified)
      .order("rand()")
      .limit(limit)
  end

  def to_param
    slug
  end

  def logo_url
    primary_avatar_url(DEFAULT_LOGO_SIZE)
  end

  def subscription_item_destruction_required?(from:, to:)
    return true if from == :draft && (to == :verification_pending_from_draft || to == :unverified_pending)
    return true if from == :verification_pending_from_draft && to == :verified
    return true if from == :unverified_pending && to == :unverified

    false
  end

  def short_description=(value)
    super(value.strip) if value
  end

  def full_description=(value)
    super(remove_windows_line_endings(value)) if value
  end

  def extended_description=(value)
    super(remove_windows_line_endings(value)) if value
  end

  def categories=(values)
    # use raw categories to perform checks before assigning them to association
    raw_categories = Array(values)

    # reset flags that are used to trigger ActiveRecord validation errors
    self.categories_have_duplicates = false
    self.categories_cannot_be_changed = false

    # check that all categories are unique
    if raw_categories.any? { |c| raw_categories.count(c) > 1 }
      self.categories_have_duplicates = true
      return
    end

    # check that categories can be changed either by override or when in daft
    unless new_record? || draft? || self.skip_draft_validation
      self.categories_cannot_be_changed = true
      return
    end

    update_category_counters(new_categories: raw_categories.reject(&:acts_as_filter))
    super(raw_categories)
  end

  # Public: Get the Integer value matching a certain state.
  def self.state_value(name)
    workflow_spec.states[name.to_sym].value
  end

  # Public: Returns an array of integer values for publicly listed states.
  def self.publicly_listed_state_values
    PUBLICLY_LISTED_STATES.map { |state| state_value(state) }
  end

  # Public: Given a User and the Organization IDs for which the User is an admin, this will return
  # a list of OauthApplication IDs that the User has admin rights to.
  def self.adminable_app_ids_for(actor:, adminable_org_ids:)
    oauth_apps = OauthApplication
    if adminable_org_ids.present?
      oauth_apps = oauth_apps.where("user_id = ? OR user_id IN (?)", actor, adminable_org_ids)
    else
      oauth_apps = oauth_apps.where(user_id: actor)
    end
    oauth_apps.pluck(:id)
  end

  # Public: Given a User and the Organization IDs for which the User is an admin, this will return
  # a list of Integration IDs that the User has admin rights to.
  def self.adminable_integration_ids_for(actor:, adminable_org_ids:)
    adminable_integrations = Integration
    if adminable_org_ids.present?
      adminable_integrations = adminable_integrations.where("owner_id = ? OR owner_id IN (?)",
                                                            actor, adminable_org_ids)
    else
      adminable_integrations = adminable_integrations.where(owner_id: actor)
    end
    adminable_integrations.pluck(:id)
  end

  # Public: Check if the specified user has installed this listing's app.
  #
  # user - a User or nil
  #
  # Returns a Boolean.
  def installed_for?(user)
    return false unless user

    if listable_is_integration?
      account_ids = user.owned_organizations.pluck(:id) << user.id
      IntegrationInstallation.exists?(target_id: account_ids, integration_id: listable_id)
    elsif user
      user.oauth_authorizations.exists?(application_id: listable_id)
    else
      false
    end
  end

  # The installation count query is expensive. Use this unless you absolutely need up-to-date data
  def async_cached_installation_count(since: nil)
    @async_cached_installation_counts ||= Hash.new do |hash, since|
      hash[since] = Platform::Loaders::Cache.fetch("#{cache_key}/installations_count/#{since}", ttl: 24.hours) do
        installation_count(since: since)
      end
    end

    @async_cached_installation_counts[since]
  end

  def cached_installation_count(since: nil)
    async_cached_installation_count(since: since).sync
  end

  def installation_count(since: nil)
    if listable_is_integration?
      query = ::IntegrationInstallation.where(integration_id: listable_id)
    elsif listable_is_oauth_application?
      query = ::OauthAuthorization.where(application_id: listable_id)
    else
      return 0
    end

    query = query.since(since) if since
    query.count
  end

  def async_meets_installation_count_requirements
    async_cached_installation_count.then do |install_count_all_time|
      install_count_all_time >= required_installations_for_verification
    end
  end

  def required_installations_for_verification
    if GitHub.flipper[:marketplace_publisher_allowed_fewer_installations].enabled?(owner)
      0
    else
      if listable_is_oauth_application?
        REQUIRED_INSTALLS_FOR_OAUTH_APP
      else
        REQUIRED_INSTALLS_FOR_GITHUB_APP
      end
    end
  end

  def recommended?
    async_is_recommended?.sync
  end

  def async_is_recommended?
    @async_is_recommended ||= Platform::Loaders::KV.load("marketplace/recommendations").then do |raw|
      if raw
        recommended_ids = JSON.parse(raw)
        self.id.in? recommended_ids
      else
        false
      end
    end
  end

  def configuration_path
    path = if listable_is_oauth_application?
      UrlHelpers.settings_user_applications_path
    elsif listable_is_integration?
      UrlHelpers.settings_user_installations_path
    end

    URI.parse(path)
  end

  def primary_avatar_path
    "/ml/#{id}"
  end

  def permalink(include_host: true)
    if include_host
      "#{GitHub.url}/marketplace/#{slug}"
    else
      "/marketplace/#{slug}"
    end
  end

  def og_image_url
    open_graph = OpenGraph.new(self,
      cache_key_parts: [
        cached_installation_count,
        slug,
        owner,
        self.updated_at
      ]
    )
    #Custom-OG-Image service shouldn't be enabled for GH Enterprise.
    #Custom-OG-Image service itself will return the default not found image if requested for a
    #private, drafted, archived or an invalid app. Hence, not handling here.
    GitHub.enterprise? ? nil : open_graph.og_image_url
  end

  # Public: Returns the User or Organization that owns the backing OauthApplication/Integration/Listable.
  def owner
    return nil unless listable

    listable.owner
  end

  # Public: Asynchronously returns the User or Organization that owns the backing OauthApplication/Integration/Listable.
  def async_owner
    async_listable.then do |listable|
      next nil unless listable
      if listable_is_oauth_application?
        integratable.async_user
      elsif listable_is_integration?
        integratable.async_owner
      end
    end
  end

  def async_target_for_conditional_access
    async_owner
  end

  def target_for_conditional_access
    owner
  end

  # Public: Returns a list of Users who own the backing OauthApplication or Integration, or who are
  # admins of the Organization that owns that app/integration.
  def admins
    if (user_or_org = owner).nil?
      []
    elsif user_or_org.user?
      [user_or_org]
    else # organization
      user_or_org.admins
    end
  end

  def show_install_count_on_search_results
    async_cached_installation_count.then do |install_count_all_time|
      install_count_all_time >= MIN_INSTALLS_FOR_SOCIAL_PROOF
    end
  end

  def show_recommended_or_install_count
    show_install_count_on_search_results.sync || recommended?
  end

  def keep_old_avatar?
    false
  end

  # Public: Returns true if the given User has permission to upload a logo or a
  # screenshot associated with this listing. This is used by Avatar#can_upload?
  def avatar_editable_by?(actor)
    allowed_to_edit?(actor)
  end

  def async_adminable_by?(actor)
    return Promise.resolve(false) unless actor.present?

    async_listable.then do |listable|
      listable&.adminable_by?(actor)
    end
  end

  # Public: Returns true if the given User has admin access to this listing.
  def adminable_by?(actor)
    async_adminable_by?(actor).sync
  end

  # Public: Returns true if the given User can request approval to publish this listing as verified.
  def verified_approval_requestable_by?(actor)
    approval_request_prerequisites_met_by?(actor) && can_request_verified_approval?
  end

  # Public: Returns true if the given User can request approval to publish this listing as verified.
  def async_verified_approval_requestable_by?(actor)
    async_approval_request_prerequisites_met_by?(actor).then do |prerequisites_met|
      if prerequisites_met
        # Must load webhook async because `can_request_verified_approval?`,
        # which comes from workflow-orchestrator, needs to know whether the
        # webhook is present because the `request_verified_approval` event
        # is conditional on `ready_for_submission?`.
        async_webhook.then do |_webhook|
          can_request_verified_approval?
        end
      else
        false
      end
    end
  end

  # Public: Returns true if the given User can request approval to publish this listing as unverified.
  def unverified_approval_requestable_by?(actor)
    approval_request_prerequisites_met_by?(actor) && can_request_unverified_approval?
  end

  # Public: Returns true if the given User can request approval to publish this listing as unverified.
  def async_unverified_approval_requestable_by?(actor)
    return Promise.resolve(false) if actor.blank?

    async_approval_request_prerequisites_met_by?(actor).then do |prerequisites_met|
      if prerequisites_met
        # Must load webhook async because `can_request_unverified_approval?`,
        # which comes from workflow-orchestrator, needs to know whether the
        # webhook is present because the `request_unverified_approval` event
        # is conditional on `ready_for_submission?`.
        async_webhook.then do |_webhook|
          can_request_unverified_approval?
        end
      else
        false
      end
    end
  end

  def async_can_request_approval?(actor)
    return Promise.resolve(false) if actor.blank?

    async_verified_approval_requestable_by?(actor)
  end

  # Public: Returns true if the listing is approved or if the given User has
  # admin access to this listing.
  #
  # Used to check whether a user-server GitHub App should receive an
  # "unauthorized" (403) or a "not found" (404) error when accessing a
  # marketplace listing through the API.
  def readable_by?(actor)
    publicly_listed? || adminable_by?(actor)
  end

  # Public: Synchronize this listing with its representation in the search index.
  # If the listing is publicly listed and not sponsorable, it will be updated in the search index.
  # If the listing has been destroyed or archived, it will be removed from the search index.
  # This method handles both cases.
  def synchronize_search_index
    if can_remove_from_search_index?
      RemoveFromSearchIndexJob.perform_later("marketplace_listing", self.id)
    elsif publicly_listed?
      Search.add_to_search_index("marketplace_listing", self.id)
    end

    self
  end

  def can_remove_from_search_index?
    destroyed? || archived? || (listable_is_integration? && async_listable.sync.private?)
  end

  def can_viewer_see?(current_user)
    if publicly_listed?
      true
    elsif current_user.nil?
      false
    elsif current_user.user_or_org_account_has_purchased_listing?(self)
      true
    elsif current_user.can_admin_marketplace_listings?
      true
    else
      adminable_by?(current_user)
    end
  end

  def can_viewer_read_insights?(viewer)
    async_can_viewer_read_insights?(viewer).sync
  end

  def async_can_viewer_read_insights?(viewer)
    async_listable.then do |integratable|
      owner_promise = if listable_is_oauth_application?
        integratable.async_user
      elsif listable_is_integration?
        integratable.async_owner
      else
        async_owner
      end

      owner_promise.then do
        owner_or_admin?(viewer)
      end
    end
  end

  def allowed_to_edit_categories?(current_user)
    return false unless current_user

    allowed_to_edit?(current_user) && draft?
  end

  def verified_owner?
    owner.present? && owner.organization? && owner.creator_verification_state? == 2
  end

  def initiate_financial_onboarding?
    has_installation_requirements_met? && verified_owner?
  end

  def owner_verification_pending?
    owner.present? && owner.organization? && owner.creator_verification_state? == 1
  end

  def status
    if draft?
      "Draft"
    elsif verification_pending_from_draft? || unverified_pending?
      "Pending for publish"
    elsif archived?
      "Archived"
    elsif rejected?
      "Rejected"
    elsif unverified? || verification_pending_from_unverified? || verified? || verified_creator?
      "Published"
    end
  end

  def verified_listing?
    verified? || verified_creator?
  end

  # Public: Returns true if publisher verification is complete
  # and installation count requirement is satisfied
  def paid_plan_checks_met?
    verified_owner? && has_installation_requirements_met?
  end

  # Public: Returns true if app has published
  # paid plans and is owned by an org
  def show_paid_plan_checks_on_draft_listing?
    published_paid_plans? && owner.organization?
  end

  # Public: Returns true if paid plan checks are not
  # required or if paid plan checks are required and met
  def allow_app_publish?
    published_paid_plans? ? paid_plan_checks_met? : true
  end

  # Public: returns true if the listing is in a publicly listed state
  #
  # Listings must be approved as verified or unverified to be publicly
  # listed.
  def publicly_listed?
    verified? || unverified? || verification_pending_from_unverified? || verified_creator?
  end

  # Public: Determine if this listing offers a free trial.
  #
  # Returns a Boolean.
  def offers_free_trial?
    listing_plans.with_free_trial(state: :published).exists?
  end

  def publish_pending?
    unverified_pending? || verification_pending_from_draft?
  end

  def published_free_plans?
    listing_plans.free.with_published_state.exists?
  end

  def published_paid_plans?
    listing_plans.paid.with_published_state.exists?
  end

  # Public: Returns true if the given User has permission to add plans to this listing, and the
  # listing has not reached its plan limit.
  def allowed_to_add_plans?(actor)
    allowed_to_edit?(actor) && remaining_plan_count > 0
  end

  # Public: Returns true if the given User has permission to change at least some properties of
  # this listing, such as its screenshots or descriptions.
  def allowed_to_edit?(actor)
    return false if rejected? || archived?
    return true if actor && (actor.biztools_user? || actor.site_admin?)

    adminable_by?(actor)
  end

  # Public: Returns true if the given User can administer the listing, either as owner/org admin
  # for the listing's app/integration or as a biztools/site admin.
  def owner_or_admin?(actor)
    actor && (actor.biztools_user? || actor.site_admin? || adminable_by?(actor))
  end

  # Public: Returns true if this listing should be visible to the given User or
  # Organization.
  def visible_to?(actor)
    return true if publicly_listed?
    return false unless actor # require user be authenticated to see draft, verification_pending_from_draft
    return true if actor == owner # the actor could be an org in the case of integrations
    return true if listable_is_integration? && actor == listable # the actor can also be the integration itself
    return true if actor&.can_admin_marketplace_listings?

    admins.include?(actor)
  end

  # Public: Returns true if owned by GitHub org
  def owned_by_github?
    owner && owner.login == "github"
  end

  # Public: Returns a string combining the short_description and full_description of this listing.
  def description
    [short_description, full_description].select(&:present?).join("\n\n")
  end

  def full_description_html
    GitHub::Goomba::MarketplaceListingPipeline.to_html(full_description)
  end

  # Public: Returns the backing OauthApplication or Integration record for this listing.
  def integratable
    async_listable.sync if listable_type.in?(INTEGRATABLES)
  end

  # Public: Asynchronously returns the backing OauthApplication or Integration record for this listing.
  def async_integratable
    async_listable if listable_type.in?(INTEGRATABLES)
  end

  # Public: Returns a human-readable description of the kind of integratable this listing
  # represents.
  def integratable_description
    if listable_is_oauth_application?
      "application"
    elsif listable_is_integration?
      "integration"
    end
  end

  # Public: Returns the listing's very short description without a trailing period and with
  # ampersands replaced by the word "and".
  def normalized_short_description
    (short_description || "").gsub(/&/, "and").gsub(/\.\z/, "")
  end

  # Public: Returns true if the listing category is github-partner
  def partnership_managed?
    return false if categories.nil?
    categories.where(slug: "github-partners").any?
  end

  # Public: Returns true if the associated app is an Integration.
  def listable_is_integration?
    listable_type == INTEGRATION_TYPE
  end

  # Public: Returns true if the associated app is an OauthApplication.
  def listable_is_oauth_application?
    listable_type == OAUTH_APPLICATION_TYPE
  end

  # Public: Returns true if the listing has any paid plans.
  def paid?
    listing_plans.paid.count > 0
  end

  # Public: Is this listing in a billable state?
  def billable?
    verified? || archived? || verified_creator?
  end

  # Public: Is this listing featured on the Marketplace homepage?
  def featured?
    featured_at.present? && featured_at <= Time.zone.now
  end

  # Public: Does this listing meet the requirements of being featured?
  def featurable?
    verified? && hero_card_background_image_id.present?
  end

  # Public: The listing's default plan - a published free trial plan if one exists,
  #         or any published plan otherwise.
  def default_plan
    listing_plans.with_published_state.order(has_free_trial: :desc).first
  end

  # Public: Returns all non-free plans for this listing.
  def paid_listing_plans
    listing_plans.paid
  end

  # Public: Returns true if paid plans are permitted given the listing's state.
  # Prevents integrators from publishing paid plans on unverified listings.
  def published_paid_plans_allowed?
    if verification_pending_from_draft? || verified_listing?
      paid_plan_checks_met?
    elsif draft? && owner.organization?
      true
    else
      false
    end
  end

  # Public: Returns an integer count of how many more plans can be added
  # to this listing.
  def remaining_plan_count
    Marketplace::ListingPlan::PLAN_LIMIT_PER_LISTING - listing_plans.with_published_state.count
  end

  # Public: Returns true if this listing has reached the maximum allowed number
  # of published plans.
  def reached_maximum_plan_count?
    remaining_plan_count <= 0
  end

  # Public: Returns an integer count of how many more screenshots can be uploaded
  # to this listing.
  def remaining_screenshot_count
    Marketplace::ListingScreenshot::SCREENSHOT_LIMIT_PER_LISTING - screenshots.count
  end

  def event_prefix
    :marketplace_listing
  end

  def event_context(prefix: event_prefix)
    {
      "#{prefix}_id".to_sym => id,
      prefix => name,
    }
  end

  def event_payload
    payload = {
      event_prefix => self,
      :state => current_state.name,
      :primary_category => categories.first.name,
      :secondary_category => categories.count > 1 ? categories.last.name : "none",
    }
    payload[:oauth_application] = listable if listable_is_oauth_application?
    payload[:integration] = listable if listable_is_integration?
    payload[:org] = owner if owner.organization?
    payload[:user] = owner if owner.user?
    payload
  end

  # Public: Creates an audit log event for this listing's creation with the given User as the
  # actor.
  def instrument_creation(actor:)
    instrument :create, event_payload.merge(actor: actor)
  end

  # Public: Creates an audit log event for this listing changing states with the given User as the
  # actor.
  def instrument_state_change(actor:, action:, state:, orig_state:)
    case action
    when :request_unverified_approval, :request_verified_approval, :redraft, :reject, :approve, :delist, :approve_creator
      payload = event_payload.merge(actor: actor, state: state)
      instrument(action, payload)                                        # for audit logs
      instrument("state_change", payload.merge(orig_state: orig_state))  # for octolytics
    end
  end

  # Public: Creates an audit log event for the primary or secondary category changing on this
  # listing, with the given User as the actor.
  def instrument_category_changed(actor:)
    instrument :change_category, event_payload.merge(actor: actor)
  end

  # Public: Creates an audit log event for the featured at datetime changing on this
  # listing, with the given User as the actor.
  def instrument_featured_at_changed(actor:)
    instrument :change_featured_at, event_payload.merge(actor: actor, featured_at: featured_at)
  end

  # Public: Returns the signature the given user made for this listing.
  def integrator_agreement_signature_for(viewer)
    # find the agreement singed by user on behalf of owner.
    # if integrator is user --> find ig signature exists where signatory is user and Organization is nil
    # if integrator is org --> find signature where Organization is this Organization, i.e. if anyone has singed on behalf of org.
    user = viewer
    if owner.organization?
      # this means we need to find if anyone has singed an agreement on behalf of the org.
      # in-case of org owned listings there may be more than one admins, while user may not be one who singed agreement on behalf of Organization
      user = nil
    end

    org = if (user_or_org = owner).organization?
      user_or_org
    end

    Marketplace::AgreementSignature.for_integrator(user: user, organization: org)
  end

  # Public: Signs the given agreement as the given User on behalf of the listing's Organization
  # if the owner is an organization and the agreement is for integrators. Returns true if the
  # agreement was signed successfully. Returns false when given User is not allowed to sign the
  # agreement, if the agreement is nil, or if the signing fails.
  def sign_agreement(actor, agreement:)
    return false unless agreement

    if agreement.end_user?
      agreement.sign(user: actor)
    elsif agreement.integrator?
      return false unless adminable_by?(actor)

      user_or_org = owner
      org = user_or_org.organization? ? user_or_org : nil
      agreement.sign(user: actor, organization: org)
    end
  end

  # Public: Returns true if the given legal agreement has been signed by the integrator. Will
  # check for a signature on the latest version of the integrator agreement if no particular
  # version is given. Defaults to false if no appropriate legal agreement exists.
  #
  # agreement - optional; a specific Marketplace::Agreement for integrators; will default to the
  #             latest version if none is specified
  #
  # Returns a Boolean.
  def has_signed_integrator_agreement?(agreement: nil)
    agreement ||= Marketplace::Agreement.latest_for_integrators
    return false unless agreement && agreement.integrator?

    if (user_or_org = owner).user?
      agreement.signed_by?(user_or_org)
    else # organization
      agreement.signed_for?(user_or_org)
    end
  end

  # Public: Has the given User signed the end-user agreement?
  #
  # actor - a User
  # agreement - optional; a specific Marketplace::Agreement for end users; will default to the
  #             latest version if none is specified
  #
  # Returns a Boolean.
  def has_signed_end_user_agreement?(actor:, agreement: nil)
    agreement ||= Marketplace::Agreement.latest_for_end_users
    return false unless agreement && agreement.end_user?

    agreement.signed_by?(actor)
  end

  # Public: Returns true if the given User can sign the end-user agreement for this listing.
  # Defaults to false if no appropriate legal agreement exists.
  def can_sign_end_user_agreement?(user, agreement:)
    return false unless user && publicly_listed?
    return false unless agreement && agreement.end_user?

    !has_signed_end_user_agreement?(agreement: agreement, actor: user)
  end

  # Public: Returns true if the given User can sign the integrator agreement for this listing.
  # Defaults to false if no appropriate legal agreement exists.
  def can_sign_integrator_agreement?(user, agreement:)
    return false unless user
    return false unless agreement && agreement.integrator?
    return false if rejected? || archived?

    adminable_by?(user) && !has_signed_integrator_agreement?(agreement: agreement)
  end

  def has_installation_requirements_met?
    (installation_count >= required_installations_for_verification)
  end

  # Public: Emails the admins of this listing about the specified state change.
  def email_state_change(action:, old_state:, new_state:, message: nil)
    return if GitHub.enterprise?

    mailer_params = { listing: self, message: message }

    mailer_method = case action
    when :redraft
      mailer_params[:new_state] = new_state
      :listing_redrafted
    when :reject
      :listing_rejected
    when :approve
      :listing_approved
    when :approve_creator
      :listing_approved
    when :delist
      :listing_delisted
    end
    # Notify biztools admins when an integrator requests approval as a verified or unverified listing
    if action == :request_verified_approval || action == :request_unverified_approval
      MarketplaceMailer.state_changed(action: action, old_state: old_state, new_state: new_state, listing: self, message: message).deliver_later
    end

    return unless mailer_method

    admins.each do |user|
      MarketplaceMailer.send(mailer_method, **mailer_params.merge!(user: user)).deliver_later
    end
  end

  # Public: Returns true if this listing's support "URL" is actually an email address.
  def support_url_is_email?
    support_url =~ User::EMAIL_REGEX
  end

  # Public: Returns the email address to get support for this listing's product. Returns nil when
  # support_url is a URL and not an email.
  def support_email
    support_url_is_email? ? support_url : nil
  end

  # Public: Deletes Subscription Items that are associated with this listing.
  def destroy_subscription_items
    listing_plans_ids = Marketplace::ListingPlan.where(marketplace_listing_id: id).pluck(:id)
    Billing::SubscriptionItem.for_marketplace_listing_plans(listing_plans_ids).destroy_all
  end

  # Public: Update this listing's insights for a specified day
  def update_insights_for(date, metric_types = nil)
    insights.build(recorded_on: date) { |insight| insight.update_metrics!(metric_types) }
  end

  # Public: Returns true if URLs are required for this listing
  def urls_required?
    !draft?
  end

  # Public: Returns true if the listing requires and installation_url to be installed
  def requires_installation_url?
    listable_is_oauth_application?
  end

  # Public: Returns true if the listing has an installation_url or doesn't require one
  def installation_url_requirement_met?
    installation_url.present? || !requires_installation_url?
  end

  FILTER_CATEGORY_MAP = {
    "free-trials" => :offers_free_trial?,
    "free" => :published_free_plans?,
    "paid" => :published_paid_plans?,
  }

  def set_filter_categories!
    FILTER_CATEGORY_MAP.each do |category, category_check_method|
      should_have_category = self.public_send(category_check_method)
      set_category!(category, should_have_category)
    end
  end

  # Public: Returns true if the listing has all the attributes needed for the
  # integrator to request it be published to the Marketplace.
  def ready_for_submission?(require_installs_count: true)
    webhook_completed? &&
      listing_description_completed? &&
      contact_info_completed? &&
      plans_and_pricing_completed? &&
      allow_app_publish?
  end

  def ready_for_unverified_submission?(*args, **kwargs)
    !published_paid_plans? && ready_for_submission?(require_installs_count: false)
  end

  # Public: Returns true if the listing has all the attributes needed for the
  # integrator to request it be published to the Marketplace.
  def async_ready_for_submission?
    async_webhook_completed?.then do |webhook_completed|
      if webhook_completed
        listing_description_completed? && contact_info_completed? && plans_and_pricing_completed? && allow_app_publish?
      else
        false
      end
    end
  end

  # Public: Returns true if the listing has all the description attributes
  # needed for the integrator to request it be published to the Marketplace.
  def listing_description_completed?
    naming_and_links_completed? && logo_and_feature_card_completed? &&
      listing_details_completed? && product_screenshots_completed?
  end

  # Public: Returns true if the listing has the naming and links needed for the
  # integrator to request it be published to the Marketplace.
  def naming_and_links_completed?
    attributes_completed?(naming_and_links_attributes)
  end

  # Public: Returns true if the listing has all the required contact info needed
  # for the integrator to request it be published to the Marketplace.
  #
  # Sponsorable listings do not require contact info.
  def contact_info_completed?
    attributes_completed?(CONTACT_INFO_ATTRIBUTES)
  end

  # Public: Returns true if the listing has all the required logo and feature
  # card details needed for the integrator to request it be published to the
  # Marketplace.
  #
  # Sponsorable listings do not require a logo and feature card.
  def logo_and_feature_card_completed?
    attributes_completed?(LOGO_AND_FEATURE_CARD_ATTRIBUTES)
  end

  # Public: Returns true if the listing has all the descriptions needed for
  # the integrator to request it be published to the Marketplace.
  def listing_details_completed?
    attributes_completed?(LISTING_DETAILS_ATTRIBUTES)
  end

  # Public: Returns true if the listing has the plans needed for the integrator
  # to request it be published to the Marketplace.
  def plans_and_pricing_completed?
    listing_plans.with_published_state.any?
  end

  # Public: Returns true if the listing has the screenshots needed for the
  # integrator to request it be published to the Marketplace.
  #
  # Sponsorable listings do not require screenshots.
  def product_screenshots_completed?
    screenshots.any?
  end

  # Public: Returns true if the listing has the webhook needed for the
  # integrator to request it be published to the Marketplace.
  #
  # Sponsorable listings do not require a webhook.
  def webhook_completed?
    webhook.present?
  end

  # Public: Returns true if the listing has the webhook needed for the
  # integrator to request it be published to the Marketplace.
  def async_webhook_completed?
    async_webhook.then do |webhook|
      webhook.present?
    end
  end

  # Public: Creates a unique slug based on listable_type and listable_id
  #
  # This provides us a unique, non-changing slug for our product in zuora.
  # Previously, marketplace would use the name and slugified version of the
  # name for custom values in Zuora product listings. With sponsors, we
  # have much more potentional for the login and name of the user
  # (or repo name, or org name, to consider the future) to change,
  # so we need to use the listable type and id to meet the aformentioned
  # criteria.
  #
  # Returns a parameterized string
  def zuora_slug
    slug
  end

  def hero_card_background_url_for_viewer(viewer)
    return unless hero_card_background_image

    hero_card_background_image.hero_image_url(viewer)
  end

  # Public: Returns organizations that are featured for the
  # listing, with spammy orgs filtered out.
  #
  # Returns a relation.
  def featured_organizations_non_spammy
    organization_ids = featured_organizations.pluck(:organization_id)
    non_spammy_organization_ids = Organization.where(id: organization_ids).not_spammy.pluck(:id)
    featured_organizations.where(organization_id: non_spammy_organization_ids)
  end

  def platform_type_name
    "MarketplaceListing"
  end

  def reset_memoized_attributes
    remove_instance_variable(:@async_cached_installation_counts) if instance_variable_defined?(:@async_cached_installation_counts)
    remove_instance_variable(:@async_is_recommended) if instance_variable_defined?(:@async_is_recommended)
    super
  end

  # Public: A workflow transition event callback that is called when a listing is delisted.
  #
  # Returns nothing.
  def delist(*_args, **_kwargs)
    opt_out_listable_proxima_sync
  end

  private

  def set_category!(category_slug, should_have_category)
    category = Marketplace::Category.find_by(slug: category_slug)
    return unless category

    if should_have_category
      self.categories << category unless self.categories.include?(category)
    else
      self.categories.delete(category)
    end
  end

  # Used to perform validations when categories change
  attr_accessor :categories_have_duplicates, :categories_cannot_be_changed

  # Internal: Set the slug based on the Listing's name.
  #
  # Returns the slug that was set, or nil if slug was set to nil or not set.
  def set_slug
    if slug.nil? || name_changed?
      # Changing the name *to* nil is unexpected/invalid, but the slug should be
      # set to nil as well to stay in sync with the name.
      if name.nil?
        self.slug = nil
      elsif persisted? && draft?
        self.slug = name.parameterize
      else
        self.slug ||= name.parameterize
      end
    end
  end

  def categories_must_be_different
    return unless categories_have_duplicates
    errors.add(:categories, "cannot have duplicates")
  end

  def categories_not_in_draft
    return unless categories_cannot_be_changed
    errors.add(:categories, "cannot be changed since the listing is not a draft")
  end

  def at_least_one_category_not_acting_as_filter
    return if categories.any? { |category| !category.acts_as_filter? }
    return if regular_categories.any? { |category| !category.acts_as_filter? }
    errors.add(:categories, "must have at least one category")
  end

  def verified_and_hero_card_present
    return if featured_at.nil?

    unless verified?
      errors.add(:featured_at, "cannot be featured since the listing is not verified")
    end

    unless hero_card_background_image_id?
      errors.add(:featured_at, "cannot be featured since the listing does not have a hero card background")
    end
  end

  ##
  # Validates that the hero image linked is owned by the Listing
  def owns_hero_image
    return if hero_card_background_image.nil?

    unless hero_card_background_image.marketplace_listing_id == id
      errors.add(:hero_card_background_image, "not owned by this listing")
    end
  end

  def supported_languages_count_does_not_exceed_max
    if languages.size > MAX_SUPPORTED_LANGUAGES_COUNT
      errors.add(:listing, "has reached its limit for supported languages")
    end
  end

  def featured_organizations_count_does_not_exceed_max
    if featured_organizations.size > MAX_FEATURED_ORGANIZATIONS_COUNT
      errors.add(:listing, "has reached its limit for featured organizations")
    end
  end

  def listable_is_not_already_listed
    # Need this until #109861 lands and the transition in #109660 runs
    return unless listable # Need this until #109861 lands and the transition in #109660 runs

    same_listable = Marketplace::Listing.where(listable: listable)
    same_listable = same_listable.where.not(id: self.id) if self.persisted?
    errors.add(:listable, "is already listed in the Marketplace.") if same_listable.exists?
  end

  def support_url_is_url_or_email
    return unless support_url.present?
    normalized = support_url.to_s
    return if normalized =~ URL_REGEX

    unless normalized =~ User::EMAIL_REGEX
      errors.add(:support_url, "must be an email address or a URL")
    end
  end

  def integration_is_public
    return unless listable_is_integration?

    if listable.private?
      errors.add(:integration, "must be public")
    end
  end

  # Checks to see if listable_type is oauth_application, if so then application cannot be marked as a copilot app.
  def can_be_marked_as_copilot_app
    if listable_is_oauth_application? && copilot_app?
      errors.add(:base, "Only integrations can be marked as a copilot app")
    end
  end

  # Disallow submissions from users whose email address begins with 'support@', because our
  # emails about the status of their Marketplace listing will not be allowed via Mailchimp.
  def admin_email_is_not_a_support_email
    any_valid_email = admins.any? { |user| !user.email.downcase.start_with?("support@") }

    unless any_valid_email
      errors.add(:base, "At least one admin for the listing must have an email address that " +
                        "does not start with 'support@'.")
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

  # Private: update associated category counters when the listing gets approved
  # archived, or when the state is unchanged at an approved state but a category
  # has changed - eg. via biztools admin. We also make sure that the counters
  # don't change if listing gets approved from unverified to verified
  def update_category_counters(event: nil, new_categories: nil)
    if event == :approve && !publicly_listed?
      regular_categories.first&.increment!(:primary_listing_count)
      regular_categories.second&.increment!(:secondary_listing_count)
    elsif event == :delist
      regular_categories.first&.decrement!(:primary_listing_count)
      regular_categories.second&.decrement!(:secondary_listing_count)
    elsif publicly_listed? && new_categories.present?
      if regular_categories.first&.id != new_categories.first&.id
        regular_categories.first&.decrement!(:primary_listing_count)
        new_categories.first&.increment!(:primary_listing_count)
      end

      if regular_categories.second&.id != new_categories.second&.id
        regular_categories.second&.decrement!(:secondary_listing_count)
        new_categories.second&.increment!(:secondary_listing_count)
      end
    end
  end

  # Private: Given an array of symbol attribute names, returns true if the
  # listing has present values for all of those attributes.
  def attributes_completed?(attributes)
    attributes.all? { |attribute| public_send(attribute).present? }
  end

  # Private: Returns an array of symbol attribute names for the naming and links
  # attributes needed for the integrator to request it be published to the
  # Marketplace.
  def naming_and_links_attributes
    if listable_is_oauth_application?
      NAMING_AND_LINKS_ATTRIBUTES_FOR_OAUTH_APPLICATION
    else
      DEFAULT_NAMING_AND_LINKS_ATTRIBUTES
    end
  end

  # Private: Returns true if the given User meets the minimum requirements to
  # request approval to publish this listing. Does not consider whether the
  # listing has all the required attributes necessary to be published.
  def approval_request_prerequisites_met_by?(actor)
    async_approval_request_prerequisites_met_by?(actor).sync
  end

  # Private: Returns true if the given User meets the minimum requirements to
  # request approval to publish this listing. Does not consider whether the
  # listing has all the required attributes necessary to be published.
  def async_approval_request_prerequisites_met_by?(actor)
    actor.async_two_factor_authentication_enabled?.then do |two_factor_authentication_enabled|
      if two_factor_authentication_enabled
        # Copilot extensions require a verified owner in order to be published
        next false if copilot_app && actor.feature_enabled?(:marketplace_updated_verified_creator) && !verified_owner?

        !actor.spammy? &&
          adminable_by?(actor) &&
          has_signed_integrator_agreement?
      else
        false
      end
    end
  end

  def update_trade_compliance_metadata
    return unless owner&.has_saved_trade_screening_record?

    owner.trade_screening_record.save! if owner.trade_screening_record.update_marketplace_owner_metadata
  end

  # Private: Update the listable app to opt it out of syncing to Proxima stamps.
  def opt_out_listable_proxima_sync
    return unless listable_type.in?(INTEGRATABLES)

    listable.update!(proxima_availability: :unavailable)
  end
end
