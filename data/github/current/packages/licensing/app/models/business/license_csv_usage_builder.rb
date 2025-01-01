# typed: strict
# frozen_string_literal: true

# Builds license usage information based on the provided business license attributer into a CSV-exportable format.
class Business::LicenseCsvUsageBuilder

  include GitHub::Memoizer
  include Scientist

  sig { returns(Business::LicenseAttributer) }
  attr_reader :attributer

  sig { params(attributer: Business::LicenseAttributer).void }
  def initialize(attributer)
    @attributer = attributer

    @page = T.let(nil, T.nilable(T::Array[T::Hash[Symbol, T.untyped]]))
  end

  module EntityType
    BUSINESS_USER_ACCOUNT = 1
    NON_MATCHED_EMAIL_ADDRESS = 2
    UNIDENTIFIED_BUSINESS_USER_ACCOUNT = 3
  end

  DEFAULT_PER_PAGE = 30
  MAX_PER_PAGE = 100
  sig { params(pagination: T::Boolean, page: Integer, per_page: Integer).returns(T::Hash[Symbol, T.untyped]) }
  def process(pagination: false, page: 1, per_page: DEFAULT_PER_PAGE)
    GitHub.tracer.in_span("Business::LicenseCsvUsageBuilder#process", kind: :internal) do |span|
      span.add_attributes({
        "gh.business.id" => attributer.business.id,
      })

      if pagination == true
        page = 1 if page < 1
        per_page = DEFAULT_PER_PAGE if per_page < 1
        per_page = MAX_PER_PAGE if per_page > MAX_PER_PAGE
      end

      attributions = if !GitHub.single_business_environment?
        GitHub.tracer.in_span("attributions_with_licensify_paging", kind: :internal) do
          attributions_with_licensify_paging(pagination, page, per_page)
        end
      else
        GitHub.tracer.in_span("attributions", kind: :internal) do
          attributions(pagination, page, per_page)
        end
      end
      usage_rows = populate_usage_from_attributions(attributions)

      user_scoped_cost_centers = attributer.business.user_scoped_cost_centers?
      bundled_advanced_security_purchased = attributer.business.ghas_sku_purchased_for_entity?
      code_security_purchased = attributer.business.code_security_purchased?
      secret_protection_purchased = attributer.business.secret_protection_purchased?
      usage_rows.map do |r|
        r.delete(:github_com_cost_center) unless user_scoped_cost_centers
        r.delete(:github_com_advanced_security_license_user) unless bundled_advanced_security_purchased
        r.delete(:github_com_code_security_license_user) unless code_security_purchased
        r.delete(:github_com_secret_protection_license_user) unless secret_protection_purchased
        r.delete(:sorting_key)
        unless attributer.business.metered_plan?
          r.delete(:ghe_license_active)
          r.delete(:ghe_license_start_date)
          r.delete(:ghe_license_end_date)
        end
        if GitHub.multi_tenant_enterprise?
          r.delete(:github_com_two_factor_auth_required_by_date)
          r.delete(:github_com_profile)
          r.transform_keys!({
            github_com_user: :github_user,
            github_com_member_roles: :github_member_roles,
            github_com_enterprise_roles: :github_enterprise_roles,
            github_com_verified_domain_emails: :github_verified_domain_emails,
            github_com_orgs_with_pending_invites: :github_orgs_with_pending_invites,
            github_com_login: :github_login,
            github_com_saml_name_id: :github_saml_name_id,
            github_com_name: :github_name,
            github_com_two_factor_auth: :github_two_factor_auth,
            github_com_advanced_security_license_user: :github_advanced_security_license_user,
            github_com_code_security_license_user: :github_code_security_license_user,
            github_com_secret_protection_license_user: :github_secret_protection_license_user,
          })
        end
      end

      # remove the enterprise_server_advanced_security_user_ids pair if the business is not on a version of Connect that is sending
      # the data (3.12+)
      # this can be removed once versions before 3.12 become obsolete
      unless EnterpriseInstallationUserAccount
        .where(enterprise_installation_id: attributer.business_enterprise_installations.keys)
        .where(EnterpriseInstallationUserAccount.arel_table[:using_advanced_security].not_eq(nil))
        .exists?
        usage_rows.map { |row| row.delete(:enterprise_server_advanced_security_user_ids) }
      end

      # remove the enterprise_server_code_security_user_ids pair if the business is not on a version of Connect that is sending
      # the data (3.17+)
      # this can be removed once versions before 3.17 become obsolete
      unless EnterpriseInstallationUserAccount
        .where(enterprise_installation_id: attributer.business_enterprise_installations.keys)
        .where(EnterpriseInstallationUserAccount.arel_table[:using_code_security].not_eq(nil))
        .exists?
        usage_rows.map { |row| row.delete(:enterprise_server_code_security_user_ids) }
      end

      # remove the enterprise_server_secret_protection_user_ids pair if the business is not on a version of Connect that is sending
      # the data (3.17+)
      # this can be removed once versions before 3.17 become obsolete
      unless EnterpriseInstallationUserAccount
        .where(enterprise_installation_id: attributer.business_enterprise_installations.keys)
        .where(EnterpriseInstallationUserAccount.arel_table[:using_secret_protection].not_eq(nil))
        .exists?
        usage_rows.map { |row| row.delete(:enterprise_server_secret_protection_user_ids) }
      end

      if attributer.business.advanced_security_products_bundled?
        usage_rows.map { |row| row.delete(:enterprise_server_code_security_user_ids) }
        usage_rows.map { |row| row.delete(:enterprise_server_secret_protection_user_ids) }
      end

      # TODO: With a little tweaking this could potentially only return usage_rows and allow the attributer to populate
      # the two total_* fields
      ActiveRecord::Base.connected_to(role: :reading) do
        {
          total_seats_consumed: attributer.business.total_consumed_licenses,
          total_seats_purchased: attributer.business.total_purchased_licenses_with_overages,
          users: usage_rows
        }
      end
    end
  end

  private

  # Find & sort users from the different attribution types; accounts consuming a license, accounts with no matching email, or unidentified accounts.
  #
  # For non matching emails or unidentified accounts, we assigned an arbitrary we assign an arbitrary sort key to enable proper pagination.
  sig { params(pagination: T::Boolean, page: Integer, per_page: Integer).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def attributions(pagination, page, per_page)
    if @page.present? && pagination == false
      return @page
    end
    if @page.present? && pagination == true
      return @page.paginate(page: page, per_page: per_page)
    end

    ids = attributer.user_ids
    ids += attributer.nonlicensed_roles_user_ids if attributer.include_nonlicensed_roles?
    ids = ids.sort.map { |id| { id: id, type: EntityType::BUSINESS_USER_ACCOUNT } }

    non_matched_emails_or_unidentified_users = (
      attributer.non_bundle_licensed_emails.map { |email| { id: email, type: EntityType::NON_MATCHED_EMAIL_ADDRESS } } +
      attributer.unidentified_enterprise_user_accounts_logins.map { |login| { id: login, type: EntityType::UNIDENTIFIED_BUSINESS_USER_ACCOUNT } }
    )
    non_matched_emails_or_unidentified_users += attributer.nonlicensed_roles_emails.map { |email| { id: email, type: EntityType::NON_MATCHED_EMAIL_ADDRESS } } if attributer.include_nonlicensed_roles?
    non_matched_emails_or_unidentified_users = non_matched_emails_or_unidentified_users.sort_by.with_index { |x, idx| [x[:id], idx] }

    @page = ids + non_matched_emails_or_unidentified_users

    if pagination
      return @page.paginate(page: page, per_page: per_page)
    end

    @page
  end

  sig { params(pagination: T::Boolean, page: Integer, per_page: Integer).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def attributions_with_licensify_paging(pagination, page, per_page)
    licensify_user_ids = T.let(Set[], T::Set[Integer])
    licensify_server_only_emails = T.let(Set[], T::Set[String])
    licensify_server_only_logins = T.let(Set[], T::Set[String])

    server_only_installation_account_ids = T.let(Set[], T::Set[Integer])

    licensify_licenses, licensify_total_count = attributer.business_customer_licenses_for_csv_generation_only_with_pagination(pagination, page, per_page)

    # Store the results in memory to populate the rest of the CSV later
    attributer.set_licensify_collections(customer_licenses: licensify_licenses)

    licensify_licenses.each do |license|
      licensee_type = T.must(license.licensee).type
      id = T.must(license.licensee).id

      if licensee_type == :LICENSEE_TYPE_USER
        licensify_user_ids << id.to_i
      elsif licensee_type == :LICENSEE_TYPE_ENTERPRISE_SERVER_USER
        # collect enterprise_installation_user_account_ids
        license.enablements.each do |enablement|
          if enablement.reason == :ENABLEMENT_REASON_ENTERPRISE_SERVER_USER
            enablement.enablementIds.each do |eid|
              # parse enablement ids of the format [enterprise_installation_id]:[enterprise_installation_user_account_id]
              parts = eid.split(":")
              if parts.length != 2
                GitHub.logger.warn(
                  "Filtered out unexpected enablement id from Licensify: #{eid.inspect} (#{eid.class})",
                  {
                    "code.namespace": self.class.name,
                    "code.function": __method__,
                    "gh.business.id": attributer.business.id,
                    "gh.customer.id": attributer.business.customer_id,
                  },
                )
                next
              end
              server_only_installation_account_ids << parts[1].to_i
            end
          end
        end
      end
    end

    # Find the server emails and business_user_account.logins associated with the server only users
    server_only_accounts = EnterpriseInstallationUserAccount
      .left_outer_joins(:business_user_account, :emails)
      .where(id: server_only_installation_account_ids)
      .where("enterprise_installation_user_account_emails.primary IS NULL OR enterprise_installation_user_account_emails.primary = ?", true)
      .group("business_user_accounts.id")
      .select("business_user_accounts.login as bua_login, MIN(enterprise_installation_user_account_emails.email) as email")

    server_only_accounts.each do |account|
      if account.email.present?
        licensify_server_only_emails << account.email.downcase
      elsif !account.bua_login.nil?
        licensify_server_only_logins << account.bua_login
      end
    end

    # Remove emails associated with the business to prevent double counting. See Business::LicenseAttributer#emails_with_access
    licensify_server_only_emails = attributer.filter_out_verified_business_emails(licensify_server_only_emails)


    licensify_ids = licensify_user_ids.sort.map { |id| { id: id, type: EntityType::BUSINESS_USER_ACCOUNT } } +
      licensify_server_only_emails.sort.map { |email| { id: email, type: EntityType::NON_MATCHED_EMAIL_ADDRESS } } +
      licensify_server_only_logins.sort.map { |login| { id: login, type: EntityType::UNIDENTIFIED_BUSINESS_USER_ACCOUNT } }

    # Check if we need to add additional ids to the page
    fetch_additional_ids = !pagination || licensify_ids.length < per_page

    monolith_ids = []
    if fetch_additional_ids
      monolith_user_ids = T.let(Set[], T::Set[Integer])
      monolith_user_ids += attributer.user_ids_invitations unless attributer.business.metered_plan?

      if attributer.business.enterprise_managed_user_enabled?
        monolith_user_ids -= T.must(attributer.suspended_member_ids)
      end

      monolith_user_ids += attributer.nonlicensed_roles_user_ids if attributer.include_nonlicensed_roles?

      # Add the monolith user ids that are not in licensify
      monolith_ids += (monolith_user_ids - licensify_user_ids).sort.map { |id| { id: id, type: EntityType::BUSINESS_USER_ACCOUNT } }

      monolith_unmatched_emails = T.let(Set[], T::Set[String])

      unless attributer.business.metered_plan?
        monolith_unmatched_emails += attributer.pending_invitation_emails_excluding_verified_business_emails
      end
      monolith_unmatched_emails += attributer.nonlicensed_roles_emails if attributer.include_nonlicensed_roles?

      # Add the monolith unmatched emails that are not in licensify
      monolith_ids += (monolith_unmatched_emails - licensify_server_only_emails).sort.map { |email| { id: email, type: EntityType::NON_MATCHED_EMAIL_ADDRESS } }
    end

    if pagination
      page = if licensify_ids.length == per_page
        # all items are from licensify
        licensify_ids
      elsif licensify_ids.length == 0
        # all items are from monolith
        monolith_offset = (page - 1) * per_page - licensify_total_count
        monolith_ids.slice(monolith_offset, per_page) || []
      else
        # licensify has some items, but not enough to fill the page, so add the rest from the monolith
        (licensify_ids + monolith_ids).slice(0, per_page) || []
      end

      return page
    end

    licensify_ids + monolith_ids
  end

  sig { params(attributions: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def populate_usage_from_attributions(attributions)
    users = []
    email_addresses = []
    unidentified_business_user_accounts = []
    attributions.each do |a|
      case a[:type]
      when EntityType::BUSINESS_USER_ACCOUNT
        users << a[:id]
      when EntityType::NON_MATCHED_EMAIL_ADDRESS
        email_addresses << a[:id]
      when EntityType::UNIDENTIFIED_BUSINESS_USER_ACCOUNT
        unidentified_business_user_accounts << a[:id]
      end
    end

    usage_for_user_ids = usage_for_user_ids(users.to_set)

    usage_for_email_addresses = usage_for_email_addresses(email_addresses.to_set)
    usage_for_unidentified_business_user_accounts =
      usage_for_unidentified_business_user_accounts(unidentified_business_user_accounts.to_set)

    usage_for_user_ids.sort_by { |x| [x[:sorting_key]] } + (
      usage_for_email_addresses +
      usage_for_unidentified_business_user_accounts
    ).sort_by.with_index { |x, idx| [x[:sorting_key].to_s, idx] }
  end

  # Return license usage information for all Business users by user_id.
  # This will include VSS subscriptions (for business members) and GHES server users with primary email
  # addresses that match a user verified email for a user associated with the Business.
  sig { params(user_ids: T::Set[Integer]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def usage_for_user_ids(user_ids)
    GitHub.tracer.in_span("Business::LicenseCsvUsageBuilder#usage_for_user_ids", kind: :internal) do

      # Before we start looping through users, build a hash of business orgs that have saml providers, and lists of all
      # the external identity ids and user ids. We will use this in our saml_name_id method. This prevents too many
      # roundtrips to the database, looking up all the external identities for each user
      return [] if user_ids.empty?

      visual_studio_sub_emails_hash = attributer.bundled_license_assignment_assigned_emails_for_user_ids(user_ids)
      server_emails_hostnames_hash = attributer.enterprise_server_hostnames_emails_by_user_id(user_ids)
      verified_domain_emails = github_verified_domain_emails(user_ids)
      nameid_hash = user_ids_name_ids(user_ids)
      two_factor_enabled_user_ids = two_factor_enabled_user_ids(user_ids)
      two_factor_requirement_date_hash = two_factor_requirement_date_hash(user_ids)
      ghas_license_usage_hash = ghas_license_usage_hash(user_ids)
      code_security_license_usage_hash = code_security_license_usage_hash(user_ids)
      secret_protection_license_usage_hash = secret_protection_license_usage_hash(user_ids)
      recent_user_subscription_information = attributer.recent_user_subscription_information
      member_roles = member_roles_for_user_ids(user_ids)

      license_usage_hash_for_user_ids = []
      get_users_id_login_name(user_ids).each do |user|
        ghes_info = server_emails_hostnames_hash.fetch(user[:id], {})
        cost_center = cost_center_for_user_id(user[:id])

        license_usage_hash_for_user_ids << build_usage_row(
          sorting_key: user[:id],
          github_com_login: user[:display_login],
          github_com_name: user[:name],
          enterprise_server_user_ids: ghes_info.fetch(:instances, []).sort,
          github_com_user: true,
          enterprise_server_user: ghes_info.present?,
          visual_studio_subscription_user: attributer.volume_licensed_user_ids.include?(user[:id]) ? true : false,
          license_type: license_type_label(license_type_for_user_id(user[:id])),
          github_com_profile: ViewModel::URLs.new.user_url(user[:display_login]),
          github_com_member_roles: member_roles[user[:id]],
          github_com_enterprise_roles: enterprise_roles_for_user_id(user[:id]),
          github_com_verified_domain_emails: verified_domain_emails[user[:id]] || [],
          github_com_saml_name_id: nameid_hash[user[:id]],
          github_com_orgs_with_pending_invites: attributer.pending_member_org_invites_hash[user[:id]] || [],
          github_com_two_factor_auth: T.must(two_factor_enabled_user_ids).include?(user[:id]) ? true : false,
          github_com_two_factor_auth_required_by_date: T.must(two_factor_requirement_date_hash)[user[:id]],
          github_com_cost_center: cost_center,
          github_com_advanced_security_license_user: ghas_license_usage_hash[user[:id]],
          github_com_code_security_license_user: code_security_license_usage_hash[user[:id]],
          github_com_secret_protection_license_user: secret_protection_license_usage_hash[user[:id]],
          enterprise_server_primary_emails: ghes_info.fetch(:emails, []).sort,
          enterprise_server_advanced_security_user_ids: ghes_info.fetch(:enterprise_server_advanced_security_user_ids, []).sort,
          enterprise_server_code_security_user_ids: ghes_info.fetch(:enterprise_server_code_security_user_ids, []).sort,
          enterprise_server_secret_protection_user_ids: ghes_info.fetch(:enterprise_server_secret_protection_user_ids, []).sort,
          visual_studio_license_status: vss_license_match(user[:id], server_emails_hostnames_hash),
          visual_studio_subscription_email: visual_studio_sub_emails_hash[user[:id]],
          total_user_accounts: ghes_info.fetch(:instances, []).length + 1,
          ghe_license_active: recent_user_subscription_information.dig(user[:id], :active),
          ghe_license_start_date: recent_user_subscription_information.dig(user[:id], :subscription_start),
          ghe_license_end_date: recent_user_subscription_information.dig(user[:id], :subscription_end),
        )
      end

      license_usage_hash_for_user_ids
    end
  end

  sig { params(user_ids: T::Set[Integer]).returns(T::Hash[Integer, T::Boolean]) }
  def ghas_license_usage_hash(user_ids)
    return {} unless attributer.business.ghas_sku_purchased_for_entity?
    active_committer_user_ids = attributer.business.advanced_security_license.active_committer_user_ids.to_set
    user_ids.to_h { |user_id| [user_id, active_committer_user_ids.include?(user_id)] }
  end

  sig { params(user_ids: T::Set[Integer]).returns(T::Hash[Integer, T::Boolean]) }
  def code_security_license_usage_hash(user_ids)
    return {} unless attributer.business.code_security_purchased?
    active_committer_user_ids = attributer.business.code_security.active_committer_user_ids.to_set
    user_ids.to_h { |user_id| [user_id, active_committer_user_ids.include?(user_id)] }
  end

  sig { params(user_ids: T::Set[Integer]).returns(T::Hash[Integer, T::Boolean]) }
  def secret_protection_license_usage_hash(user_ids)
    return {} unless attributer.business.secret_protection_purchased?
    active_committer_user_ids = attributer.business.secret_protection.active_committer_user_ids.to_set
    user_ids.to_h { |user_id| [user_id, active_committer_user_ids.include?(user_id)] }
  end

  sig { params(user_id: Integer).returns(T.nilable(String)) }
  def cost_center_for_user_id(user_id)
    return nil unless attributer.business.user_scoped_cost_centers?
    return "Unavailable" if attributer.business.cost_centers.nil?
    attributer.business.cost_center_for_id(user_id)
  end

  sig { params(user_ids: T::Set[Integer]).returns(T.nilable(T::Set[Integer])) }
  def two_factor_enabled_user_ids(user_ids)
    return @two_factor_enabled_user_ids if defined?(@two_factor_enabled_user_ids)

    @two_factor_enabled_user_ids = T.let(User.where(id: user_ids).two_factor_enabled.pluck(:id).to_set, T.nilable(T::Set[Integer]))
  end

  sig { params(user_ids: T::Set[Integer]).returns(T.nilable(T::Hash[T.nilable(Integer), String])) }
  def two_factor_requirement_date_hash(user_ids)
    return @two_factor_requirement_date_hash if defined?(@two_factor_requirement_date_hash)

    @two_factor_requirement_date_hash = T.let(
      User.where(id: user_ids).with_account_two_factor_requirement.map do |user|
        [user.id, user.two_factor_requirement_metadata&.required_by&.strftime("%Y-%m-%d")]
      end.to_h,
      T.nilable(T::Hash[T.nilable(Integer), String])
    )
  end

  MAX_USER_PROFILE_QUERIES = 1000
  # Retrieve information that is necessary to then gather license usage information for all Business users by user_id.
  sig { params(user_ids: T::Set[Integer]).returns(T::Array[{ display_login: String, name: String, id: Integer }]) }
  def get_users_id_login_name(user_ids)
    rows = []
    user_ids.each_slice(MAX_USER_PROFILE_QUERIES) do |user_ids|
      User.left_outer_joins(:profile).where(id: user_ids).pluck(:id, :display_login, "profiles.name").map do |(id, display_login, name)|
        rows << {
          display_login: display_login,
          name: name,
          id: id,
        }
      end
    end
    rows
  end

  # Returns a hash of all user emails, verified or not, that would match the verified domain for the business
  sig { params(user_ids: T::Set[Integer]).returns(T::Hash[Integer, T::Array[String]]) }
  def github_verified_domain_emails(user_ids)
    UserEmail.where(user_id: user_ids, normalized_domain: verified_domains).pluck(:user_id, :email).each_with_object({}) do |i, hash|
      hash[i[0]] ||= []
      hash[i[0]] << i[1]
    end
  end

  sig { returns(T::Array[String]) }
  memoize def verified_domains
    GitHub.tracer.in_span("LicenseAttributer#verified_domains", kind: :internal) do
      VerifiableDomain.where(
        owner_type: %w[User Business],
        owner_id: [attributer.business.id, *attributer.business.organization_ids],
      ).verified.pluck(:domain)
    end
  end

  sig { params(user_ids: T::Set[Integer]).returns(T::Hash[Integer, T::Array[String]]) }
  def member_roles_for_user_ids(user_ids)
    GitHub.tracer.in_span("Business::LicenseCsvUsageBuilder#member_roles_for_user_ids", kind: :internal) do
      user_ids_to_member_roles = Hash.new { |h, id| h[id] = [] }
      member_organization_roles_for_user_ids(user_ids).each do |user_id, orgs_to_roles|
        user_roles = user_ids_to_member_roles[user_id]
        orgs_to_roles.each do |org_name, org_roles|
          role = "#{org_name}:"
          if org_roles.include?("Owner")
            role << "Owner"
          elsif org_roles.include?("Billing manager")
            role << "Billing manager"
          elsif org_roles.include?("Member")
            role << "Member"
          end
          user_roles << role
        end
        user_roles.sort!
      end

      user_ids_to_member_roles
    end
  end

  sig { params(user_ids: T::Set[Integer]).returns(T::Hash[Integer, T::Hash[String, T::Array[String]]]) }
  def member_organization_roles_for_user_ids(user_ids)
    GitHub.tracer.in_span("Business::LicenseCsvUsageBuilder#member_organization_roles_for_user_ids", kind: :internal) do
      orgs_by_id = attributer.business.organizations_hash(value_field: :display_login)

      actor_ids = if user_ids.length <= MAX_PER_PAGE
        user_ids
      else
        nil
      end

      include_indirect_abilities = attributer.business.indirect_abilities_feature_enabled?
      if include_indirect_abilities
        member_organization_roles_for_orgs_and_actors_with_indirect_members(orgs_by_id:, actor_ids:)
      else
        member_organization_roles_for_orgs_and_actors(orgs_by_id:, actor_ids:)
      end
    end
  end

  sig do params(
    orgs_by_id: T::Hash[T.untyped, T.untyped],
    actor_ids: T.nilable(T::Set[Integer]),
  ).returns(T::Hash[Integer, T::Hash[T.untyped, T::Array[String]]])
  end
  def member_organization_roles_for_orgs_and_actors_with_indirect_members(orgs_by_id:, actor_ids:)
    start_time = Time.current.utc

    user_ids_to_orgs_to_member_roles = Hash.new { |h, id| h[id] = Hash.new { |h, id| h[id] = [] } }

    abilities = attributer.business.business_org_abilities(
      actor_ids: actor_ids,
      include_billing_managers: true,
      include_indirect_abilities: false,
    ) do |scope|
      scope.pluck(:actor_id, :subject_id, :subject_type, :action)
    end

    abilities.each do |(user_id, org_id, subject_type, action)|
      org_name = orgs_by_id[org_id]
      roles = user_ids_to_orgs_to_member_roles[user_id][org_name]

      if subject_type == "Organization::BillingManagement"
        roles << "Billing manager"
      else
        roles << "Owner" if Ability.can_at_least?(:admin, action)
        roles << "Member"
      end
    end

    Orgs.domain.teams.business_team_user_ids_by_org_ids(
      business_id: attributer.business.id,
      user_ids: actor_ids,
    ).each do |org_id, user_ids|
      org_name = orgs_by_id[org_id]
      user_ids.each do |user_id|
        roles = user_ids_to_orgs_to_member_roles[user_id][org_name]
        roles << "Member"
      end
    end

    GitHub.logger.info(
      "Business::LicenseCsvUsageBuilder#member_organization_roles_for_orgs_and_actors_with_indirect_members",
      "gh.business.id": attributer.business.id,
      "gh.user_ids": actor_ids,
      "gh.duration_ms": (Time.current.utc - start_time) * 1000,
    )

    user_ids_to_orgs_to_member_roles
  end

  sig do params(
    orgs_by_id: T::Hash[T.untyped, T.untyped],
    actor_ids: T.nilable(T::Set[Integer]),
  ).returns(T::Hash[Integer, T::Hash[T.untyped, T::Array[String]]])
  end
  def member_organization_roles_for_orgs_and_actors(orgs_by_id:, actor_ids:)
    user_ids_to_orgs_to_member_roles = Hash.new { |h, id| h[id] = Hash.new { |h, id| h[id] = [] } }
    abilities = if attributer.business.feature_flag_enabled?(:batch_business_org_abilities, default: false) || attributer.business.feature_flag_enabled?(:run_business_org_abilities_experiment, default: false)
      attributer.business.business_org_abilities(include_billing_managers: true, actor_ids: actor_ids) do |scope|
        scope.select(:id, :actor_id, :subject_id, :subject_type, :action)
      end
    else
      attributer.business.business_org_abilities(include_billing_managers: true, actor_ids: actor_ids)
        .select(:actor_id, :subject_id, :subject_type, :action)
    end

    abilities.each do |ability|
      org_name = orgs_by_id[ability.subject_id]
      roles = user_ids_to_orgs_to_member_roles[ability.actor_id][org_name]

      if ability.subject_type == "Organization::BillingManagement"
        roles << "Billing manager"
      else
        roles << "Owner" if ability.can?(:admin)
        roles << "Member"
      end
    end

    user_ids_to_orgs_to_member_roles
  end

  sig { params(user_ids: T::Set[Integer]).returns(T::Hash[Integer, Integer]) }
  def user_ids_name_ids(user_ids)
    GitHub.tracer.in_span("Business::LicenseCsvUsageBuilder#user_ids_name_ids", kind: :internal) do
      @providers = T.let(nil, T.nilable(T::Array[T.nilable(T.any(Business::SamlProvider, Organization::SamlProvider))]))
      @providers ||= [attributer.business.saml_provider] + Organization::SamlProvider.where(organization_id: attributer.business.organization_ids)
      ExternalIdentity.where(provider: @providers, user_id: user_ids).pluck(:user_id, :name_id).to_h
    end
  end

  sig { params(user_id: Integer).returns(T::Array[String]) }
  def enterprise_roles_for_user_id(user_id)
    GitHub.tracer.in_span("Business::LicenseCsvUsageBuilder#enterprise_roles_for_user_id", kind: :internal) do
      roles = []
      business = attributer.business

      if !GitHub.single_business_environment?
        private_outside_collaborator_ids = attributer.business_private_outside_repo_collaborator_ids_licensify_for_csv_generation_only
      else
        private_outside_collaborator_ids = T.must(attributer.private_outside_collaborator_ids)
      end

      roles << "Owner" if owner_ids.include?(user_id)
      roles << "Billing manager" if billing_manager_ids.include?(user_id)
      roles << "Member" if org_member_ids.include?(user_id)

      roles << "Guest Collaborator" if attributer.business_guest_collaborator_ids.include?(user_id)
      roles << "Outside collaborator" if private_outside_collaborator_ids&.include?(user_id)
      roles << "Pending invitation" if attributer.non_expired_pending_member_invitations_invitee_ids.include?(user_id)
      roles << "Pending outside collaborator invitation" if attributer.pending_collaborator_invitation_user_ids.include?(user_id)

      if attributer.include_nonlicensed_roles?
        roles << "Outside collaborator" if
          T.must(attributer.nonlicensed_outside_collaborator_ids).include?(user_id) &&
          !roles.include?("Outside collaborator")
        roles << "Pending administrator invitation" if attributer.business_pending_admin_invites_user_ids.include?(user_id)
        roles << "Pending outside collaborator invitation" if
          attributer.public_collaborator_invitations_user_ids.include?(user_id) &&
          !roles.include?("Pending outside collaborator invitation")
        roles << "Unaffiliated user" if roles.blank? && attributer.business_unaffiliated_user_ids.include?(user_id)
      end

      roles
    end
  end

  sig { returns(T::Array[Integer]) }
  memoize def billing_manager_ids
    GitHub.tracer.in_span("Business::LicenseCsvUsageBuilder#billing_manager_ids", kind: :internal) do
      attributer.business.billing_manager_ids
    end
  end

  sig { returns(T::Array[Integer]) }
  memoize def owner_ids
    GitHub.tracer.in_span("Business::LicenseCsvUsageBuilder#owner_ids", kind: :internal) do
      attributer.business.owner_ids
    end
  end

  sig { returns(T::Array[Integer]) }
  memoize def org_member_ids
    GitHub.tracer.in_span("Business::LicenseCsvUsageBuilder#org_member_ids", kind: :internal) do
      if !GitHub.single_business_environment?
        attributer.org_member_user_ids_for_csv_generation_only || []
      else
        attributer.business.organization_member_ids
      end
    end
  end


  sig do
    params(
      id: Integer,
      server_emails_hostnames_hash: T::Hash[Integer, T.untyped]
    )
    .returns(T.nilable(String))
  end
  def vss_license_match(id, server_emails_hostnames_hash)
    if attributer.volume_licensed_user_ids.include?(id)
      status = "Matched to Cloud"
      if server_emails_hostnames_hash[id]
        status += " + Server"
      end
    else
      status = nil
    end

    status
  end

  # Returns license usage information for GHES users with email addresses that weren't matched
  # to a user account associated with the Business.
  sig { params(email_addresses: T::Set[String]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def usage_for_email_addresses(email_addresses)
    GitHub.tracer.in_span("Business::LicenseCsvUsageBuilder#usage_for_email_addresses", kind: :internal) do
      return [] if email_addresses.blank?

      server_emails_hostnames_hash = attributer.get_enterprise_server_hostnames_emails_by_email(attributer.get_enterprise_server_users_per_email(email_addresses))
      license_usage_hash_for_email_addresses = []
      email_addresses.each do |email|
        ghes_info = server_emails_hostnames_hash.fetch(email, {})

        license_usage_hash_for_email_addresses << build_usage_row(
          sorting_key: email,
          github_com_login: ghes_info.blank? ? email : "",
          enterprise_server_user_ids: ghes_info.fetch(:instances, []).sort,
          enterprise_server_user: ghes_info.present?,
          visual_studio_subscription_user: volume_licensed_user_emails.include?(email) ? true : false,
          license_type: license_type_label(license_type_for_email(email)),
          github_com_enterprise_roles: enterprise_roles_for_email(email),
          github_com_orgs_with_pending_invites: attributer.pending_member_org_invites_hash[email] || [],
          enterprise_server_primary_emails: ghes_info.fetch(:emails, []).sort,
          enterprise_server_advanced_security_user_ids: ghes_info.fetch(:enterprise_server_advanced_security_user_ids, []).sort,
          enterprise_server_code_security_user_ids: ghes_info.fetch(:enterprise_server_code_security_user_ids, []).sort,
          enterprise_server_secret_protection_user_ids: ghes_info.fetch(:enterprise_server_secret_protection_user_ids, []).sort,
          visual_studio_subscription_email: volume_licensed_user_emails.include?(email) ? email : nil,
          visual_studio_license_status: vss_license_status_email(email),
          total_user_accounts: ghes_info.fetch(:instances, []).length,
        )
      end

      license_usage_hash_for_email_addresses
    end
  end

  sig { params(email: String).returns(T::Array[String]) }
  def enterprise_roles_for_email(email)
    roles = []

    roles << "Pending invitation" if attributer.non_expired_pending_member_invitations_emails.include?(email)
    roles << "Pending outside collaborator invitation" if attributer.pending_collaborator_invitation_emails.include?(email)

    if attributer.include_nonlicensed_roles?
      roles << "Unlinked Visual Studio license subscription" if attributer.pending_bundled_license_assignment_emails.include?(email.downcase)
      roles << "Pending administrator invitation" if attributer.business_pending_admin_invites_emails.include?(email.downcase)
      roles << "Pending outside collaborator invitation" if
        attributer.public_collaborator_invitations_emails.include?(email.downcase) &&
        !roles.include?("Pending outside collaborator invitation")
    end

    roles
  end

  sig { params(unidentifiend_business_user_accounts: T::Set[String]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def usage_for_unidentified_business_user_accounts(unidentifiend_business_user_accounts)
    GitHub.tracer.in_span("Business::LicenseCsvUsageBuilder#usage_for_unidentified_bua", kind: :internal) do
      return [] if unidentifiend_business_user_accounts.blank?

      license_usage_hash_for_unidentified_business_user_accounts = []

      server_hostnames_hash = attributer.enterprise_server_hostnames_by_logins(logins: unidentifiend_business_user_accounts.to_a)

      unidentifiend_business_user_accounts.each do |ubua|
        license_usage_hash_for_unidentified_business_user_accounts << build_usage_row(
          sorting_key: ubua,
          enterprise_server_user_ids: server_hostnames_hash[ubua] ? T.must(server_hostnames_hash[ubua])[:instances].sort : [],
          enterprise_server_user: true,
          license_type: license_type_label("ENTERPRISE"),
          total_user_accounts: server_hostnames_hash[ubua] ? T.must(server_hostnames_hash[ubua])[:instances].length : 0,
        )
      end
      license_usage_hash_for_unidentified_business_user_accounts
    end
  end

  sig { params(email: String).returns(T.nilable(String)) }
  def vss_license_status_email(email)
    return unless T.must(attributer.bundled_license_assignment_emails).include?(email)

    if attributer.business.enterprise_managed_user_enabled?
      "Not a member of any enterprise organizations"
    elsif attributer.non_expired_pending_member_invitations_emails.include?(email)
      "Pending Invitation"
    else
      "No pending organization invitations"
    end
  end

  sig { params(license_type: T.nilable(String)).returns(T.nilable(String)) }
  def license_type_label(license_type)
    Platform::Enums::EnterpriseLicenseType.values[license_type]&.description if license_type.present?
  end

  sig { params(user_id: Integer).returns(T.nilable(String)) }
  def license_type_for_user_id(user_id)
    if attributer.volume_licensed_user_ids.include?(user_id)
      "VSS_BUNDLE"
    elsif attributer.user_ids.include?(user_id)
      "ENTERPRISE"
    elsif attributer.include_nonlicensed_roles? && attributer.nonlicensed_roles_user_ids.include?(user_id)
      nil
    else
      "ENTERPRISE" # default to enterprise license
    end
  end

  sig { params(email: String).returns(T.nilable(String)) }
  def license_type_for_email(email)
    # Check for pending bundled license emails. They are included in volume_licensed_user_emails, but they
    # don't consume a license, so must check for them first.
    if attributer.include_nonlicensed_roles? && attributer.volume_licensing_enabled &&
      attributer.pending_bundled_license_assignment_emails.include?(email.downcase)
      nil
    elsif volume_licensed_user_emails.include?(email.downcase)
      "VSS_BUNDLE"
    elsif attributer.emails.include?(email.downcase)
      "ENTERPRISE"
    elsif attributer.include_nonlicensed_roles? && attributer.nonlicensed_roles_emails.include?(email.downcase)
      nil
    else
      "ENTERPRISE" # default to enterprise license
    end
  end

  sig { returns(T::Set[String]) }
  memoize def volume_licensed_user_emails
    attributer.business.bundled_license_assignments.pluck(:email).to_set
  end

  # Formats license usage into a structured hash.
  #
  # Particular formatting is determined by the CSV export. Each key represents a column in the CSV, so the order matters.
  sig do
    params(
      sorting_key: T.any(String, Integer),
      license_type: T.nilable(String),
      total_user_accounts: Integer,
      enterprise_server_user: T.nilable(T::Boolean),
      enterprise_server_user_ids: T.nilable(T::Array[Integer]),
      enterprise_server_primary_emails: T.nilable(T::Array[String]),
      enterprise_server_advanced_security_user_ids: T.nilable(T::Array[Integer]),
      enterprise_server_code_security_user_ids: T.nilable(T::Array[Integer]),
      enterprise_server_secret_protection_user_ids: T.nilable(T::Array[Integer]),
      github_com_user: T.nilable(T::Boolean),
      github_com_login: T.nilable(String),
      github_com_name: T.nilable(String),
      github_com_profile: T.nilable(String),
      github_com_member_roles: T.nilable(T::Array[String]),
      github_com_enterprise_roles: T.nilable(T::Array[String]),
      github_com_verified_domain_emails: T.nilable(T::Array[String]),
      github_com_saml_name_id: T.nilable(T.any(Integer, String)),
      github_com_orgs_with_pending_invites: T.nilable(T::Array[String]),
      github_com_two_factor_auth: T.nilable(T::Boolean),
      github_com_two_factor_auth_required_by_date: T.nilable(String),
      github_com_cost_center: T.nilable(String),
      github_com_advanced_security_license_user: T.nilable(T::Boolean),
      github_com_code_security_license_user: T.nilable(T::Boolean),
      github_com_secret_protection_license_user: T.nilable(T::Boolean),
      visual_studio_subscription_user: T.nilable(T::Boolean),
      visual_studio_subscription_email: T.nilable(String),
      visual_studio_license_status: T.nilable(String),
      ghe_license_active: T.nilable(T::Boolean),
      ghe_license_start_date: T.nilable(DateTime),
      ghe_license_end_date: T.nilable(DateTime)
    )
    .returns(T::Hash[Symbol, T.untyped])
  end
  def build_usage_row(
    sorting_key:,
    license_type:,
    total_user_accounts: 0,
    enterprise_server_user: false,
    enterprise_server_user_ids: [],
    enterprise_server_primary_emails: [],
    enterprise_server_advanced_security_user_ids: [],
    enterprise_server_code_security_user_ids: [],
    enterprise_server_secret_protection_user_ids: [],
    github_com_user: false,
    github_com_login: "",
    github_com_name: nil,
    github_com_profile: nil,
    github_com_member_roles: [],
    github_com_enterprise_roles: [],
    github_com_verified_domain_emails: [],
    github_com_saml_name_id: nil,
    github_com_orgs_with_pending_invites: [],
    github_com_two_factor_auth: nil,
    github_com_two_factor_auth_required_by_date: nil,
    github_com_cost_center: nil,
    github_com_advanced_security_license_user: false,
    github_com_code_security_license_user: false,
    github_com_secret_protection_license_user: false,
    visual_studio_subscription_user: false,
    visual_studio_subscription_email: nil,
    visual_studio_license_status: nil,
    ghe_license_active: nil,
    ghe_license_start_date: nil,
    ghe_license_end_date: nil
  )
    {
      sorting_key: sorting_key,

      # First three rows prevent a mass of empty columns when skimming the left side
      github_com_login: github_com_login,
      github_com_name: github_com_name,
      enterprise_server_user_ids: enterprise_server_user_ids,

      # Gives an idea of types of auxiliary data to follow in subsequent columns
      github_com_user: github_com_user,
      enterprise_server_user: enterprise_server_user,
      visual_studio_subscription_user: visual_studio_subscription_user,

      license_type: license_type,

      # Dotcom info
      github_com_profile: github_com_profile,
      github_com_member_roles: github_com_member_roles,
      github_com_enterprise_roles: github_com_enterprise_roles,
      github_com_verified_domain_emails: github_com_verified_domain_emails,
      github_com_saml_name_id: github_com_saml_name_id,
      github_com_orgs_with_pending_invites: github_com_orgs_with_pending_invites,
      github_com_two_factor_auth: github_com_two_factor_auth,
      github_com_two_factor_auth_required_by_date: github_com_two_factor_auth_required_by_date,
      github_com_cost_center: github_com_cost_center,
      github_com_advanced_security_license_user: github_com_advanced_security_license_user,
      github_com_code_security_license_user: github_com_code_security_license_user,
      github_com_secret_protection_license_user: github_com_secret_protection_license_user,

      # License Details
      ghe_license_active: ghe_license_active,
      ghe_license_start_date: ghe_license_start_date,
      ghe_license_end_date: ghe_license_end_date,

      # GHES info
      enterprise_server_primary_emails: enterprise_server_primary_emails,
      enterprise_server_advanced_security_user_ids: enterprise_server_advanced_security_user_ids,
      enterprise_server_code_security_user_ids: enterprise_server_code_security_user_ids,
      enterprise_server_secret_protection_user_ids: enterprise_server_secret_protection_user_ids,

      # VSS info
      visual_studio_license_status: visual_studio_license_status,
      visual_studio_subscription_email: visual_studio_subscription_email,

      # Summary
      total_user_accounts: total_user_accounts,
    }
  end
end
