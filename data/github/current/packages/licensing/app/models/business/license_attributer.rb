# typed: strict
# frozen_string_literal: true

# Contains information about users consuming a license in a business.
# Can optionally include non-licensed users in the license usage hash.
class Business::LicenseAttributer
  include GitHub::Memoizer
  include Licensing::Licensify

  include BundledLicenseAssignmentDependency
  include CollaboratorDependency
  include EnterpriseInstallationDependency
  include InvitesDependency

  sig { returns(Business) }
  attr_reader :business
  sig { returns(T::Hash[Symbol, T::Boolean]) }
  attr_reader :options
  sig { returns(Billing::Platform::Api::Client) }
  attr_reader :billing_platform_client

  SKU = "ghec_seats"

  UserSubscribedRange = T.type_alias do
    {
      user_id: Integer,
      subscription_start: T.nilable(DateTime),
      subscription_end: T.nilable(DateTime),
      active: T::Boolean
    }
  end

  LicenseCounts = T.type_alias do
    {
      ghe_active_cloud_user_count: Integer,
      ghe_active_server_only_user_count: Integer,
      ghe_suspended_cloud_user_count: Integer,
      ghe_suspended_server_only_user_count: Integer,
      ghe_deactivated_cloud_user_count: Integer,
      ghe_deactivated_server_only_user_count: Integer,
      bundled_ghas_active_cloud_user_count: Integer,
      bundled_ghas_active_server_only_user_count: Integer,
      bundled_ghas_suspended_cloud_user_count: Integer,
      bundled_ghas_suspended_server_only_user_count: Integer,
      bundled_ghas_deactivated_cloud_user_count: Integer,
      bundled_ghas_deactivated_server_only_user_count: Integer,
    }
  end

  # Initialize a LicenseAttributer.
  #
  # options - Hash of options to add to the LicenseAttributer (default: {}).
  #           :include_nonlicensed_roles - The LicenseAttributer will include roles that do not consume a license,
  #                                        ie, Billing Managers, Pending Enterprise Administrators.
  #                                        Only license_usage_hash includes these roles.
  #           :include_users_removed_this_cycle - The LicenseAttributer will include users who had access in the
  #                                        current billing period, but no longer do.
  sig { params(business: Business, options: T::Hash[Symbol, T::Boolean]).void }
  def initialize(business, options: {})
    @business = business
    @options = options
    @billing_platform_client = T.let(Billing::Platform::Api::Client.new, Billing::Platform::Api::Client)
  end

  # Returns the unique number of enterprise users across all owned organizations.
  sig { returns(Integer) }
  def consumed_enterprise_licenses
    return ::User.count_seats_used if GitHub.single_business_environment?

    licensing_platform = business.licensing_platform

    GitHub.tracer.in_span("Business::LicenseAttributer#consumed_enterprise_licenses", kind: :internal, attributes: { "gh.licensing.platform" => licensing_platform.serialize }) do
      GitHub.dogstats.distribution_time("business_license_attributer.consumed_enterprise_licenses.time", tags: ["gh.licensing.platform:#{licensing_platform.serialize}"]) do
        return licensify_licensee_count if licensing_platform == Business::LicenseDependency::LicensingPlatform::Licensify && business.feature_enabled?(:licensing_server_users_from_licensify)
        return unique_count unless business.volume_licensing_enabled? # note "volume" here means "VSS"

        # volume_user_ids and user_ids are overlapping sets so do set subtraction
        user_count = (user_ids - bla_licensed_user_ids).count
        # volume_emails and emails are overlapping sets so do set subtraction
        email_count = (emails - bla_licensed_emails).count
        ubua_count = unidentified_business_user_account_ids.count

        user_count + email_count + ubua_count
      end
    end
  end

  # Returns the unique number of volume users across all owned organizations.
  sig { returns(Integer) }
  def consumed_volume_licenses
    GitHub.tracer.in_span("Business::LicenseAttributer#consumed_volume_licenses", kind: :internal) do
      return 0 unless business.volume_licensing_enabled?

      user_ids = bla_licensed_user_ids

      if business.enterprise_managed_user_enabled?
        user_ids -= T.must(suspended_member_ids)
      end

      user_count = user_ids.count
      email_count = (non_bundle_licensed_emails & bla_licensed_emails).count

      user_count + email_count
    end
  end

  # IDs of users consuming a license
  sig { returns(T::Set[Integer]) }
  memoize def user_ids
    GitHub.tracer.in_span("Business::LicenseAttributer#user_ids", kind: :internal) do
      user_ids = user_ids_with_access

      # Pending member invitations and outside collaborator invites consume licenses in volume licensing mode but not for metered plans
      user_ids += user_ids_invitations if !business.metered_plan?
      user_ids += user_ids_that_had_access_removed_this_cycle if business.metered_plan? && include_users_removed_this_cycle?

      user_ids
    end
  end

  sig { returns(T::Set[String]) }
  memoize def non_bundle_licensed_emails
    GitHub.tracer.in_span("Business::LicenseAttributer#non_bundled_licensed_emails", kind: :internal) do
      non_bundle_licensed_emails = emails_with_access
      non_bundle_licensed_emails += (
        non_expired_pending_member_invitations_emails +
        pending_collaborator_invitation_emails
      ) unless business.metered_plan?

      (
        non_bundle_licensed_emails.map(&:downcase) -
        # Members being invited to more than one organization in the business should not be double counted.
        verified_business_user_emails.map { |email_record| email_record[:email].downcase }
      ).to_set
    end
  end

  sig { returns(T::Set[String]) }
  memoize def emails
    GitHub.tracer.in_span("Business::LicenseAttributer#emails", kind: :internal) do
      (
        non_bundle_licensed_emails +
        T.must(bundled_license_assignment_emails)
      ).map(&:downcase).to_set
    end
  end

  # A user/email will consume a license if at least one of the following is true:
  #
  # 1. They are an admin of a managed organization
  # 2. They are a member of a managed organization (except if they have the role of billing manager)
  # 3. They are an outside collaborator on a private repository owned by a managed organization (except forks)
  # 4. They have a pending invitation to a managed organization (except if the invitation is for a role of billing manager or if the enterprise has metered licensing)
  # 5. They have a pending invitation to a private repository owned by a managed organization (except forks or if the enterprise has metered licensing)
  #
  # In addition to associations with managed organizations, users from connected Enterprise Server instances will consume
  # a license.
  sig { returns(Integer) }
  memoize def unique_count
    GitHub.tracer.in_span("Business::LicenseAttributer#unique_count", kind: :internal) do
      email_records = verified_business_user_emails
      user_ids_with_emails = email_records.pluck(:user_id).uniq
      user_ids_without_emails = user_ids - user_ids_with_emails

      user_emails = email_records.map { |email_record| email_record[:email].downcase }.uniq
      emails_without_user_ids = emails - user_emails

      count_licenses_by_email = user_ids_with_emails.count + emails_without_user_ids.count
      count_licenses_by_ids = user_ids_without_emails.count + unidentified_business_user_account_ids.count

      count_licenses_by_email + count_licenses_by_ids
    end
  end

  DEFAULT_PER_PAGE = 30
  MAX_PER_PAGE = 100
  sig { params(pagination: T::Boolean, page: Integer, per_page: Integer).returns(T::Hash[Symbol, T.untyped]) }
  def license_usage_hash(pagination: false, page: 1, per_page: DEFAULT_PER_PAGE)
    GitHub.tracer.in_span("Business::LicenseAttributer#license_usage_hash", kind: :internal) do
      Business::LicenseCsvUsageBuilder.new(self).process(pagination: pagination, page: page, per_page: per_page)
    end
  end

  # Licensed users who have access to business resources.
  # Does not include invite-only users
  sig { returns({ emails: T::Set[String], unidentified_business_user_account_ids: T::Set[Integer], user_ids: T::Set[Integer] }) }
  def users_with_business_access
    {
      emails: emails_with_access,
      unidentified_business_user_account_ids: unidentified_business_user_account_ids.to_set,
      user_ids: user_ids_with_access,
    }
  end

  # Returns an array of user ids in roles not consuming a license.
  sig { returns(T::Array[Integer]) }
  memoize def nonlicensed_roles_user_ids
    nonlicensed_roles_user_ids = (
      T.must(nonlicensed_outside_collaborator_ids) +
      admin_ids +
      business_pending_admin_invites_user_ids +
      public_collaborator_invitations_user_ids +
      business_unaffiliated_user_ids
    )
    nonlicensed_roles_user_ids += user_ids_invitations.to_a if business.metered_plan?

    nonlicensed_roles_user_ids
  end

  # Returns an array of emails in roles not consuming a license.
  sig { returns(T::Array[String]) }
  memoize def nonlicensed_roles_emails
    nonlicensed_roles_emails = (
      business_pending_admin_invites_emails +
      public_collaborator_invitations_emails
    )
    if business.metered_plan?
      nonlicensed_roles_emails += (
        non_expired_pending_member_invitations_emails +
        pending_collaborator_invitation_emails
      )
    end
    if volume_licensing_enabled
      nonlicensed_roles_emails += pending_bundled_license_assignment_emails
    end

    nonlicensed_roles_emails
  end

  # Returns subscription start and end dates for users who have been subscribed recently
  sig { returns(T::Hash[Integer, UserSubscribedRange]) }
  memoize def recent_user_subscription_information
    return {} unless business.metered_plan?

    subscription_range_by_user || {}
  end

  # Subset of user_ids that had access in the current billing period, but no longer do.
  sig { returns(T::Set[Integer]) }
  memoize def user_ids_that_had_access_removed_this_cycle
    start_of_billing_period = ::GitHub::Billing.today.beginning_of_month.beginning_of_day

    user_ids = Set.new
    recent_user_subscription_information.each do |user_id, subscriber|
      if subscriber[:subscription_end].nil? || subscriber[:subscription_end] > start_of_billing_period
        user_ids.add(user_id)
      end
    end

    user_ids
  end

  # Subset of user_ids, limited to those with access to business resources.
  # Does not include invite-only users.
  sig { returns(T::Set[Integer]) }
  memoize def user_ids_with_access
    GitHub.tracer.in_span("Business::LicenseAttributer#user_ids_with_access", kind: :internal) do
      user_ids_with_access = (
        business_org_member_and_private_outside_collaborator_ids +
        T.must(business_enterprise_installation_user_ids) +
        T.must(bundled_license_assignment_user_ids)
      ).to_set

      if @business.enterprise_managed_user_enabled?
        user_ids_with_access -= T.must(suspended_member_ids)
      end

      user_ids_with_access
    end
  end

  # Subset of emails, limited to those with access to business resources.
  # Does not include invite-only users.
  # Does not include unassigned bundled licenses.
  sig { returns(T::Set[String]) }
  memoize def emails_with_access
    primary_emails_of_user_accounts_with_only_emails.map(&:downcase).to_set -
    # Exclude emails that are associated with members of the business to prevent double counting
    verified_business_user_emails.map { |email_record| email_record[:email].downcase }
  end

  # Note: `business_organization_member_ids` should be considered deprecated and replaced by `business_org_member_and_private_outside_collaborator_ids` for license counts.
  # Only Business::LicenseCsvUsageBuilder should still be using `business_organization_member_ids` for now.
  sig { returns(T::Array[Integer]) }
  memoize def business_organization_member_ids
    licensing_platform = business.licensing_platform

    GitHub.tracer.in_span("Business::LicenseAttributer#business_organization_member_ids", kind: :internal, attributes: { "gh.licensing.platform" => licensing_platform.serialize }) do
      GitHub.dogstats.distribution_time("business_license_attributer.business_organization_member_ids.time", tags: ["gh.licensing.platform:#{licensing_platform.serialize}"]) do
        if licensing_platform == Business::LicenseDependency::LicensingPlatform::Licensify
          return business_organization_member_ids_licensify
        else
          return business.organization_member_ids
        end
      end
    end
  end

  # users suspended across platforms
  # more details here - https://github.com/github/github/pull/353420
  sig { params(skip_cache: T.nilable(T::Boolean)).returns(T.nilable(T::Array[Integer])) }
  def suspended_member_ids(skip_cache: false)
    return @suspended_member_ids if defined?(@suspended_member_ids)

    suspended_member_ids = business.license_attributer_cache.ids("updated_suspended_member_ids", skip_cache: skip_cache) do
      # store the results here so we can use them in the select
      business_suspended_member_ids = self.business_suspended_member_ids(skip_cache:)&.to_set || []
      suspended_enterprise_installation_user_ids = self.suspended_enterprise_installation_user_ids(skip_cache:)&.to_set || []
      business_enterprise_installation_user_ids = self.business_enterprise_installation_user_ids(skip_cache:)&.to_set || []

      all_suspended_ids = (business_suspended_member_ids + suspended_enterprise_installation_user_ids).uniq

      all_suspended_ids.select do |user_id|
        suspended_cloud = business_suspended_member_ids.include?(user_id)
        suspended_server = suspended_enterprise_installation_user_ids.include?(user_id)

        # only check for server suspension if the user has a server account
        if business_enterprise_installation_user_ids.include?(user_id)
          suspended_cloud && suspended_server
        else
          suspended_cloud
        end
      end
    end

    @suspended_member_ids = T.let(suspended_member_ids, T.nilable(T::Array[Integer]))
  end

  sig { params(skip_cache: T.nilable(T::Boolean)).returns(T.nilable(T::Array[Integer])) }
  def business_suspended_member_ids(skip_cache: false)
    return @business_suspended_member_ids if defined?(@business_suspended_member_ids)

    @business_suspended_member_ids = T.let(
      business.license_attributer_cache.ids("suspended_member_ids", skip_cache: skip_cache) do
        business.suspended_member_ids || []
      end,
      T.nilable(T::Array[Integer])
    )
  end

  sig { returns(T::Set[Integer]) }
  memoize def volume_licensed_user_ids
    business.bundled_license_assignments.assigned_user.pluck(:user_id).to_set
  end

  sig { returns(T::Array[String]) }
  memoize def primary_emails_of_user_accounts_with_only_emails
    business.user_accounts_with_only_emails.
      distinct(false). # Since we're grouping on the ID which will be unique we don't need this (and save ~100ms for some queries without it)
      group(:id).
      pluck("MIN(email)") # Grab the first primary email address if they have multiple
  end

  sig { returns(T::Array[Integer]) }
  memoize def admin_ids
    GitHub.tracer.in_span("Business::LicenseAttributer#admin_ids", kind: :internal) do
      business.admins.pluck(:id)
    end
  end

  sig { returns(T::Array[Integer]) }
  memoize def business_unaffiliated_user_ids
    return [] unless business.supports_unaffiliated_user_accounts?
    business.user_accounts.exclusive_unaffiliated_role.pluck(:user_id).compact.uniq
  end

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  memoize def verified_business_user_emails
    T.unsafe(UserEmail.verified).batched_scope(:user_id, values: user_ids).pluck(:user_id, :email).map do |user_id, email|
      { user_id: user_id, email: email }
    end
  end

  sig { returns(T::Boolean) }
  memoize def volume_licensing_enabled
    business.volume_licensing_enabled?
  end

  sig { returns(T::Set[String]) }
  memoize def bla_licensed_emails
    business.bundled_license_assignments.unassigned_user.pluck(:email).map(&:downcase).to_set
  end

  sig { returns(T::Set[Integer]) }
  memoize def bla_licensed_user_ids
    business.bundled_license_assignments.assigned_user.pluck(:user_id).to_set
  end

  sig { returns(T::Boolean) }
  def include_nonlicensed_roles?
    options[:include_nonlicensed_roles].presence || false
  end

  sig { returns(T::Boolean) }
  def include_users_removed_this_cycle?
    options[:include_users_removed_this_cycle].presence || false
  end

  sig { returns(T::Array[Integer]) }
  memoize def business_org_member_and_private_outside_collaborator_ids
    licensing_platform = business.licensing_platform

    GitHub.tracer.in_span("Business::LicenseAttributer#business_org_member_and_private_outside_collaborator_ids", kind: :internal, attributes: { "gh.licensing.platform" => licensing_platform.serialize }) do
      GitHub.dogstats.distribution_time("business_license_attributer.business_org_member_and_private_outside_collaborator_ids.time", tags: ["gh.licensing.platform:#{licensing_platform.serialize}"]) do
        if licensing_platform == Business::LicenseDependency::LicensingPlatform::Licensify
          business_org_member_and_private_outside_collaborator_ids_licensify
        else
          (business.organization_member_ids + T.must(private_outside_collaborator_ids)).to_set.to_a
        end
      end
    end
  end

  sig { returns(T.nilable(T::Array[Integer])) }
  def business_private_outside_repo_collaborator_ids_licensify_for_csv_generation_only
    return @business_private_outside_repo_collaborator_ids_licensify_for_csv_generation_only if defined?(@business_private_outside_repo_collaborator_ids_licensify_for_csv_generation_only)

    set_licensify_collections
    @business_private_outside_repo_collaborator_ids_licensify_for_csv_generation_only
  end

  sig { returns(T.nilable(T::Hash[Integer, UserSubscribedRange])) }
  def subscription_range_by_user
    return @subscription_range_by_user if defined?(@subscription_range_by_user)
    set_licensify_collections
    @subscription_range_by_user
  end

  sig { returns(T.nilable(T::Array[Integer])) }
  def org_member_user_ids_for_csv_generation_only
    return @org_member_user_ids_for_csv_generation_only if defined?(@org_member_user_ids_for_csv_generation_only)
    set_licensify_collections
    @org_member_user_ids_for_csv_generation_only
  end

  # Note: This is expected to be used for Business::LicenseCsvUsageBuilder only.
  # Querying with GetCustomerLicensesRequest instead of GetLicenseeIdsRequest is a perf hit
  # and the outsideness checks here don't help!
  sig { returns(T::Array[Integer]) }
  def set_licensify_collections
    customer_licenses = business_customer_licenses_for_csv_generation_only
    collaborator_repo_ids = T.let([], T::Array[Integer])
    org_member_user_ids = T.let([], T::Array[Integer])
    subscription_rangees = T.let({}, T::Hash[Integer, UserSubscribedRange])

    customer_licenses.each do |license|
      licensee = T.must(license.licensee)
      licensee_id = licensee.id.to_i

      unless licensee.type == :LICENSEE_TYPE_ENTERPRISE_SERVER_USER
        # Any customer_license with enablement reason `ENABLEMENT_REASON_REPOSITORY_COLLABORATOR` is a private repo collaborator.
        # Collect all those enablement ids and then get the repo ids for each one.
        collaborator_repo_ids += license
          .enablements
          .select { |e| e.reason == :ENABLEMENT_REASON_REPOSITORY_COLLABORATOR }
          .flat_map(&:enablementIds).map(&:to_i)

        # Collect all licenses that are org members
        if license.enablements.any? { |e| e.reason == :ENABLEMENT_REASON_ORG_MEMBERSHIP }
          org_member_user_ids << licensee_id
        end

        subscription_end = Google::Protobuf::Timestamp.new(seconds: 253402300799, nanos: 0) == license.expiresAt ? nil : license.expiresAt&.to_time&.to_datetime

        subscription_rangees[licensee_id] = {
          user_id: licensee_id,
          subscription_start: nil,
          subscription_end: subscription_end,
          active: license.licenseStatus == :LICENSE_STATUS_ACTIVE
        }
      end
    end

    @org_member_user_ids_for_csv_generation_only = T.let(org_member_user_ids, T.nilable(T::Array[Integer]))

    @subscription_range_by_user = T.let(subscription_rangees, T.nilable(T::Hash[Integer, UserSubscribedRange]))

    # Fetch the org ids for each repo and build a repo_id => org_id map to refer to
    repo_org_ids = Repository.where(id: collaborator_repo_ids).pluck(:id, :organization_id).to_h

    # Get _outside_ collaborator ids, where the licensee has a ENABLEMENT_REASON_REPOSITORY_COLLABORATOR enablement for a repo
    # But does not have a ENABLEMENT_REASON_ORG_MEMBERSHIP enablement for the org that that repo belongs to
    outside_collaborators = customer_licenses.select do |license|
      # Collect org IDs from ORG_MEMBERSHIP enablements
      org_membership_org_ids = license.enablements
                                      .select { |e| e.reason == :ENABLEMENT_REASON_ORG_MEMBERSHIP }
                                      .flat_map(&:enablementIds)
                                      .uniq.map(&:to_i)

      # Find repositories where the licensee is a collaborator but not a member of the org
      license.enablements.any? do |enablement|
        next false unless enablement.reason == :ENABLEMENT_REASON_REPOSITORY_COLLABORATOR

        enablement.enablementIds.any? do |repo_id|
          org_id = repo_org_ids[repo_id.to_i]
          next false unless org_id

          !org_membership_org_ids.include?(org_id)
        end
      end
    end.map { |license| T.must(license.licensee).id.to_i }.uniq

    T.must(@business_private_outside_repo_collaborator_ids_licensify_for_csv_generation_only = T.let(outside_collaborators, T.nilable(T::Array[Integer])))
  end

  sig { returns(Integer) }
  def licensify_licensee_count
    licensify_licensee_ids.size
  end

  sig { returns(T::Array[String]) }
  memoize def licensify_licensee_ids
    fetch_licensee_ids_from_licensify(
      [
        Licensify::Services::V1::EnablementReason::ENABLEMENT_REASON_ORG_MEMBERSHIP,
        Licensify::Services::V1::EnablementReason::ENABLEMENT_REASON_REPOSITORY_COLLABORATOR,
        Licensify::Services::V1::EnablementReason::ENABLEMENT_REASON_ENTERPRISE_SERVER_USER,
      ]
    )
  end

  sig { returns(LicenseCounts) }
  memoize def license_counts
    license_counts_hash = {
      ghe_active_cloud_user_count: 0,
      ghe_active_server_only_user_count: 0,
      ghe_suspended_cloud_user_count: 0,
      ghe_suspended_server_only_user_count: 0,
      ghe_deactivated_cloud_user_count: 0,
      ghe_deactivated_server_only_user_count: 0,
      bundled_ghas_active_cloud_user_count: 0,
      bundled_ghas_active_server_only_user_count: 0,
      bundled_ghas_suspended_cloud_user_count: 0,
      bundled_ghas_suspended_server_only_user_count: 0,
      bundled_ghas_deactivated_cloud_user_count: 0,
      bundled_ghas_deactivated_server_only_user_count: 0,
    }

    licensify_req = Licensify::Services::V1::GetCustomerUsageSummaryRequest.new(
      customerId: business.customer_id,
    )
    licensify_res = licensify_client.get_customer_usage_summary(licensify_req)
    if licensify_res.error.present?
      GitHub.logger.error(
        "Failed to get customer licenses for business from Licensify: #{licensify_res.error}",
        {
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.business.id": business.id,
          "gh.customer.id": business.customer_id,
        },
      )
      return license_counts_hash
    end

    licensify_res.data["summaries"].to_a.each do |customer_usage_summary|
      product = customer_usage_summary["product"]
      license_type = customer_usage_summary["licenseeType"]
      license_status = customer_usage_summary["licenseStatus"]
      count = customer_usage_summary["count"]

      case product
      when :PRODUCT_SDLC
        case license_type
        when :LICENSEE_TYPE_USER
          case license_status
          when :LICENSE_STATUS_ACTIVE
            license_counts_hash[:ghe_active_cloud_user_count] = count
          when :LICENSE_STATUS_SUSPENDED
            license_counts_hash[:ghe_suspended_cloud_user_count] = count
          when :LICENSE_STATUS_DEACTIVATED
            license_counts_hash[:ghe_deactivated_cloud_user_count] = count
          end
        when :LICENSEE_TYPE_ENTERPRISE_SERVER_USER
          case license_status
          when :LICENSE_STATUS_ACTIVE
            license_counts_hash[:ghe_active_server_only_user_count] = count
          when :LICENSE_STATUS_SUSPENDED
            license_counts_hash[:ghe_suspended_server_only_user_count] = count
          when :LICENSE_STATUS_DEACTIVATED
            license_counts_hash[:ghe_deactivated_server_only_user_count] = count
          end
        end
      when :PRODUCT_GHAS
        case license_type
        when :LICENSEE_TYPE_USER
          case license_status
          when :LICENSE_STATUS_ACTIVE
            license_counts_hash[:bundled_ghas_active_cloud_user_count] = count
          when :LICENSE_STATUS_SUSPENDED
            license_counts_hash[:bundled_ghas_suspended_cloud_user_count] = count
          when :LICENSE_STATUS_DEACTIVATED
            license_counts_hash[:bundled_ghas_deactivated_cloud_user_count] = count
          end
        when :LICENSEE_TYPE_ENTERPRISE_SERVER_USER
          case license_status
          when :LICENSE_STATUS_ACTIVE
            license_counts_hash[:bundled_ghas_active_server_only_user_count] = count
          when :LICENSE_STATUS_SUSPENDED
            license_counts_hash[:bundled_ghas_suspended_server_only_user_count] = count
          when :LICENSE_STATUS_DEACTIVATED
            license_counts_hash[:bundled_ghas_deactivated_server_only_user_count] = count
          end
        end
      end
    end

    license_counts_hash
  end

  sig { returns(Integer) }
  def server_only_user_count
    fetch_licensee_ids_from_licensify(
      [Licensify::Services::V1::EnablementReason::ENABLEMENT_REASON_ENTERPRISE_SERVER_USER]
    ).length
  end

  private

  sig { params(enablement_reasons: T::Array[Integer]).returns(T::Array[String]) }
  def fetch_licensee_ids_from_licensify(enablement_reasons)
    licensify_req = Licensify::Services::V1::GetLicenseeIdsRequest.new(
      customerId: business.customer_id,
      product: Licensify::Services::V1::Product::PRODUCT_SDLC,
      enablementReasons: enablement_reasons,
    )
    licensify_res = licensify_client.get_licensee_ids(licensify_req)
    if licensify_res.error.present?
      GitHub.logger.error(
        "Failed to get customer licenses for business from Licensify: #{licensify_res.error}",
        {
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.business.id": business.id,
          "gh.customer.id": business.customer_id,
        },
      )
      return []
    end

    licensify_res.data["licenseeIds"].to_a
  end

  sig { returns(T::Array[Integer]) }
  def business_organization_member_ids_licensify
    fetch_licensee_ids_from_licensify(
      [Licensify::Services::V1::EnablementReason::ENABLEMENT_REASON_ORG_MEMBERSHIP]
    ).map(&:to_i)
  end

  sig { returns(T::Array[Integer]) }
  def business_org_member_and_private_outside_collaborator_ids_licensify
    licensee_ids = fetch_licensee_ids_from_licensify([
      Licensify::Services::V1::EnablementReason::ENABLEMENT_REASON_ORG_MEMBERSHIP,
      Licensify::Services::V1::EnablementReason::ENABLEMENT_REASON_REPOSITORY_COLLABORATOR,
    ])

    # defend against unexpected non-numeric ids (i.e. server-only licensees)
    numeric_ids = licensee_ids.select do |id|
      if id.to_s =~ /^\d+$/
        true
      else
        GitHub.logger.warn(
          "Filtered out unexpected non-numeric licensee ID: #{id.inspect} (#{id.class})",
          {
            "code.namespace": self.class.name,
            "code.function": __method__,
            "gh.business.id": business.id,
            "gh.customer.id": business.customer_id,
          },
        )
        false
      end
    end

    numeric_ids.map(&:to_i)
  end

  # Note: This is expected to be used for CSV generation only.
  # Querying with GetCustomerLicensesRequest instead of GetLicenseeIdsRequest is a step down in performance.
  sig { returns(T::Array[Licensify::Services::V1::CustomerLicense]) }
  memoize def business_customer_licenses_for_csv_generation_only
    licensify_req = Licensify::Services::V1::GetCustomerLicensesRequest.new(
      customerId: business.customer_id,
      product: Licensify::Services::V1::Product::PRODUCT_SDLC,
    )
    licensify_res = licensify_client.get_customer_licenses(licensify_req)
    if licensify_res.error.present?
      GitHub.logger.error(
        "Failed to get customer licenses for business from Licensify: #{licensify_res.error}",
        {
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.business.id": business.id,
          "gh.customer.id": business.customer_id,
        },
      )
      return []
    end

    licensify_res.data["customerLicenses"].to_a
  end
end
