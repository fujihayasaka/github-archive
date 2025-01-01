# typed: strict
# frozen_string_literal: true

# Contains information about users consuming a license in a business.
# Can optionally include non-licensed users in the license usage hash.
class Business::LicenseAttributer
  extend T::Sig
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
      subscription_start: DateTime,
      subscription_end: DateTime,
      active: T::Boolean
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
    GitHub.tracer.in_span("Business::LicenseAttributer#consumed_enterprise_licenses", kind: :internal) do
      return ::User.count_seats_used if GitHub.single_business_environment?
      return unique_count unless business.volume_licensing_enabled?

      # volume_user_ids and user_ids are overlapping sets so do set subtraction
      user_count = (user_ids - bla_licensed_user_ids).count
      # volume_emails and emails are overlapping sets so do set subtraction
      email_count = (emails - bla_licensed_emails).count
      ubua_count = unidentified_business_user_account_ids.count

      user_count + email_count + ubua_count
    end
  end

  # Returns the unique number of volume users across all owned organizations.
  sig { returns(Integer) }
  def consumed_volume_licenses
    GitHub.tracer.in_span("Business::LicenseAttributer#consumed_volume_licenses", kind: :internal) do
      return 0 unless business.volume_licensing_enabled?

      suspended_user_ids = business.enterprise_managed_user_enabled? ? business.suspended_member_ids.to_set : Set[]
      user_ids = bla_licensed_user_ids - suspended_user_ids

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
  sig { returns({ user_ids: T::Set[Integer], emails: T::Set[String] }) }
  def users_with_business_access
    { user_ids: user_ids_with_access, emails: emails_with_access }
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

    client_result = billing_platform_client.get_subscribed_items(usage_entity_id: business.customer_id.to_s, sku: SKU)

    if client_result.is_a?(Billing::Platform::Api::Error)
      # We don't want to return an incomplete list of users, so bail out.
      raise client_result
    else
      results = {}
      client_result[:subscribedItems].each do |subscriber|
        sub_start = Time.at(subscriber[:subscribedAt] / 1000).to_datetime
        sub_end = subscriber[:lastBilledForAt] == 0 ? nil : Time.at(subscriber[:lastBilledForAt] / 1000).to_datetime

        results[subscriber[:subscriptionId]] = {
          user_id: subscriber[:subscriptionId],
          subscription_start: sub_start,
          subscription_end: sub_end,
          active: subscriber[:status] == :Active
        }
      end
    end

    results
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
        business_organization_member_ids +
        T.must(business_enterprise_installation_user_ids) +
        T.must(private_outside_collaborator_ids) +
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

  sig { returns(T::Array[Integer]) }
  memoize def business_organization_member_ids
    GitHub.tracer.in_span("Business::LicenseAttributer#organization_member_ids", kind: :internal) do
      e = GitHub::Licensing::Licensify::Experiment.new "business_organization_member_ids"
      e.context({
        business_id: business.id,
        customer_id: business.customer_id,
      })

      e.use do
        business.organization_member_ids
      end

      e.try do
        licensify_req = Licensify::Services::V1::GetLicenseeIdsRequest.new(
          customerId: business.customer_id,
          product: Licensify::Services::V1::Product::PRODUCT_SDLC,
          enablementReasons: [Licensify::Services::V1::EnablementReason::ENABLEMENT_REASON_ORG_MEMBERSHIP],
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
          break []
        end

        licensify_res.data["licenseeIds"]
      end

      # The license attributer may be called when a business signs up for a trial but before the business is saved, so
      # there is no customer yet. This will generate a mismatch since licensify has no records yet, so ignore the mismatch.
      e.ignore { !business.persisted? }
      e.compare_sorted_sequence
      e.run
    end
  end

  sig { params(skip_cache: T.nilable(T::Boolean)).returns(T.nilable(T::Array[Integer])) }
  def suspended_member_ids(skip_cache: false)
    return @suspended_member_ids if defined?(@suspended_member_ids)

    @suspended_member_ids = T.let(@suspended_member_ids, T.nilable(T::Array[Integer]))
    @suspended_member_ids = business.license_attributer_cache.ids("suspended_member_ids", skip_cache: skip_cache) do
      business.suspended_member_ids || []
    end
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
end
