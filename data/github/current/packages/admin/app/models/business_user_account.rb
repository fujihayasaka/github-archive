# typed: true
# frozen_string_literal: true

# A user account on a business.
#
# Belongs to a single Business.
# Belongs to a single User.
# Has many EnterpriseInstallationUserAccounts.
class BusinessUserAccount < ApplicationRecord::Collab
  include GitHub::Relay::GlobalIdentification
  include GitHub::BatchedScope
  include BusinessUserAccount::Roles
  include BusinessUserAccount::GhecLicenses
  include Licensing::BusinessUserAccount::LicensingDependency

  belongs_to :user
  belongs_to :business
  has_many :enterprise_installation_user_accounts
  has_many :enterprise_installation_user_account_emails,
    through: :enterprise_installation_user_accounts,
    source: :emails

  has_many :avatars, through: :user

  validates :business, presence: true
  validates_uniqueness_of :user, scope: :business, allow_nil: true

  before_save :update_user, if: :user_id_changed?
  after_commit :snapshot_license_state
  after_commit :assign_user_to_bundled_license_assignment
  after_destroy :suspend_and_obfuscate_emus, if: :enterprise_managed_user?

  # Orphaned records don't have any associated cloud or server user accounts
  # `BusinessUserAccount.orphaned.delete_all` is run during enterprise installation
  # user account import, which does not trigger destroy hooks.
  scope :orphaned, -> { left_joins(:enterprise_installation_user_accounts).where(user_id: nil, enterprise_installation_user_accounts: { id: nil }) }

  # GHEC Licenses a user can have in a business.
  enum :ghec_license, {
    unlicensed: 0,
    enterprise_license: 1,
    vss_bundle_license: 2,
  }

  enum :two_factor_status, {
    disabled: 0,
    enabled: 1,
    required: 2,
  }, prefix: :two_factor

  def self.remove_members(user_ids)
    emit_removed_license_billing_message_for_user_ids(user_ids)
    orphaned_count = orphaned.count
    destroyed_count = T.let(0, Integer)
    business_ids = where(user_id: user_ids).pluck(:business_id).uniq
    matching_accounts = where(user_id: user_ids)
    BusinessUserAccount.transaction do
      with_write do
        matching_accounts.update_all(user_id: nil)
        orphaned_accounts = with_read { matching_accounts.merge(orphaned.all) }
        destroyed_count = orphaned_accounts.destroy_all.size
      end
    end
    GitHub.logger.info(
      "BusinessUserAccount#remove_members",
      business_id: business_ids,
      orphaned_count_post: orphaned.count,
      orphaned_count_pre: orphaned_count,
      remove_members_count: [user_ids].flatten.size,
      removed_members_count: destroyed_count,
      user_ids: user_ids
    )
  end

  # Public: Scope to get users with specified role
  def self.with_business_role(role)
    role_value = BusinessUserAccount::Roles::BUSINESS_ROLES[role]
    if role_value == 0
      where(business_roles_bitfield: 0)
    else
      where("business_roles_bitfield & ? > 0", role_value)
    end
  end

  # Public: Batch operation to add a business role to multiple business user accounts.
  def self.add_business_role_to_accounts(role, user_accounts)
    return if user_accounts.empty? || role == :unaffiliated
    return unless BUSINESS_ROLES.key?(role)

    role_value = BUSINESS_ROLES[role]
    bua_ids = user_accounts.map(&:id)

    query = Arel.sql(<<-SQL, role_value: role_value, bua_ids: bua_ids)
      UPDATE business_user_accounts
      SET business_roles_bitfield = COALESCE(business_roles_bitfield, 0) | :role_value
      WHERE id IN (:bua_ids)
    SQL

    self.connection.update(query)
  end

  # Public: Batch operation to remove a role from multiple business user accounts.
  def self.remove_business_role_from_accounts(role, user_accounts)
    return if user_accounts.empty? || role == :unaffiliated
    return unless BUSINESS_ROLES.key?(role)

    role_value = BUSINESS_ROLES[role]
    bua_ids = user_accounts.map(&:id)

    query = Arel.sql(<<-SQL, role_value: role_value, bua_ids: bua_ids)
      UPDATE business_user_accounts
      SET business_roles_bitfield = COALESCE(business_roles_bitfield, 0) & ~:role_value
      WHERE id IN (:bua_ids)
    SQL

    self.connection.update(query)
  end

  # Public: Scope to get all licensed users
  def self.licensed_users
    where("ghec_license > ?", 0)
  end

  def name
    if user
      T.must(user).profile_name
    else
      # user could have multiple enterprise_installation_user_accounts with different profile_names or logins
      # for now, sort and take the first profile_name
      enterprise_installation_user_accounts.map(&:profile_name).compact.sort.first
    end
  end

  def display_login
    if user
      T.must(user).display_login
    else
      login
    end
  end

  def avatar_url(size = nil)
    user&.primary_avatar_url(size)
  end

  def platform_type_name
    "EnterpriseUserAccount"
  end

  def two_factor_authentication_enabled?
    user&.two_factor_authentication_enabled?
  end

  # Public: Get the enterprise installations this BusinessUserAccount is associated with.
  #
  # All arguments optional.
  #
  # query:              - The user-provided query string with any filters (example: `role`) removed,
  #                       matched against the installation host name and/or customer name
  # order_by_field      - a String specifying the sort field
  # order_by_direction  - a String specifying the sort direction
  # role                - filter enterprise installations by the user's role. either `member` or `owner`
  #
  # Returns an ActiveRecord::Relation
  def user_enterprise_installations(query: nil, order_by_field: nil, order_by_direction: nil, role: nil)
    user_accounts = enterprise_installation_user_accounts

    unless role.nil? || user_accounts.empty?
      selected_role_is_site_admin = (role == "owner")

      user_accounts = user_accounts.select do |user_account|
        user_account.site_admin == selected_role_is_site_admin
      end
    end

    scope = T.must(business)
      .enterprise_installations
      .where(id: user_accounts.map(&:enterprise_installation_id))

    query = ActiveRecord::Base.sanitize_sql_like(query.to_s.strip.downcase)
    if query.present?
      scope = scope.where(["host_name LIKE :query OR customer_name LIKE :query", { query: "%#{query}%" }])
    end

    if order_by_field.present? && order_by_direction.present?
      scope = scope.order("#{order_by_field} #{order_by_direction}")
    end

    scope
  end

  # Public: Get the enterprise organizations that this BusinessUserAccount is a member of.
  #
  # viewer - required, the user who is requesting to list the BusinessUserAccount's organization memberships
  #
  # optional arguments
  #
  # query:              - The user-provided query string with any filters (example: `role`) removed
  # order_by_field      - a String specifying the sort field
  # order_by_direction  - a String specifying the sort direction
  # org_member_type     - filter to return organizations based on the user's membership type (:admin, :member_without_admin, :all)
  #                       default: :all
  #
  # Returns an ActiveRecord::Relation
  def enterprise_organizations(viewer, query: nil, order_by_field: nil, order_by_direction: nil, org_member_type: :all)
    # server-only members won't have a dotcom User or Organizations they're a part of
    return Organization.none if user.nil?

    scope = T.must(business).organizations.where(id: T.must(user).organizations)

    query = ActiveRecord::Base.sanitize_sql_like(query.to_s.strip.downcase)
    if query.present?
      scope = scope.includes(:profile)
        .where(["users.login LIKE :query OR profiles.name LIKE :query", { query: "%#{query}%" }])
        .references(:profile)
    end

    unless T.must(business).owner?(viewer) || viewer.site_admin?
      viewable_org_ids = T.must(user).public_organizations.pluck(:id) | viewer.organizations.pluck(:id)
      scope = scope.where(id: viewable_org_ids)
    end

    unless org_member_type == :all
      viewable_org_ids = T.must(business)
        .organizations_for_member(
          user,
          type: org_member_type,
        ).pluck(:id)

      scope = scope.where(id: viewable_org_ids)
    end

    if order_by_field.present? && order_by_direction.present?
      scope = scope.order("users.#{order_by_field} #{order_by_direction}")
    end

    scope.distinct
  end

  # Public: Get the enterprise teams that this BusinessUserAccount is a member of.
  #
  # optional arguments
  #
  # query:              - The user-provided query string with any filters (example: `role`) removed
  # order_by_field      - a String specifying the sort field
  # order_by_direction  - a String specifying the sort direction
  # org_member_type     - filter to return organizations based on the user's membership type (:admin, :member_without_admin, :all)
  #                       default: :all
  #
  # Returns an ActiveRecord::Relation
  def enterprise_teams(query: nil, order_by_direction: nil)
    return Team.none if user.nil?

    business_teams_ids = T.must(business).organizations.joins(:teams).pluck("teams.id")
    scope = T.must(user).teams.where(id: business_teams_ids)

    query = ActiveRecord::Base.sanitize_sql_like(query.to_s.strip.downcase)
    if query.present?
      scope = scope.where(["teams.name LIKE :query", { query: "%#{query}%" }])
    end

    if order_by_direction.present?
      scope = scope.order("teams.name #{order_by_direction}")
    end

    scope.distinct
  end

  # Public: Get the org member type Symbol based on a role String.
  #
  # role - String, either "member" or "owner"
  #
  # Returns Symbol
  def self.org_member_type_from_role(role)
    case role
    when "owner"
      :admin
    when "member"
      :member_without_admin
    else
      :all
    end
  end

  def two_factor_status_type(user)
    return :enabled if User.where(id: user.id).two_factor_enabled.any?
    return :required if User.where(id: user.id).two_factor_disabled.with_account_two_factor_requirement.any?
    return :disabled if User.where(id: user.id).two_factor_disabled.any?
    nil
  end

  def has_any_given_2fa_methods_configured?(methods)
    user&.has_any_given_2fa_methods_configured?(methods)
  end

  def update_user
    if user
      self.login = T.must(user).display_login
      self.profile_name = T.must(user).profile_name
      # Since the query in external_identity_emails is running against external identity attributes
      # and for an EMU we are still in a transaction, I believe we were getting deadlocks from this query on Proxima.
      # At the time of a creation of this business user account, the external identity is not created yet and
      # external_identity_emails query always returns an empty array.
      # EMUs currently only support a single email, so getting verified emails will return the modified email
      # with the shortcode, the profile email will contains an unmodified email sent from an IdP.
      if enterprise_managed_user?
        self.verified_emails = [
          T.must(user).emails.verified.pluck(:email),
          T.must(user).profile_email
        ].flatten.compact.join(",")
      else
        self.verified_emails = [
          T.must(user).emails.verified.pluck(:email),
          external_identity_emails
        ].flatten.compact.join(",")
      end
      self.two_factor_status = self.two_factor_status_type(user)
      self.spammy = T.must(user).spammy?
    else
      self.login = enterprise_installation_user_account_emails.where(primary: true).limit(1).pluck(:email).first || enterprise_installation_user_accounts.limit(1).pluck(:login).first || ""
      self.profile_name = nil
      self.verified_emails = nil
      self.two_factor_status = nil
      self.spammy = false
    end
  end

  private

  def enterprise_managed_user?
    !!user&.is_enterprise_managed?
  end

  def suspend_and_obfuscate_emus
    SuspendEmuAndRemoveExternalIdentityJob.perform_later(
      user_id: T.must(user).id,
      obfuscate_users: true,
      obfuscate_with_shortcode: false
    )
  end

  def external_identity_emails
    return nil unless T.must(business).external_provider.present?
    provider = T.must(business).external_provider
    ExternalIdentityAttribute
      .joins(:external_identity)
      .where("external_identities.user_id = :user_id AND external_identities.provider_id = :provider_id AND external_identities.provider_type = :provider_type",
        user_id: T.must(user).id,
        provider_id: provider.id,
        provider_type: provider.class.name
      ).where("name = :name_id OR name = :emails", name_id: "NameID", emails: "emails").pluck(:value)
  end

  def self.emit_removed_license_billing_message_for_user_ids(user_ids)
    removed_accounts = where(user_id: user_ids).compact
    # All accounts belong to the same business. Check emission state on one account to avoid looping through the
    # rest of the accounts.
    return if removed_accounts.none?
    return unless removed_accounts.first.can_emit_billing_message?

    removed_accounts.each do |account|
      account.emit_removed_license_billing_message if account.has_ghec_license?
    end
  end
  private_class_method :emit_removed_license_billing_message_for_user_ids
end
