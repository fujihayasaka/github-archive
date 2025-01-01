# typed: strict
# frozen_string_literal: true

module Business::LicenseDependency
  extend T::Helpers
  extend ActiveSupport::Concern
  include GitHub::Memoizer
  include Vexi::Actor

  requires_ancestor { Business }

  included do
    T.bind(self, T.class_of(Business))

    has_many :bundled_license_assignments, -> { T.unsafe(self).nonrevoked }, class_name: "Licensing::BundledLicenseAssignment"
    has_one :license_usage, class_name: "Business::LicenseUsage"
  end

  # Returns the consumed invitable licenses
  #
  # This is a temporary method until bundled license assignments are enabled for everyone. When bundled license
  # assignments are enabled only enterprise licenses are invitable from GitHub. However, when bundled license assignments
  # are disabled we allow all kinds of licenses to be used for invitations in GitHub.
  sig { returns(Integer) }
  def consumed_invitable_licenses
    return ::User.count_seats_used if GitHub.single_business_environment?

    consumed_enterprise_licenses
  end

  # Returns the number of available (and invitable) licenses.
  #
  # This is a temporary method until bundled license assignments are enabled for everyone. When bundled license
  # assignments are enabled only enterprise licenses are invitable from GitHub. However, when bundled license assignments
  # are disabled we allow all kinds of licenses to be used for invitations in GitHub.
  sig { params(pending_cycle: T::Boolean).returns(Integer) }
  def available_invitable_licenses(pending_cycle: false)
    return available_enterprise_licenses if GitHub.single_business_environment?
    return 1000 if has_unlimited_seats? # See https://github.com/github/licensing/issues/461 for more details

    [0, total_available_licenses(pending_cycle:)].max
  end

  # Returns the number of available (that is, not used) enterprise licenses.
  sig { returns(Integer) }
  def available_enterprise_licenses
    [0, purchased_enterprise_licenses - consumed_enterprise_licenses].max
  end

  # Total number of licenses purchased (both standalone and bundled)
  sig { returns(Integer) }
  def total_purchased_licenses
    purchased_enterprise_licenses + purchased_volume_licenses
  end

  # Returns the total number of purchased licenses in addition to overages, if they are overallocated in VSS
  sig { params(pending_cycle: T::Boolean).returns(Integer) }
  def total_purchased_licenses_with_overages(pending_cycle: false)
    purchased_volume_licenses_with_overages + purchased_enterprise_licenses(pending_cycle:)
  end

  # Total number of consumed licenses (both standalone and bundled)
  sig { returns(Integer) }
  def total_consumed_licenses
    consumed_enterprise_licenses +
      consumed_volume_licenses
  end

  # Total number of available licenses (both standalone and bundled)
  sig { params(pending_cycle: T::Boolean).returns(Integer) }
  def total_available_licenses(pending_cycle: false)
    total_purchased_licenses_with_overages(pending_cycle:) - total_consumed_licenses
  end

  # Total number of consumed licenses by users with business or org access
  sig { returns(Integer) }
  def consumed_users_access_licenses
    license_attributer.users_with_business_access[:user_ids].count +
      license_attributer.users_with_business_access[:emails].count +
      license_attributer.users_with_business_access[:unidentified_business_user_account_ids].count
  end

  sig { returns(Integer) }
  def consumed_ghec_only_users_access_licenses
    license_attributer.users_with_business_access[:user_ids].count
  end

  # Total number of consumed licenses by pending invitations
  sig { returns(Integer) }
  def consumed_pending_invitation_licenses
    license_attributer.invitations[:user_ids].count + license_attributer.invitations[:emails].count
  end

  # Returns the number of available (that is, not used) volume licenses, including overages (overallocated VSS).
  sig { returns(Integer) }
  def available_volume_licenses_with_overages
    [0, purchased_volume_licenses_with_overages - consumed_volume_licenses].max
  end

  # Returns the number of overallocated volume licenses (above the number purchased)
  sig { returns(Integer) }
  def volume_license_overages
    [0, bundled_license_assignments.count - purchased_volume_licenses].max
  end

  # Returns the unique number of volume users across all owned organizations grouped by agreement number.
  sig { returns(T::Hash[String, Integer]) }
  def consumed_volume_licenses_per_agreement_count
    return {} unless has_active_vss_bundle?

    vss_enterprise_agreements = enterprise_agreements.visual_studio_bundle.pluck(:agreement_id)
    non_bundle_licensed_emails = license_attributer.non_bundle_licensed_emails
    suspended_user_ids = enterprise_managed_user_enabled? ? suspended_member_ids(skip_business_accounts: true).to_set : Set[]

    vss_enterprise_agreements.each_with_object({}) do |agreement_number, user_count_per_agreement|
      # Count user ids that are assigned and not suspended
      volume_licensed_user_ids_by_agreement = bundled_license_assignments.assigned_user
        .where(enterprise_agreement_number: agreement_number).pluck(:user_id).to_set - suspended_user_ids
      user_count = (volume_licensed_user_ids_by_agreement - suspended_user_ids).count
      # Count volume licensed emails that are unassigned
      volume_licensed_emails_by_agreement = bundled_license_assignments.unassigned_user
        .where(enterprise_agreement_number: agreement_number).pluck(:email).map(&:downcase).to_set
      email_count = (non_bundle_licensed_emails & volume_licensed_emails_by_agreement).count
      # Add total count for this agreement to hash
      user_count_per_agreement[agreement_number] = user_count + email_count
    end
  end

  # Returns the unique number of assigned bundled licenses across all owned organizations.
  sig { returns(Integer) }
  def assigned_user_bundled_license_assignments_count
    bundled_license_assignments.assigned_user.count
  end

  # Returns the unique number of unassigned bundled licenses across all owned organizations.
  sig { returns(Integer) }
  def unassigned_user_bundled_license_assignments_count
    bundled_license_assignments.unassigned_user.count
  end

  # Returns the unique number of unassigned bundled licenses across all owned organizations grouped by agreement number.
  sig { returns(T::Hash[String, Integer]) }
  def unassigned_user_bundled_license_assignments_per_agreement_count
    bundled_license_assignments.unassigned_user.group(:enterprise_agreement_number).count
  end

  # Returns the unique number of vss users across all owned organizations.
  sig { returns(Integer) }
  def consumed_vss_licenses
    return license_attributer.consumed_vss_licenses if GitHub.single_business_environment?

    license_usage&.consumed_volume_licenses.to_i # note "volume" in this context refers to vss
  end

  # @deprecated Use {#consumed_vss_licenses} instead
  sig { returns(Integer) }
  def consumed_volume_licenses
    consumed_vss_licenses
  end

  # Returns the unique number of enterprise users across all owned organizations.
  sig { returns(Integer) }
  def consumed_enterprise_licenses
    return ::User.count_seats_used if GitHub.single_business_environment?

    license_usage&.consumed_enterprise_licenses.to_i
  end

  sig { returns(T::Boolean) }
  def has_active_vss_bundle?
    GitHub.tracer.in_span("Business::LicenseDependency#has_vss_bundle?", kind: :internal) do
      enterprise_agreements.active.visual_studio_bundle.any?
    end
  end

  sig { returns(Integer) }
  def purchased_volume_licenses
    GitHub.tracer.in_span("Business::LicenseDependency#purchased_volume_licenses", kind: :internal) do
      enterprise_agreements.active.visual_studio_bundle.sum(:seats).to_i
    end
  end

  sig { returns(Integer) }
  def purchased_volume_licenses_with_overages
    [purchased_volume_licenses, bundled_license_assignments.count].max
  end

  sig { params(pending_cycle: T::Boolean).returns(Integer) }
  def purchased_enterprise_licenses(pending_cycle: false)
    available_seats = T.let(pending_cycle_change&.seats, T.nilable(Integer)) if pending_cycle
    available_seats || seats.to_i
  end

  sig { params(user: T.nilable(User), email: T.nilable(String), pending_cycle: T::Boolean).returns(T::Boolean) }
  def has_sufficient_licenses_for?(user: nil, email: nil, pending_cycle: false)
    return false if user.nil? && email.nil?

    available_invitable_licenses(pending_cycle:) > 0 ||
      additional_licenses_consumed_by(user_ids: [user&.id].compact, emails: [email].compact).zero?
  end

  sig { params(user_ids: T.nilable(T::Array[Integer]), emails: T.nilable(T::Array[String]), pending_cycle: T::Boolean).returns(T::Boolean) }
  def has_sufficient_licenses_for_users?(user_ids: [], emails: [], pending_cycle: false)
    user_ids ||= []
    emails ||= []

    user_ids.compact!

    return false if user_ids.empty? && emails.empty?

    additional_licenses_consumed_by(user_ids: user_ids, emails: emails) <= available_invitable_licenses(pending_cycle:)
  end

  # Returns the number of additional licenses the customer must purchase to add organization to business
  sig { params(organization: Organization).returns(Integer) }
  def additional_licenses_required_for_organization(organization)
    return 0 if GitHub.single_business_environment?
    return 0 if metered_plan?
    return 0 if organization_memberships.exists?(organization: organization)
    additional_licenses_consumed = additional_licenses_consumed_by_organization(organization)
    return 0 if additional_licenses_consumed.zero?

    [additional_licenses_consumed - total_available_licenses, 0].max
  end

  # Returns the number of additional licenses that will be consumed by adding organization to business
  sig { params(organization: Organization).returns(Integer) }
  def additional_licenses_consumed_by_organization(organization)
    organization_license_attributer = Organization::LicenseAttributer.new(organization)

    additional_licenses_consumed_by(user_ids: organization_license_attributer.user_ids, emails: organization_license_attributer.emails, match_users_to_bundled_license_emails: true)
  end

  sig { params(organization: Organization).returns(T::Boolean) }
  def has_sufficient_licenses_for_organization?(organization)
    additional_licenses_required_for_organization(organization).zero?
  end

  sig { params(organization: Organization).void }
  def ensure_sufficient_licenses_for_organization!(organization)
    return if has_sufficient_licenses_for_organization?(organization)

    licenses_consumed_by_organization = additional_licenses_consumed_by_organization(organization)
    extra_licenses_required = additional_licenses_required_for_organization(organization)
    message = "Insufficient licenses to add this organization (#{pluralize(licenses_consumed_by_organization, "license")} required to add #{organization.display_login}, #{extra_licenses_required} more must be purchased for the enterprise account)"
    raise Business::CannotAddOrganizationError.new(message)
  end

  # Returns the number of additional licenses the customer must purchase to add repository to business
  sig { params(repository: Repository).returns(Integer) }
  def additional_licenses_required_for_repository(repository)
    user_ids = repository.member_ids + repository.repository_invitations.where.not(invitee_id: nil).pluck(:invitee_id)
    emails = repository.repository_invitations.where.not(email: nil).pluck(:email)

    [additional_licenses_consumed_by(user_ids: user_ids, emails: emails) - available_invitable_licenses, 0].max
  end

  sig { params(user_account_ids: T.nilable(T::Array[Integer]), license_job_delay: ActiveSupport::Duration).void }
  def update_license_usage(user_account_ids: nil, license_job_delay: 0.seconds)
    return if GitHub.single_business_environment?
    log_license_usage_update(completed: false)
    if license_job_delay > 0
      BusinessUpdateLicenseUsageJob.set(wait: license_job_delay).perform_later(T.cast(self.id, Integer))
    else
      BusinessUpdateLicenseUsageJob.perform_later(T.cast(self.id, Integer))
    end
    BusinessUserAccountUpdateAttributesJob.enqueue(self, user_account_ids: user_account_ids)
  end

  sig { params(completed: T::Boolean).void }
  def log_license_usage_update(completed:)
    return if GitHub.single_business_environment?
    GitHub.logger.info("license usage update", {
      "gh.backtrace": Rails.backtrace_cleaner.clean(caller).join("\n").truncate(15000),
      "gh.business.id": id,
      "gh.business.slug": slug,
      "gh.license_usage.completed": completed,
      "gh.license_usage.consumed_enterprise_licenses": license_usage&.consumed_enterprise_licenses,
      "gh.license_usage.consumed_volume_licenses": license_usage&.consumed_volume_licenses,
      "gh.license_usage.generated_at": license_usage&.generated_at,
      "gh.business.seats": seats
    })
  end

  sig { returns(::Business::LicenseAttributer) }
  memoize def license_attributer
    T.bind(self, Business)
    Business::LicenseAttributer.new(self)
  end

  sig { returns(Business::PassThroughCache) }
  def license_attributer_cache
    Business::PassThroughCache.new(
      "business",
      license_usage&.cache_seed.to_i,
      id,
      disabled: GitHub.single_business_environment? || !persisted? || license_usage.blank?
    )
  end

  sig { void }
  def license_attributer_cache_clear
    return if GitHub.single_business_environment?
    license_usage&.touch(:generated_at)
  end

  sig do
    params(
      user_ids: T.any(T::Array[Integer], T::Set[Integer]),
      emails: T.any(T::Array[String], T::Set[String]),
      match_users_to_bundled_license_emails: T::Boolean
    ).returns(Integer)
  end
  def additional_licenses_consumed_by(user_ids: [], emails: [], match_users_to_bundled_license_emails: false)
    licensed_user_ids = license_attributer.user_ids
    unlicensed_user_ids = user_ids.to_set - licensed_user_ids

    unlicensed_emails = if emails.any?
      existing_user_emails = UserEmail.verified.where(user_id: licensed_user_ids).pluck(:email).map(&:downcase).to_set
      licensed_emails = license_attributer.emails + existing_user_emails
      emails.filter_map(&:downcase).to_set - licensed_emails
    else
      []
    end

    if match_users_to_bundled_license_emails && has_active_vss_bundle? && !unlicensed_user_ids.empty?
      # BundledLicenseAssignment and UserEmail are in different datagbases, so we can't subquery
      bundled_license_emails = bundled_license_assignments.unassigned_user.pluck(:email)
      # As of now, there is no index on (user_id, email) for user_emails so select on email and intersect with unlicensed_user_ids
      # for faster query on large number of email
      matching_user_ids = UserEmail.verified.where(email: bundled_license_emails).pluck(:user_id).to_set & unlicensed_user_ids
      unlicensed_user_ids = unlicensed_user_ids - matching_user_ids
    end

    unlicensed_user_ids.count + unlicensed_emails.count
  end

  # Whether the business has an unlimited number of GHEC licenses.
  sig { returns(T::Boolean) }
  memoize def has_unlimited_seats?
    return false if self.trial?

    !!self.metered_plan?
  end

  # Whether the admin of a business can manage the number of seats.
  sig { returns(T::Boolean) }
  memoize def can_manage_seats?
    return false if has_unlimited_seats? || self.metered_plan?

    true
  end

  # Whether the business can have user-specific cost centers.
  #
  # Valid for billing platform enabled products that support user specific cost centers.
  sig { returns(T::Boolean) }
  memoize def user_scoped_cost_centers?
    GitHub.billing_enabled?
  end

  sig { returns(T.nilable(T::Hash[String, String])) }
  memoize def cost_centers_by_user_id
    return nil if cost_centers.nil?

    user_hash = {}
    cost_centers&.each do |cost_center|
      cost_center.dig(:resources)&.each do |resource|
        next unless resource.dig(:type) == :User
        user_hash[resource.dig(:id)] = cost_center.dig(:name)
      end
    end

    user_hash
  end

  sig { returns(T.nilable(T::Hash[String, T::Array[String]])) }
  memoize def cost_centers_with_user_id
    return nil if cost_centers.nil?

    cost_center_hash = {}
    cost_centers&.each do |cost_center|
      uuid = cost_center.dig(:costCenterKey, :uuid)
      next nil unless uuid
      cost_center_hash[uuid] = cost_center.dig(:resources)&.map do |resource|
        next nil unless resource.dig(:type) == :User
        resource.dig(:id)
      end
    end

    cost_center_hash
  end

  # Alias for the cost_center_for_id method.
  sig { params(user: T.nilable(User)).returns(T.nilable(String)) }
  def cost_center_for(user)
    return nil unless user
    cost_center_for_id(user.id)
  end

  # Get user's cost center from the cost_centers_by_user_id hash.
  #
  # Return the cost center name if the user is found in the cost_centers_by_user_id hash.
  sig { params(user_id: T.nilable(Integer)).returns(T.nilable(String)) }
  def cost_center_for_id(user_id)
    return nil unless user_id
    return nil if cost_centers.nil?

    cost_centers_by_user_id&.dig(user_id.to_s)
  end

  sig { returns(T::Array[String]) }
  memoize def duplicate_cost_center_names
    return [] if cost_centers.nil?

    cost_center_names = cost_centers&.map { |cost_center| cost_center.dig(:name)&.parameterize }
    duplicate_names = cost_center_names&.group_by { |e| e }&.select { |_, v| v.size > 1 }&.keys || []
  end

  # Adds users and/or orgs to a cost center.
  # Also ensures that the BusinessUserAccount attributes are updated for these users and orgs.
  #
  # uuid     - Unique identifier of the cost center
  # entity_ids - An array with the ids of all users or orgs or repos to add to the cost center
  #
  # Returns the cost center information
  sig { params(uuid: String, entity_ids: T::Array[String]).returns(T.nilable(T.any(T::Hash[Symbol, T.untyped], Billing::Platform:: Api::Error))) }
  def add_resources_to_cost_center(uuid, entity_ids)
    user_entity_ids = entity_ids.select { |entity| entity["type"] == BillingPlatform::Base::ResourceType::User }

    response = billing_platform_client.add_resource_to_cost_center(key: {
      customer_id: customer_id.to_s,
      uuid: uuid
    }, resources: entity_ids)
    if !response.is_a?(Billing::Platform::Api::Error)
      BusinessUserAccountUpdateAttributesJob.enqueue(self, user_account_ids: BusinessUserAccount.where(business_id: self.id, user_id: user_entity_ids.pluck(:id)).pluck(:id))
    end
    response
  end


  # Removes users from a cost center.
  # Also ensures that the BusinessUserAccount attributes are updated for these users.
  #
  # uuid       - Unique identifier of the cost center
  # entity_ids - An array with the entities to remove from the cost center. Each element can be:
  #              - Hash with "type"/"id" or :type/:id keys (preferred format)
  #              - Array with [id, type] format
  #              - Raw string (legacy format, always treated as user ID)
  #
  # Returns the cost center information
  sig { params(uuid: String, entity_ids: T::Array[T.untyped]).returns(T.any(T.nilable(T::Hash[Symbol, T.untyped]), Billing::Platform::Api::Error)) }
  def remove_resources_from_cost_center(uuid, entity_ids)
    # Defensive handling: entity elements may be hashes (preferred), arrays, or raw strings (legacy)
    user_ids_for_job = entity_ids.filter_map do |entity|
      case entity
      when Hash
        if (entity["type"] || entity[:type]) == BillingPlatform::Base::ResourceType::User
          entity["id"] || entity[:id]
        end
      when Array
        if entity[1] == BillingPlatform::Base::ResourceType::User
          entity[0]
        end
      else
        # legacy string form, always treated as a user
        entity.to_s
      end
    end

    response = Billing::Platform::Api::Client.new.remove_resource_from_cost_center(key: {
      customer_id: customer_id.to_s,
      uuid: uuid
    }, resources: entity_ids)

    if !response.is_a?(Billing::Platform::Api::Error) && user_ids_for_job.any?
      BusinessUserAccountUpdateAttributesJob.enqueue(self, user_account_ids: BusinessUserAccount.where(business_id: self.id, user_id: user_ids_for_job).pluck(:id))
    end

    response
  end

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def metered_server_licenses
    self.ghes_licenses.order(created_at: :desc).map do |license|
      license.as_json(only: [:reference_number, :seats, :expires_at, :code_security_enabled, :secret_protection_enabled], root: false)
    end
  end

  sig { returns(T::Array[String]) }
  def issues_preventing_transition
    issues = []

    issues << "The customer is on a trial" if trial?
    issues << "The customer is on a GitHub Advanced Security trial" if advanced_security_trial_enabled_for_entity?
    unless advanced_security_metered_for_entity?
      issues << "The customer is on a manual GitHub Advanced Security trial set up by sales" if advanced_security_seats_for_entity == 0 && ghas_sku_purchased_for_entity?
      issues << "The customer is on a manual Secret Protection trial set up by sales" if secret_scanning_license_count == 0 && secret_protection_purchased_for_entity?
      issues << "The customer is on a manual Code Security trial set up by sales" if code_security_license_count == 0 && code_security_purchased_for_entity?
    end

    # additional checks for customers paying via azure
    unless pays_github_directly?
      issues << "The customer with enterprise agreement doesn't have valid azure subscription setup" if customer&.invalid_azure_subscription_detected?
    end

    issues
  end

  sig { returns(T::Boolean) }
  def eligible_for_metered_licensing?
    issues_preventing_transition.empty?
  end

  sig { returns(T::Array[String]) }
  def issues_preventing_ghas_transition
    issues = []

    issues << "The customer is on a trial" if trial?
    issues
  end

  sig { returns(T::Boolean) }
  def eligible_for_metered_ghas?
    issues_preventing_ghas_transition.empty?
  end

  sig { params(actor: User, ghas_only: T.nilable(T::Boolean), reset_ghas_configuration: T.nilable(T::Boolean)).returns(T::Boolean) }
  def enable_metered_product_suite(actor:, ghas_only: false, reset_ghas_configuration: false)
    return false if !ghas_only && !eligible_for_metered_licensing?
    return false if ghas_only && !eligible_for_metered_ghas?
    customer = self.customer
    return false unless customer.present?

    customer.update!(metered_plan: true) unless ghas_only

    products = [
      Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Actions.serialize,
      Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Codespaces.serialize,
      Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Copilot.serialize,
      Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Git_Lfs.serialize,
      Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Packages.serialize,
    ]

    run_ghas_reset = false
    # If the customer is not on a GHAS trial, and it is not already on metered GHAS, onboard GHAS too.
    if !self.advanced_security_trial_enabled_for_entity? &&
      !self.advanced_security_metered_for_entity?
      actor_id = actor.id
      if reset_ghas_configuration && !self.advanced_security_purchased_for_entity?
        run_ghas_reset = true
      end
    end

    # Note that onboard_to_all_billing_platform_products will not override the GHAS offering
    # if they already have it in some form.
    customer.onboard_to_all_billing_platform_products(async: false, unbundle_ghas: nil)

    return true if ghas_only

    unless pays_github_directly?
      active_ea = enterprise_agreements.github_enterprise_unified.active.first
      active_ea&.ended!

      unless enterprise_agreements.metered.active.any?
        Licensing::EnterpriseAgreement.create(
          business: self,
          agreement_id: SecureRandom.uuid,
          category: :metered,
          status: :active,
          seats: active_ea&.seats.presence || 0,
          ends_at: GitHub::Validations::DatetimeInSupportedRangeValidator::TIME_MAX
        )
      end
    end

    # BusinessUserAccountUpdateAttributesJob updates each business user account's license type to "enterprise" once
    # business.customer.metered = true.
    BusinessUserAccountUpdateAttributesJob.enqueue(self)
    if FeatureFlag.vexi.enabled?(:licensing_metered_transition_reset_seats, business, default: false)
      business.update!(seats: 0)
    end

    # metered plans are only compatible with a monthly plan
    if plan_duration != Business::BillingDependency::MONTHLY_PLAN && actor.present?
      Billing::SchedulePlanChange.run \
        account: T.unsafe(self),
        actor: actor,
        plan_duration: Business::BillingDependency::MONTHLY_PLAN,
        active_on: GitHub::Billing.today
    end

    if run_ghas_reset
      SecurityAnalysisSettingsBatchUpdateBusinessJob.perform_now(
        owner: self,
        update_type: :advanced_security_disable_all,
        actor_id: actor_id,
        entity_type: :organization,
      )

      UpdateBusinessSecurityFeatureForNewReposJob.perform_now(
        T.cast(self, Business),
        :advanced_security,
        :disable,
        actor_id
      )
    end

    true
  end

  # Finds metered transition scheduled for the future
  sig { returns(T.nilable(Licensing::LicensingModelTransition)) }
  def future_metered_transition
    customer&.licensing_model_transitions
      &.where(
        status: "scheduled",
        licensing_model: "metered"
      )
      &.where("transition_date > ?", Date.current)
      &.order(:transition_date)
      &.first
  rescue GitHub::DatabaseQueryDisabler::DatabaseDisabledError
    nil
  end

  # Calculates amount saved by transitioning to metered billing
  sig { returns(Integer) }
  def metered_amount_saved
    begin
      total_seats = seats || 0
      consumed_licenses = consumed_enterprise_licenses
      metered_ghe_license_price = GitHub::Plan.business_plus.cost
      [total_seats - consumed_licenses, 0].max * metered_ghe_license_price
    rescue GitHub::DatabaseQueryDisabler::DatabaseDisabledError
      0
    end
  end

  sig { params(current_user: T.nilable(User), on_licensing_page: T::Boolean).returns(T::Boolean) }
  def eligible_for_self_serve_metered_transition?(current_user:, on_licensing_page:)
    return false if GitHub.enterprise?
    return false unless on_licensing_page
    return false unless current_user&.feature_flag_enabled?(:licensing_self_serve_metered_ui, default: false)
    return false unless owner?(current_user)
    return false if trial?
    return false if metered_plan?
    return false if future_metered_transition.present?
    # sales_serve_plan_subscription == nil indicates self-serve
    return false if sales_serve_plan_subscription.present? && sales_serve_plan_subscription&.self_serve_eligible?
    # coupons aren't valid for metered businesses, will help avoid escalations to prevent these transitions
    return false if has_an_active_coupon?
    # another indicator of a sales-serve business
    return false if has_active_vss_bundle?
    # businesses with a trade restriction cannot transition to metered
    return false if has_commercial_interaction_restriction?
    # eligible cohort is using at least 70% of their available volume licenses
    license_utilization_percent = consumed_enterprise_licenses.to_f / purchased_enterprise_licenses
    return false if purchased_enterprise_licenses.zero? || license_utilization_percent < 0.7

    true
  rescue GitHub::DatabaseQueryDisabler::DatabaseDisabledError
    false
  end
end
