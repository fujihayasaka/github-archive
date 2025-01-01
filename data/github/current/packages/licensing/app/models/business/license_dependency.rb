# typed: strict
# frozen_string_literal: true

module Business::LicenseDependency
  extend T::Helpers
  extend ActiveSupport::Concern
  include GitHub::Memoizer

  class LicensingPlatform < T::Enum
    enums do
      Default = new("default")
      Licensify = new("licensify")
    end
  end

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
  sig { returns(Integer) }
  def available_invitable_licenses
    return available_enterprise_licenses if GitHub.single_business_environment?
    return 1000 if has_unlimited_seats? # See https://github.com/github/licensing/issues/461 for more details

    [0, total_available_licenses].max
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
  sig { returns(Integer) }
  def total_purchased_licenses_with_overages
    purchased_volume_licenses_with_overages + purchased_enterprise_licenses
  end

  # Total invitable licenses purchased
  #
  # This is a temporary method until bundled license assignments are enabled for everyone. When bundled license
  # assignments are enabled only enterprise licenses are invitable from GitHub. However, when bundled license assignments
  # are disabled we allow all kinds of licenses to be used for invitations in GitHub.
  sig { returns(Integer) }
  def total_invitable_purchased_licenses
    purchased_enterprise_licenses
  end

  # Total number of consumed licenses (both standalone and bundled)
  sig { returns(Integer) }
  def total_consumed_licenses
    consumed_enterprise_licenses +
      consumed_volume_licenses
  end

  # Total number of available licenses (both standalone and bundled)
  sig { returns(Integer) }
  def total_available_licenses
    total_purchased_licenses_with_overages - total_consumed_licenses
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
    return {} unless volume_licensing_enabled?

    vss_enterprise_agreements = enterprise_agreements.visual_studio_bundle.pluck(:agreement_id)
    non_bundle_licensed_emails = license_attributer.non_bundle_licensed_emails
    suspended_user_ids = enterprise_managed_user_enabled? ? suspended_member_ids.to_set : Set[]

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

  # Returns the unique number of volume users across all owned organizations.
  sig { returns(Integer) }
  def consumed_volume_licenses
    return license_attributer.consumed_volume_licenses if GitHub.single_business_environment?

    license_usage&.consumed_volume_licenses.to_i
  end

  # Returns the unique number of enterprise users across all owned organizations.
  sig { returns(Integer) }
  def consumed_enterprise_licenses
    return ::User.count_seats_used if GitHub.single_business_environment?

    license_usage&.consumed_enterprise_licenses.to_i
  end

  sig { returns(T::Boolean) }
  def volume_licensing_enabled?
    GitHub.tracer.in_span("Business::LicenseDependency#volume_licensing_enabled?", kind: :internal) do
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

  sig { returns(Integer) }
  def purchased_enterprise_licenses
    seats.to_i
  end

  sig { params(user: T.nilable(User), email: T.nilable(String)).returns(T::Boolean) }
  def has_sufficient_licenses_for?(user: nil, email: nil)
    return false if user.nil? && email.nil?

    available_invitable_licenses > 0 ||
      additional_licenses_consumed_by(user_ids: [user&.id].compact, emails: [email].compact).zero?
  end

  sig { params(user_ids: T.nilable(T::Array[Integer]), emails: T.nilable(T::Array[String])).returns(T::Boolean) }
  def has_sufficient_licenses_for_users?(user_ids: [], emails: [])
    user_ids ||= []
    emails ||= []

    user_ids.compact!

    return false if user_ids.empty? && emails.empty?

    additional_licenses_consumed_by(user_ids: user_ids, emails: emails) <= available_invitable_licenses
  end

  # Returns the number of additional licenses the customer must purchase to add organization to business
  sig { params(organization: Organization).returns(Integer) }
  def additional_licenses_required_for_organization(organization)
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

  # Returns the number of additional licenses the customer must purchase to add repository to business
  sig { params(repository: Repository).returns(Integer) }
  def additional_licenses_required_for_repository(repository)
    user_ids = repository.member_ids + repository.repository_invitations.where.not(invitee_id: nil).pluck(:invitee_id)
    emails = repository.repository_invitations.where.not(email: nil).pluck(:email)

    [additional_licenses_consumed_by(user_ids: user_ids, emails: emails) - available_invitable_licenses, 0].max
  end

  sig { void }
  def update_license_usage
    return if GitHub.single_business_environment?
    log_license_usage_update(completed: false)
    BusinessUpdateLicenseUsageJob.perform_later(T.cast(self.id, Integer))
    BusinessUserAccountUpdateAttributesJob.enqueue(self)
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

    if match_users_to_bundled_license_emails && volume_licensing_enabled? && !unlicensed_user_ids.empty?
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
    customer&.billing_platform_enabled_product&.ghec? ||
    customer&.billing_platform_enabled_product&.copilot? ||
    customer&.billing_platform_enabled_product&.ghas? ||
    false
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

  # Adds users to a cost center.
  # Also ensures that the BusinessUserAccount attributes are updated for these users.
  #
  # uuid     - Unique identifier of the cost center
  # user_ids - An array with the ids of all users to add to the cost center
  #
  # Returns the cost center information
  sig { params(uuid: String, user_ids: T::Array[String]).returns(T.nilable(T.any(T::Hash[Symbol, T.untyped], Billing::Platform:: Api::Error))) }
  def add_resources_to_cost_center(uuid, user_ids)
    response = billing_platform_client.add_resource_to_cost_center(key: {
      customer_id: customer_id.to_s,
      uuid: uuid
    }, resources: user_ids)
    if !response.is_a?(Billing::Platform::Api::Error)
      BusinessUserAccountUpdateAttributesJob.enqueue(self, user_account_ids: BusinessUserAccount.where(business_id: self.id, user_id: user_ids.pluck(:id)).pluck(:id))
    end
    response
  end


  # Removes users from a cost center.
  # Also ensures that the BusinessUserAccount attributes are updated for these users.
  #
  # uuid     - Unique identifier of the cost center
  # user_ids - An array with the ids of all users to remove from the cost center
  #
  # Returns the cost center information
  sig { params(uuid: String, user_ids: T::Array[String]).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def remove_resources_from_cost_center(uuid, user_ids)
    response = Billing::Platform::Api::Client.new.remove_resource_from_cost_center(key: {
      customer_id: customer_id.to_s,
      uuid: uuid
    }, resources: user_ids)

    if !response.is_a?(Billing::Platform::Api::Error)
      BusinessUserAccountUpdateAttributesJob.enqueue(self, user_account_ids: BusinessUserAccount.where(business_id: self.id, user_id: user_ids.pluck(:id)).pluck(:id))
    end

    response
  end

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def metered_server_licenses
    self.ghes_licenses.order(created_at: :desc).map do |license|
      license.as_json(only: [:reference_number, :seats, :expires_at], root: false)
    end
  end

  sig { returns(T::Array[String]) }
  def issues_preventing_transition
    issues = []

    issues << "The customer is on a trial" if trial?
    issues << "The customer has Basic seats plan" if seats_plan_basic?
    issues << "The customer is on a GitHub Advanced Security trial" if advanced_security_trial_enabled_for_entity?
    issues << "The customer is on a manual GitHub Advanced Security trial set up by sales" if advanced_security_seats_for_entity == 0 && advanced_security_purchased_for_entity? && !advanced_security_metered_for_entity?

    # additional checks for customers paying via azure
    unless pays_github_directly?
      issues << "The customer has an enterprise agreement with visual studio subscription seats" if customer&.has_active_vss_enterprise_agreement?
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

    products << Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Ghec.serialize unless ghas_only

    run_ghas_reset = false
    # If the customer is not on a GHAS trial, and it is not already on metered GHAS, onboard GHAS too.
    if !self.advanced_security_trial_enabled_for_entity? &&
      !self.advanced_security_metered_for_entity?
      products << Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Ghas.serialize
      actor_id = actor.id
      if reset_ghas_configuration && !self.advanced_security_purchased_for_entity?
        run_ghas_reset = true
      end
    end

    return false if products.empty?

    customer.onboard_to_billing_platform(products: products, async: false)

    return true if ghas_only

    unless pays_github_directly?
      active_ea = enterprise_agreements.github_enterprise_unified.active.first
      active_ea&.ended!

      Licensing::EnterpriseAgreement.create(
        business: self,
        agreement_id: SecureRandom.uuid,
        category: :metered,
        status: :active,
        seats: T.must(active_ea).seats.presence || 0,
        ends_at: GitHub::Validations::DatetimeInSupportedRangeValidator::TIME_MAX
      )
    end

    # BusinessUserAccountUpdateAttributesJob updates each business user account's license type to "enterprise" once
    # business.customer.metered = true.
    BusinessUserAccountUpdateAttributesJob.enqueue(self)

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

  sig { returns(LicensingPlatform) }
  def licensing_platform
    metered_plan? ? LicensingPlatform::Licensify : LicensingPlatform::Default
  end
end
