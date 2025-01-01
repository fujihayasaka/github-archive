# typed: true
# frozen_string_literal: true

require "github/enterprise_accounts/kv"

# A `Business` represents an "enterprise account" to end-users. It is a collection of organizations.

# This model is intended to act as a gateway for a business's billing information, usage limits, and member
# organizations. Each Business instance is related to a Customer model which actually houses billing information. For
# more background information,
# see: https://github.com/github/gitcoin/blob/main/projects/lawncraft/outline.md
class Business < ApplicationRecord::Domain::Users
  include Admin::IBusiness

  include GitHub::Relay::GlobalIdentification
  include GitHub::Validations
  include Ability::Subject
  include Ability::Membership
  include ApplicationHelper
  include PrimaryAvatar::Model
  include Avatar::List::Model
  include Instrumentation::Model
  include GitHub::FlipperActor
  include GitHub::VexiActor
  include GitHub::ApplicationsCreationLimit
  include Configurable::DefaultNewRepoBranch
  include Business::ActionsDependency
  include Business::AdvancedSecurityDependency
  include Business::BillingDependency
  include Business::BillingManagementDependency
  include Business::BillingTransactionsDependency
  include Business::CodespacesDependency
  include Business::CouponsDependency
  include Business::EnterpriseAgreementDependency
  include Business::LicenseDependency
  include Business::ConfigurationDependency
  include Business::TwoFactorRequirementDependency
  include Business::ExternalProviderDependency
  include Business::SamlSsoDependency
  include Business::PeopleDependency
  include Business::RepositoryDependency
  include Business::SecurityCenterDependency
  include Business::DependabotAlertsDependency
  include Business::SettingsDependency
  include Business::SupportEntitleeDependency
  include Business::ManagedUserDependency
  include Business::NotificationRestrictionsDependency
  include Business::TradeControlsDependency
  include Business::SponsorsDependency
  include Business::TradeScreeningDependency
  include Spam::MarkableAsSpammy
  include Suspension::SuspensionDependency
  include Business::InstrumentationDependency
  include Business::TokenScanningDependency
  include Business::FeatureFlagMethods
  include Billing::Public::Product::Subscribable
  include OnboardingTasks::Taskable
  include Coders::CodableColumn
  include GitHub::BatchedScope
  include Business::CustomerCategoryDependency
  include Business::CopilotDependency
  include Business::TrialDependency
  include StaffNotesDependency
  include KillSwitch
  include Repositories::Domain::Provider
  include RuleEngine::RuleSettingsDependency
  include Business::SecurityProductsDependency
  include Business::TrialDependency
  include Business::CustomRolesDependency

  include Permissions::Attributes::Wrapper
  self.permissions_wrapper_class = Permissions::Attributes::Business

  SLUG_REGEX = /\A[a-z0-9]+(-[a-z0-9]+)*\z/i
  SLUG_VALIDATION_MESSAGE = "may only contain alphanumeric characters or single hyphens, and cannot begin or end with a hyphen"
  SHORTCODE_REGEX = /\A[a-zA-Z0-9]+\z/i
  SHORTCODE_VALIDATION_MESSAGE = "may only contain alphanumeric characters"
  MIN_SHORTCODE_LENGTH = 3
  MAX_SHORTCODE_LENGTH = 8
  MAX_NAME_LENGTH = 60
  MAX_SLUG_LENGTH = 60
  MAX_DESCRIPTION_LENGTH = 160
  MAX_LONG_DESCRIPTION_LENGTH = 125_000
  MAX_WEBSITE_URL_LENGTH = 255
  MAX_LOCATION_LENGTH = 255
  TERMS_OF_SERVICE_TYPES = ["Corporate", "Custom", "ESA+Education"].freeze
  TERMS_OF_SERVICE_TYPE_DESCRIPTIONS = ["Corporate", "Custom", "Corporate + Education"].freeze
  MAX_TERMS_OF_SERVICE_NOTES_LENGTH = 255
  EXCLUDE_FROM_SINGLE_BUSINESS_ORGS = [GitHub.trusted_oauth_apps_org_name].freeze
  OWNER_ROLE = :owner
  BILLING_MANAGER_ROLE = :billing_manager
  UNAFFILIATED_ROLE = :unaffiliated
  ADMIN_ROLES = [OWNER_ROLE, BILLING_MANAGER_ROLE].freeze
  DELETE_BATCH_SIZE = 1000
  CANCEL_BATCH_SIZE = 1000
  RESTORABLE_PERIOD = 90.days
  EXPIRED_TRIAL_DELETION_CUTOFF_DATE = DateTime.new(2023, 2, 1).freeze
  TRIAL_ORG_CREATION_LIMIT = 3
  ORPHANED_SHORTCODES = %w(
    lmigpoc
    tally
    readev
    cinins
    hillrom
    infatest
    trvtest
    polive
    bnvtest
    expdtest
  )
  RESOURCE_CREATION_ELIGIBLE_COUNTRY_CODE = %w[US CA]
  STARTUP_PROGRAM_COUPONS = %w[GFSYR1 GFSPartnerYR1 GFSYR2 MSYR2]
  STARTUP_PROGRAM_COUPONS_PREFIX = %w[gfs- gfspartner-]

  enum :business_type, { default_managed: 0, enterprise_managed: 1 }

  # Describes the current Business creation lifecycle state. The states offer information on how the account was created.
  # This allows restriction of functionality when needed, and facilitiates tracking and metrics. This 'trial_completion_status'
  # enum is no longer only trial related, as it now deals with Businessess created in many other ways (org upgrades, coupon redemption).
  # This enum should be renamed at some point in the future.
  enum :trial_completion_status, {
    no_trial_or_active_trial: 0,
    trial_converted: 1,
    trial_expired: 2,
    trial_cancelled: 3,
    trial_conversion_initiated: 4,
    organization_upgrade_initiated: 10,  # Enterprise has been created in order to upgrade an organization
    organization_upgrade_purchase_initiated: 11,  # Enterprise created to upgrade an organization, with payment in progress
    organization_upgrade_completed: 12, # Enterprise created to upgrade an organization, with payment completed
    organization_direct_upgraded: 13, # Enterprise created to upgrade an Enterprise-plan organization, no payment flow necessary
    creation_initiated_from_coupon: 14, # Enterprise has been created in the process of redeeming a coupon
    creation_from_coupon_purchase_initiated: 15, # Enterprise has been created in the process of redeeming a coupon, with payment in progress
    created_from_coupon: 16, # Enterprise has been created by completing coupon redemption
  }

  # Defaults to full (paid per seats)
  # Basic is currently being used for Copilot-only accounts
  enum :seats_plan_type, { full: 0, basic: 1 }, prefix: :seats_plan

  # Raised when an attempt to delete the last admin is made.
  class NoAdminsError < StandardError; end

  # Raised when an attempt to create a business in addition to the single global
  # business is made. Only possible when GitHub.single_business_environment?
  class SingleGlobalBusinessError < StandardError; end

  # Raised if an attempt is made to add an admin without 2FA enabled
  # when the business requires 2FA to be enabled.
  class UserHasTwoFactorDisabledError < StandardError; end

  # Raised if an attempt is made to add an admin without an external identity
  # when the business requires that SAML SSO is enabled
  class UserHasNoExternalIdentityError < StandardError; end

  # More generic error raised if an attempt is made to add an admin who is in an
  # invalid state to become an admin.
  #
  # This currently includes users marked as suspended or deceased.
  class InvalidAdminStateError < StandardError; end

  # Raised if trying to change the admin's user role (owner <=> billing manager)
  # but the given user isn't an admin
  class UserNotAnAdminError < StandardError; end

  # Raised when a forbidden attempt is made to remove a member from this Enterprise
  # Example: the user is the last admin in an Organization belonging to the Enterprise
  class ForbiddenRemovalError < StandardError; end

  # Raised when an attempt is made to remove a member from this Enterprise that cannot
  # be processed. Example: The Enterprise can't self-serve
  class InvalidRemovalError < StandardError; end

  # Raised when an attempt to add a user as admin to an EMU enterprise fails due to user creation failure
  class UnableToCreateAdminUserError < StandardError; end

  # Raised when an attempt to reset the admin user on an EMU enterprise fails due to user not yet existing failure
  class UnableToFindExistingAdminUserError < StandardError; end

  # Raised when an attempt to add a user as admin to an EMU enterprise fails due to existing admin user
  class AdminAlreadyExistsError < StandardError; end

  # Raised when an attempt to review a business that was upgraded from an organization and is
  # already reviewed is made, to prevent overwriting already existing review data.
  class AlreadyReviewedUpgradeError < StandardError; end

  # Raised when an attempt to sync billing settings of an organization without an owner is made.
  class NoOrganizationOwnerError < StandardError; end

  # Raised when attempting to perform a one-time payment for a business's
  # bill but certain checks fails.
  class OnetimePaymentsError < StandardError; end

  # Raised when soft-deletion of the Business is unsupported.
  class SoftDeletionUnsupportedError < StandardError; end

  belongs_to :upgraded_from, class_name: "Organization"
  belongs_to :upgrade_initiated_from_organization, class_name: "Organization"
  belongs_to :upgrade_reviewed_by, class_name: "User"
  has_many :audit_log_git_event_exports, as: :subject, dependent: :destroy
  has_many :audit_log_web_exports, as: :subject, dependent: :destroy
  has_many :hooks, as: :installation_target, dependent: :destroy
  has_many :organization_memberships, class_name: "Business::OrganizationMembership"
  has_many :organizations,
    -> {
      # In case the github-enterprise org is added to the single global business,
      # make sure they are never included in business org results. We also exclude
      # soft-deleted organizations.
      return scoped.active unless GitHub.single_business_environment?
      where.not(login: EXCLUDE_FROM_SINGLE_BUSINESS_ORGS)
    },
    through: :organization_memberships,
    dependent: :destroy

  has_many :soft_deleted_organizations,
    -> { return scoped.soft_deleted },
    through: :organization_memberships,
    source: :organization,
    dependent: :destroy

  has_many :credential_authorizations,
    through: :organizations,
    class_name: "Organization::CredentialAuthorization"

  # rubocop:todo Rails/InverseOf
  has_one :prerelease_agreement,
    -> { where(member_type: "Business") },
    foreign_key: :member_id,
    as: :member,
    class_name: "PrereleaseProgramMember"
  # rubocop:enable Rails/InverseOf

  has_one :saml_provider,
    class_name: "Business::SamlProvider",
    inverse_of: :target,
    dependent: :destroy

  has_one :oidc_provider,
    class_name: "Business::OIDCProvider",
    inverse_of: :target,
    dependent: :destroy

  has_one :team_sync_tenant,
    class_name: "TeamSync::BusinessTenant",
    inverse_of: :business,
    dependent: :destroy

  has_many :audit_log_stream_configurations,
    class_name: "AuditLogStreamConfiguration",
    inverse_of: :business,
    dependent: :destroy

  has_many :invitations, class_name: "BusinessAdministratorInvitation", dependent: :destroy
  has_many :organization_invitations, class_name: "BusinessOrganizationInvitation", dependent: :destroy
  has_many :user_accounts, class_name: "BusinessUserAccount", dependent: :destroy
  has_many :enterprise_agreements, class_name: "Licensing::EnterpriseAgreement", dependent: :destroy
  has_many :business_report_exports, as: :owner, dependent: :destroy

  # Public: Installations for an Integration
  has_many :integration_installations, as: :target, dependent: :destroy

  # Public: Integrations owned by this Business
  has_many :integrations,
    dependent: :destroy,
    as: :owner

  has_many :enterprise_installations, as: :owner, dependent: :destroy
  has_many :enterprise_installation_user_accounts_uploads, dependent: :destroy
  has_many :enterprise_contributions, dependent: :destroy

  has_many :ssh_certificate_authorities, as: :owner, dependent: :destroy

  has_many :ip_allowlist_entries, as: :owner, dependent: :destroy

  has_many :metered_usage_exports,
    class_name: "Billing::MeteredUsageExport",
    as: :billable_owner

  has_many :verifiable_domains, as: :owner, dependent: :destroy

  has_many :footer_links, class_name: "BusinessFooterLink", dependent: :destroy
  has_many :billing_external_emails, as: :owner, dependent: :delete_all

  has_many :staff_notes, as: :notable, dependent: :destroy

  has_many :policy_groups, as: :owner, class_name: "Codespaces::PolicyGroup", dependent: :destroy

  has_one :startups_program, class_name: "BusinessStartupsProgram", dependent: :destroy
  has_many :enterprise_teams, dependent: :destroy
  has_many :business_teams, dependent: :destroy

  has_many :ghes_licenses,
    class_name: "Licensing::GhesLicense",
    inverse_of: :business,
    dependent: :destroy

  has_many :rulesets, as: :source, class_name: "RepositoryRuleset"
  destroy_dependents_in_background :rulesets

  serialize_with_coder :raw_data, Coders::BusinessCoder

  delegate :metered_plan,
           :metered_plan?,
           :metered_ghe,
           :metered_ghe?,
           :plan_subscription,
           :autopay_disabled_by_trade_controls?,
           :metered_via_azure,
           :metered_via_azure?,
           :billed_via_billing_platform?,
           to: :customer, allow_nil: true

  accepts_nested_attributes_for :footer_links,
                                reject_if: :all_blank,
                                allow_destroy: true

  accepts_nested_attributes_for(:customer, update_only: true)

  before_validation :generate_slug, on: :create
  before_validation :set_default_terms_of_service_company_name
  before_create :ensure_single_global_business, if: -> { GitHub.single_business_environment? }
  after_create :grant_initial_owners
  after_create :create_user_accounts_for_members, unless: -> { GitHub.single_business_environment? }
  after_create :initialize_workflow_permissions
  after_create :update_license_usage
  after_create :set_default_emu_repo_collab_policy, if: :enterprise_managed_user_enabled?
  after_create :initialize_deploy_key_policy
  after_update :sync_all_organization_billing_settings, if: :synced_billing_settings_changed?
  after_update :instrument_change_billing_plan, if: proc {
    T.bind(self, Business)
    saved_change_to_downgraded_at? || saved_change_to_plan_duration?
  }
  after_update_commit :instrument_billing_email_change, if: :saved_change_to_billing_email?
  after_create_commit  :instrument_creation
  after_create_commit  :instrument_accept_terms_of_service
  after_create_commit  :set_default_fine_grained_token_expiration_limit
  after_destroy_commit :instrument_destruction
  after_commit :remove_billing_managers, on: :destroy
  after_commit :remove_all_support_entitlees, on: :destroy
  after_commit :remove_first_emu_owner, on: :destroy
  after_commit :destroy_custom_properties, on: :destroy
  after_commit :instrument_update_terms_of_service, on: [:create, :update]
  after_commit :synchronize_search_index
  after_commit :set_spammy_notice, on: [:create, :update], if: -> {
    T.bind(self, Business)
    previous_changes[:spammy]
  }
  after_commit :soft_delete_pages, on: :update, if: :saved_change_to_downgraded_at?

  validates :slug,
    presence: true,
    length: { maximum: MAX_SLUG_LENGTH },
    format: { with: SLUG_REGEX, message: SLUG_VALIDATION_MESSAGE, allow_blank: true },
    if: :slug_changed?
  validates :slug,
    uniqueness: {
      case_sensitive: false,
      message: "is already taken by another enterprise account"
    },
    if: -> {
      T.bind(self, Business)
      errors[:slug].blank?
    }
  validates :name, presence: true, length: { maximum: MAX_NAME_LENGTH, allow_blank: true }
  validate  :ensure_initial_owners_are_all_users, on: :create
  validates :terms_of_service_type, presence: true, inclusion: {
    in: TERMS_OF_SERVICE_TYPES, message: "%{value} is not a valid terms of service type"
  }
  validates :terms_of_service_company_name, length: { maximum: MAX_NAME_LENGTH, allow_blank: true }
  validates :terms_of_service_notes, unicode3: true, length: { maximum: MAX_TERMS_OF_SERVICE_NOTES_LENGTH, allow_blank: true }
  validates :seats, presence: true, numericality: true
  validate  :ensure_enough_seats, if: :seats_changed?
  validates :website_url, unicode3: true, length: { maximum: MAX_WEBSITE_URL_LENGTH }
  validate :ensure_website_url_is_valid, if: :website_url?
  validates :location, length: { maximum: MAX_LOCATION_LENGTH }
  validates :description, length: { maximum: MAX_DESCRIPTION_LENGTH }
  validates :long_description, length: { maximum: MAX_LONG_DESCRIPTION_LENGTH }

  validates_format_of :billing_email,
    with: User::EMAIL_REGEX,
    message: "does not look like an email address",
    allow_blank: true
  validates :billing_email, unicode3: true
  validates :enterprise_web_business_id,
    numericality: { only_integer: true, greater_than: 0 },
    uniqueness: { message: "is already taken by another enterprise account" },
    allow_blank: true
  validates :business_type, presence: true, inclusion: { in: business_types.keys }
  validate :business_type_not_modified
  validates :shortcode,
    if: :enterprise_managed?,
    presence: { message: "required to enable enterprise managed users" },
    format: { with: SHORTCODE_REGEX, message: SHORTCODE_VALIDATION_MESSAGE, allow_blank: true },
    length: { in: MIN_SHORTCODE_LENGTH..MAX_SHORTCODE_LENGTH, allow_blank: true,
      unless: :any_length_shortcode_feature_flag_enabled, on: :create },
    uniqueness: { case_sensitive: false, message: "is already taken by another enterprise account", allow_blank: true }
  validates :shortcode,
    if: :default_managed?,
    absence: { message: "only allowed when enterprise managed users is enabled" }
  validate :shortcode_not_modified

  # The skip_ghas_seats_validation is used when a self-serve Advanced Security subscription
  # is being cancelled and refunded through a background job. The validation will fail because
  # the seat count has not yet been updated to reflect the cancellation (since it depends on the
  # background job), but the Advanced Security subscription is already marked as not purchased.
  validate :ensure_ghas_seats_valid, unless: :skip_ghas_seats_validation
  attr_accessor  :skip_ghas_seats_validation

  attribute :name, StringFromBinary.new
  attribute :terms_of_service_company_name, StringFromBinary.new
  attribute :description, StringFromBinary.new
  attribute :long_description, StringFromBinary.new

  # This should only be set by long-lived feature flag GitHub.flipper[:any_length_shortcode].enabled?(current_user)
  # The feature flag is allowed for specific users, not businesses or other type of actors or globally enabled.
  attr_accessor :any_length_shortcode_feature_flag_enabled

  # Set when a metered business activates GitHub Enterprise to aid in identifying if the business wants to talk to
  # sales about payment and term options.
  attr_accessor :talk_to_sales


  # Internal: an abstract collection, for the sub-resources of an Business available for abilities
  def resources
    Business::Resources.new(self)
  end

  def part_of_startup_program?
    !!startups_program&.currently_in_the_program?
  end

  # Given an organization ID, find the business that the organization belongs to
  # in a single query.
  #
  # org_id - Integer organization ID
  #
  # Returns the owning Business otherwise nil.
  def self.from_org_id(org_id)
    return unless org_id
    joins(:organization_memberships)
      .where(business_organization_memberships: { organization_id: org_id })
      .first
  end

  def to_s
    slug
  end

  def display_login
    slug
  end

  def to_param
    slug
  end

  default_scope -> { where(deleted_at: nil) }
  scope :including_deleted, -> { unscope(where: :deleted_at) }
  scope :deleted, -> { unscope(where: :deleted_at).where.not(deleted_at: nil) }
  scope :purgeable, -> { unscope(where: :deleted_at).where("deleted_at < ?", RESTORABLE_PERIOD.ago) }

  scope :by_slug, -> { order("slug ASC") }

  scope :is_staff_owned, ->(staff) { where(staff_owned: staff) }
  scope :not_staff_owned, -> { where(staff_owned: false) }

  scope :for_query, ->(query) {
    safe_query = ActiveRecord::Base.sanitize_sql_like(query.to_s.strip)
    return scoped unless safe_query.present?

    where <<-SQL, query: "%#{safe_query}%"
      businesses.slug LIKE :query OR businesses.name LIKE :query
    SQL
  }

  scope :upgraded_and_not_reviewed, -> {
    joins(:customer).where(customers: { billing_type: Customer::BILLING_TYPE_INVOICE })
    .where <<-SQL
      businesses.upgraded_at IS NOT NULL
      AND businesses.upgraded_from_plan <> 'free'
      AND businesses.upgrade_reviewed_at IS NULL
    SQL
  }

  scope :upgraded_and_reviewed, -> {
    joins(:customer).where(customers: { billing_type: Customer::BILLING_TYPE_INVOICE })
    .where("businesses.upgraded_at IS NOT NULL AND businesses.upgrade_reviewed_at IS NOT NULL")
  }

  scope :self_serve_organization_upgrading_or_upgraded, -> {
    joins(:customer).where(customers: { billing_type: Customer::BILLING_TYPE_CARD })
    .where(
      trial_completion_status: [
        :organization_upgrade_initiated,
        :organization_upgrade_purchase_initiated,
        :organization_upgrade_completed,
        :organization_direct_upgraded,
        :creation_initiated_from_coupon,
        :creation_from_coupon_purchase_initiated,
        :created_from_coupon,
    ]).or( # will likely want to remove this section below once the transition is complete
      joins(:customer).where(customers: { billing_type: Customer::BILLING_TYPE_CARD })
      .where(
        trial_completion_status: :no_trial_or_active_trial,
        trial_expires_at: nil,
      )
      .where.not(upgraded_at: nil)
    )
  }

  scope :auto_pay_rbi_disabled, -> {
    joins(:customer)
    .where(trial_expires_at: nil)
    .where.not(trial_completion_status: :trial_cancelled)
    .where(customers: { billing_type: Customer::BILLING_TYPE_CARD })
    .where("customers.auto_pay_reasons like ?", "%:india_rbi%")
  }

  scope :spammy, -> { where(spammy: true) }
  scope :not_spammy, -> { where(spammy: false) }

  scope :not_trial, -> { where(trial_expires_at: nil) }
  scope :trial, -> { where.not(trial_expires_at: nil) }
  scope :trial_active, -> { where("trial_expires_at > ?", Time.current) }
  scope :trial_expired, -> { where("trial_expires_at <= ?", Time.current) }
  scope :trial_not_completed, -> { trial.where(trial_completed_at: nil) }
  scope :trial_with_conversion_initiated, -> {
    trial
    .where(trial_completion_status: :trial_conversion_initiated)
  }
  scope :trial_conversion_not_initiated, -> { trial.where(trial_conversion_initiated_at: nil) }
  scope :upgrade_purchase_initiated, -> {
    where(trial_completion_status: :organization_upgrade_purchase_initiated)
  }

  scope :metered_ghe, -> { joins(:customer).where(customers: { metered_plan: true }) }
  scope :volume_ghe, -> { joins(:customer).where(customers: { metered_plan: false }) }

  # Public: Is renaming of the business's slug supported?
  #
  # Returns Boolean.
  def url_change_supported?
    return false if GitHub.single_business_environment?
    return false if enterprise_managed_user_enabled?
    return false if spammy?
    true
  end

  # Public: Is self-serve renaming of the business's slug permitted?
  #
  # Returns Boolean.
  def self_serve_url_change_permitted?
    url_change_supported? && !invoiced?
  end

  # Public: Is self-serve deletion supported at all?
  #
  # Returns Boolean.
  def self_serve_deletion_supported?
    return false if GitHub.single_business_environment?
    return false if GitHub.multi_tenant_enterprise?
    return false if trial?
    return false if sales_managed?
    return false if enterprise_managed? && !self.feature_enabled?(:self_serve_emu_ea_deletion)
    true
  end

  # Public: Is self-serve deletion both supported and permitted?
  #
  # Returns Boolean.
  def self_serve_deletion_permitted?
    self_serve_deletion_supported? && !organizations_blocking_deletion?
  end

  # Public: Are there any member Organizations that block deletion of the Business?
  #
  # Returns Boolean.
  def organizations_blocking_deletion?
    organization_ids.any?
  end

  # Public: Should the Organization Orchestrator be used when adding/removing Org members?
  def use_organization_orchestrator?
    feature_enabled?(:organization_add_remove_orchestrator)
  end

  # Public: Returns soft deleted businesses the user was a member of.
  #
  # Returns ActiveRecord::Relation
  def self.soft_deleted_businesses_for(user, emu_admin: false)
    return Business.none if GitHub.single_business_environment?
    business_ids = if emu_admin
      user.business_user_accounts.roles([:emu_admin]).pluck(:business_id)
    else
      user.business_user_accounts.pluck(:business_id)
    end
    return Business.none if business_ids.none?
    Business.deleted.where(id: business_ids)
  end

  # Public: Returns cancelled trial businesses the user was a member of.
  #
  # Returns ActiveRecord::Relation
  def self.cancelled_trial_businesses_for(user, emu_admin: false)
    return Business.none if GitHub.single_business_environment?
    business_ids = if emu_admin
      user.business_user_accounts.roles([:emu_admin]).pluck(:business_id)
    else
      user.business_user_accounts.pluck(:business_id)
    end
    return Business.none if business_ids.none?
    Business.where(id: business_ids, trial_completion_status: :trial_cancelled)
  end

  # Public: Mark the Business as deleted but don't destroy it yet.
  #
  # actor - Optional User who performed the deletion. Defaults to nil.
  # self_serve - Optional Boolean indicating whether it was a self-serve deletion. Defaults to false.
  #
  # Returns nothing. Raises Business::SoftDeletionUnsupportedError.
  def soft_delete!(actor: nil, self_serve: false)
    if GitHub.single_business_environment?
      raise SoftDeletionUnsupportedError.new("Soft-deletion is not supported in this environment")
    end

    if enterprise_managed_user_enabled? &&
      !(actor&.feature_enabled?(:emu_ea_deletion) || self.feature_enabled?(:self_serve_emu_ea_deletion))
      raise SoftDeletionUnsupportedError.new("Soft-deletion is not currently supported on EMU enterprises")
    end

    if organizations_blocking_deletion? && self_serve
      raise SoftDeletionUnsupportedError.new("Soft-deletion is not permitted for enterprises with existing member organizations")
    end

    if trade_screening_record.delete_restricted?
      raise SoftDeletionUnsupportedError.new("Soft-deletion is not permitted for enterprises with trade restrictions")
    end

    touch :deleted_at
    payload = {}
    payload[:actor] = actor if actor.present?
    instrument_deletion(payload)

    find_first_emu_owner&.suspend("Soft-deleted enterprise", actor: actor) if enterprise_managed_user_enabled?
    BusinessMailer.business_deleted(actor, id).deliver_later if self_serve
    SoftDeleteBusinessJob.perform_later(T.must(id), self_serve: self_serve, actor: actor)
  end

  # Public: Is the Business marked as deleted (but not yet destroyed)?
  #
  # Returns Boolean.
  def deleted?
    deleted_at.present?
  end

  # Public: Checks whether Stafftools deletion of this Business is disabled.
  #
  # Returns a Boolean
  def stafftools_deletion_disabled?(actor)
    return true if GitHub.single_business_environment?
    return true if GitHub.multi_tenant_enterprise? && (stafftools_tenant? || !actor&.feature_enabled?(:proxima_tenant_deletion))
    return true if enterprise_managed? && !actor&.feature_enabled?(:emu_ea_deletion)
    false
  end

  # Public: Restore the Business if it was marked as deleted.
  #
  # Returns nothing.
  def restore!
    return unless deleted?

    business_deleted_at = deleted_at
    self.update! deleted_at: nil
    find_first_emu_owner.unsuspend("Soft-deleted enterprise restored", actor: actor) if enterprise_managed_user_enabled?

    restore_soft_deleted_org_repos(business_deleted_at)

    if self.eligible_for_expired_trial_deletion?
      self.update! trial_deleted_at: 8.days.from_now
    end

    instrument_restoration
    resume_billing
  end

  # Public: Is the user on a paid seat plan?
  #
  # user - Currently this attribute is not used in the check, but provided for future compatibility with per-seat licensing.
  #
  # Returns Boolean.
  def user_on_seat_plan?(user)
    return false if seats_plan_basic?
    return false if supports_unaffiliated_user_accounts? && exclusive_unaffiliated_member?(user)
    true
  end

  # Public: Can the business be transitioned to another seats plan?
  #
  # plan - The new seats plan
  def can_transition_to_seats_plan_type?(plan)
    can_transition_to_seats_plan_type_issues(plan).none?
  end

  # Public: What is blocking the business from transitioning to another seats plan?
  #
  # plan - The new seats plan
  #
  # Returns a Hash describing the issues with the key for the issue type and each key containing a Hash with
  # at least a message as well as other information that can be helpful, like :organization_ids in the case
  # of an issue with :organizations_present that need to be removed.
  def can_transition_to_seats_plan_type_issues(plan)
    plan = plan.to_s
    valid_plans = Business.seats_plan_types.keys.map(&:to_s)
    issues = {}
    unless valid_plans.include?(plan)
      issues[:invalid_plan] = { message: "The seats plan type is invalid. Only full and basic can be selected." }
    end
    # Can not transition to current plan
    if plan == seats_plan_type.to_s
      issues[:current_plan] = { message: "Can not transition to #{plan}, because the enterprise is already on #{plan}." }
      return issues
    end
    # Transition from full is only possible when there are no organizations in the business
    if seats_plan_full? && organizations.any?
      issues[:organizations_present] = {
        message: "There are existing organizations that must be removed.",
        organization_ids: organizations.pluck(:id)
      }
    end
    issues
  end

  # Public: Return the reason this enterprise cannot be transitioned to the given seats plan type as a String.
  #
  # plan - String representing the seats plan type.
  #
  # Returns String.
  def reason_unable_to_transition_to_seats_plan_type(plan)
    errors = []
    issues = can_transition_to_seats_plan_type_issues(plan)
    issues.each do |_, err|
      errors << err[:message]
    end
    errors.join(" ")
  end

  # Public: Transition this enterprise to the given seats plan type.
  #
  # plan - String representing the seats plan type.
  #
  # Returns Boolean.
  def transition_to_seats_plan_type(plan)
    return false unless can_transition_to_seats_plan_type?(plan)

    seats_plan_type_was = self.seats_plan_type

    updated_attributes = { seats_plan_type: plan.to_sym }
    updated_attributes[:seats] = 0 if plan.to_s == "basic"

    if update(updated_attributes)
      instrument_change_seats_plan_type \
        seats_plan_type_was: seats_plan_type_was,
        seats_plan_type: seats_plan_type

      if plan.to_s == "full"
        # Until the unaffiliated_user_accounts feature has shipped to all user accounts, we need to enable the
        # flag here to ensure the account owners are able to see all their existing unaffiliated user accounts.
        GitHub.flipper[:unaffiliated_user_accounts].enable(self)

        if metered_ghe?
          GitHub.flipper[:copilot_metered_enterprise].enable(self)
        end
      end
      update_license_usage

      true
    else
      false
    end
  end

  # Public: Returns filtered organizations for the enterprise.
  #
  # viewer - optional - The User requesting filtered organizations.
  # viewer_role - optional - String representing a viewer role in an Organization.
  #   When viewer is also provided, only Organizations where the viewer has this
  #   role will be returned. Valid roles are "owner", "member", and "unaffiliated".
  # two_factor_policy - optional - String, only return organizations that have the specified two-factor policy,
  #   don't apply any filter if nil.
  # has_deploy_keys - optional - Boolean, only return organizations that have deploy keys if true,
  #   only return organizations that do not have deploy keys if false,
  #   don't apply any filter if nil.
  # query - optional - String user-provided query value.
  # order_by_field - optional — String specifying the sort field. Supported: "login", "created_at". Default: "login".
  # order_by_direction - optional - String specifying the sort direction. Supported: "asc", "desc". Default: "asc".
  # can_enable_two_factor - optional - Boolean, only return organizations
  #   that can have two-factor authentication enabled if truthy.
  # team_sync_statuses - optional - Array of Symbol, only return organizations
  #   that have a team sync tenant with the appropriate status.
  # only_deleted - optional - Boolean, uses only soft deleted organizations.
  #
  # Returns ActiveRecord::Relation.
  def filtered_organizations(
    viewer: nil,
    viewer_role: nil,
    two_factor_policy: nil,
    has_deploy_keys: nil,
    query: nil,
    order_by_field: "login",
    order_by_direction: "asc",
    can_enable_two_factor: nil,
    team_sync_statuses: nil,
    only_deleted: false
  )
    orgs = only_deleted ? Organization.where(id: soft_deleted_organization_ids) : organizations

    # guest collaborators should filter for all organizations by default
    if viewer.present? && viewer.guest_collaborator?
      orgs = organizations_for_member(viewer, type: :all)
    elsif viewer.present? && viewer_role.present?
      case viewer_role
      when "owner"
        orgs = organizations_for_member(viewer, type: :admin)
      when "member"
        orgs = organizations_for_member(viewer, type: :member_without_admin)
      when "unaffiliated"
        member_org_ids = organizations_for_member(viewer, type: :all).pluck(:id)
        orgs = organizations.without_ids(member_org_ids)
      end
    end

    unless can_enable_two_factor.nil?
      orgs = organizations_can_enable_two_factor_requirement(!!can_enable_two_factor, orgs: orgs)
    end

    if team_sync_statuses
      orgs = orgs.with_team_sync_status(team_sync_statuses)
    end

    unless two_factor_policy.nil?
      orgs = organizations_two_factor_policy_filter(two_factor_policy, orgs: orgs)
    end

    unless has_deploy_keys.nil?
      orgs = organizations_with_deploy_keys_filter(!!has_deploy_keys, orgs: orgs)
    end

    orgs = apply_user_query_filter(orgs, query)

    # Ignore invalid order by field and direction
    order_by_field = "login" unless %w(login created_at).include?(order_by_field.to_s.downcase)
    order_by_direction = "asc" unless %w(asc desc).include?(order_by_direction.to_s.downcase)
    orgs.order(Arel.sql("users.#{order_by_field} #{order_by_direction}"))
  end

  # Public: Returns organizations within the enterprise without any admins.
  #
  # order_by_field - optional — String specifying the sort field. Supported: "login", "created_at". Default: "login".
  # order_by_direction - optional - String specifying the sort direction. Supported: "asc", "desc". Default: "asc".
  #
  # Returns ActiveRecord::Relation.
  def orphaned_organizations(
    order_by_field: "login",
    order_by_direction: "asc"
  )
    owned_orgs_ids = Ability.distinct.where(
      subject_id: organization_ids,
      subject_type: "Organization",
      actor_type: "User",
      action: "admin"
    ).pluck(:subject_id)

    orgs = organizations.where(id: organization_ids - owned_orgs_ids)

    # Ignore invalid order by field and direction
    order_by_field = "login" unless %w(login created_at).include?(order_by_field.to_s.downcase)
    order_by_direction = "asc" unless %w(asc desc).include?(order_by_direction.to_s.downcase)
    orgs.order(Arel.sql("users.#{order_by_field} #{order_by_direction}"))
  end

  # Public: Rename the URL slug of the business. If the URL slug is renamed
  # successfully and the new slug is different to the old slug, the
  # business.rename event is instrumented.
  #
  # slug - The String to use as the new URL slug.
  # actor - The User that is the actor renaming the URL slug.
  #
  # Returns a Boolean indicating whether the URL slug was renamed successfully.
  def rename_slug(slug, actor:)
    return false if spammy? && !actor.site_admin?

    slug_was = self.slug.dup
    updated = update slug: slug
    success = updated && slug_was != slug
    if success
      instrument :rename_slug, \
        slug_was: slug_was,
        slug: slug,
        actor: actor
      GlobalInstrumenter.instrument("enterprise_account.rename_slug", {
        enterprise: self,
        slug_was: slug_was,
        slug: slug,
      })
    end

    updated
  end

  # Public: Is the Business eligible for a trial?
  #
  # Returns Boolean
  def eligible_for_trial?
    return true if default_managed?

    # EMU accounts cannot be converted to a trial. Check if they were created as a trial.
    trial_expires_at.present? || trial_completed_at.present?
  end

  # Public: Returns whether the business is a trial account
  #
  # Returns a Boolean
  sig {  returns(T::Boolean) }
  def trial?
    trial_expires_at.present?
  end

  def cancel_trial_flavor
    trial_expired? ? "Delete" : "Cancel"
  end

  def cancelling_trial_flavor
    trial_expired? ? "deleting" : "cancelling"
  end

  def metered_ghec_trial?
    metered_ghe? && trial?
  end

  def metered_ghes_eligible?
    metered_ghe? && !metered_ghec_trial?
  end

  # Public: Returns whether the business is eligible to allow its organizations to have a Copilot Business trial.
  #
  # Returns a Boolean
  def eligible_to_trial_copilot_business?
    return false unless self.feature_enabled?(:digital_front_door_mvp)
    return false unless trial?
    self.has_valid_payment_method? && self.billing_transactions.authorized.any?
  end

  # Public: Returns whether the business is currently trialing Copilot Business.
  # This is the case if any of its organizations have an ongoing Copilot Business trial.
  #
  # Returns a Boolean
  def has_ongoing_copilot_business_trial?
    Copilot::Business.new(self).ongoing_organization_trials.any?
  end

  # Public: Has the trial been extended beyond the default period?
  #
  # Generally trial_expires_at will be initially set as
  # GitHub::Billing.today + Billing::EnterpriseCloudTrial.trial_length
  # So we consider that a trial has been extended beyond the original
  # trial period when:
  #
  # trial_expires_at > (created_at + Billing::EnterpriseCloudTrial.trial_length + 1.day)
  #
  # Returns Boolean
  def extended_trial?
    return false unless trial?

    T.must(trial_expires_at) > (T.must(created_at) + Billing::EnterpriseCloudTrial.trial_length + 1.day)
  end

  # Public: Returns whether a business trial account is past its expiry
  # date
  #
  # Returns a Boolean
  def trial_expired?
    trial? && T.must(trial_expires_at) <= Time.current
  end

  # Public: Returns whether the trial_expires_at field can be updated manually
  # through Stafftools for a given business account. Only allows accounts that
  # meet the following criteria:
  #
  # 1) The account is default managed
  # 2) The account is on self-serve payments
  # 3) The account is on trial
  # 4) The trial for the account is active
  #
  # Returns a Boolean
  def can_update_trial_expires_at_manually?
    return false unless eligible_for_trial?
    return false unless self_serve_payment?
    return false unless trial?
    no_trial_or_active_trial?
  end

  def instrument_create_trial(
    actor = nil,
    upgraded_organization = nil,
    billing_full_name: nil,
    marketing_consent: nil,
    industry: nil,
    employees_size: nil
  )
    return false unless trial?
    GlobalInstrumenter.instrument("enterprise_account.trial", {
      enterprise: self,
      actor: actor,
      user_initiated: :USER,
      status: :CREATED,
      expiration_timestamp: trial_expires_at,
      upgraded_organization: upgraded_organization,
      metered: metered_plan?,
      emu: enterprise_managed_user_enabled?
    })
    GlobalInstrumenter.instrument("enterprise_account.salesforce_trial_update", {
      enterprise: self,
      actor: actor,
      user_initiated: :USER,
      status: :CREATED,
      expiration_timestamp: trial_expires_at,
      upgraded_organization: upgraded_organization,
      metered: metered_plan?,
      emu: enterprise_managed_user_enabled?,
      billing_full_name: billing_full_name,
      marketing_consent: marketing_consent,
      industry: industry,
      employees_size: employees_size
    })
    instrument :create_trial
    GitHub.dogstats.increment("business.trial.create")
  end

  def initiate_trial_conversion
    return unless trial?

    transaction do
      trial_conversion_initiated!
      touch :trial_conversion_initiated_at
      update(trial_deleted_at: nil)
    end
  end

  def extend_trial(actor)
    return false unless trial?
    new_expires_at = if trial_expired?
      ::Billing::EnterpriseCloudTrial.trial_length.from_now
    else
      T.must(trial_expires_at) + ::Billing::EnterpriseCloudTrial.trial_length
    end

    transaction do
      update(trial_expires_at: new_expires_at)
      if update_billing_end_date_on_trial_extension?(new_expires_at)
        T.must(customer).update(billing_end_date: new_expires_at)
      end
      GlobalInstrumenter.instrument("enterprise_account.trial", {
        enterprise: self,
        actor: actor,
        user_initiated: :STAFF,
        status: :EXTENDED,
        expiration_timestamp: trial_expires_at,
        upgraded_organization: self.upgraded_from,
        metered: metered_plan?,
        emu: enterprise_managed_user_enabled?
      })
      GlobalInstrumenter.instrument("enterprise_account.salesforce_trial_update", {
        enterprise: self,
        actor: actor,
        user_initiated: :STAFF,
        status: :EXTENDED,
        expiration_timestamp: trial_expires_at,
        upgraded_organization: self.upgraded_from,
        metered: metered_plan?,
        emu: enterprise_managed_user_enabled?
      })
      instrument :extend_trial
      GitHub.dogstats.increment("business.trial.extend")
      update(trial_deleted_at: nil)
    end
    true
  end

  def convert_trial(actor = nil, staff_initiated: false, switch_billing_to_invoice: false)
    return false if !trial? && !trial_cancelled?
    actor = actor || self.actor
    transaction do
      touch :trial_completed_at
      trial_converted!
      upgrade_to_business_plus_plan if downgraded_to_free_plan?
      GlobalInstrumenter.instrument("enterprise_account.trial", {
        enterprise: self,
        actor: actor,
        user_initiated: staff_initiated ? :STAFF : :USER,
        status: :UPGRADED,
        expiration_timestamp: trial_expires_at,
        upgraded_organization: self.upgraded_from,
        metered: metered_plan?,
        emu: enterprise_managed_user_enabled?
      })
      GlobalInstrumenter.instrument("enterprise_account.salesforce_trial_update", {
        enterprise: self,
        actor: actor,
        user_initiated: staff_initiated ? :STAFF : :USER,
        status: :UPGRADED,
        expiration_timestamp: trial_expires_at,
        upgraded_organization: self.upgraded_from,
        metered: metered_plan?,
        emu: enterprise_managed_user_enabled?,
        talk_to_sales: talk_to_sales,
        payment_method: payment_method_enum
      })
      update trial_expires_at: nil
      instrument :convert_trial
      update(trial_deleted_at: nil)

      GitHub.dogstats.increment("business.trial.convert")
    end

    send_welcome_net_new_enterprise_account_email

    if switch_billing_to_invoice
      customer&.update(billing_type: Customer::BILLING_TYPE_INVOICE)
    elsif enable_autopay_on_trial_conversion?
      enable_automatic_self_serve_payment(actor, reason: :enterprise_purchase)
    end

    enable_ghec_bill_through_licensify(trial_upgrade: true)

    convert_metered_ghe(actor)

    sync_all_organization_billing_settings(
      enterprise_purchase: true,
      switch_org_billing_to_invoice: switch_billing_to_invoice
    )
    self.update_license_usage

    UpdateCustomerInLicensifyJob.perform_later(T.must(customer_id))

    true
  end

  # TODO: ecosystem-apps/issues/5723 add support for GitHub Apps transfers
  def inbound_integration_transfers
    IntegrationTransfer.none
  end

  private def convert_metered_ghe(actor = nil)
    return unless metered_ghe?

    update(seats: 0)

    if self.has_active_advanced_security_trial?
      Billing::Public::SubscriptionItem.end_free_trial_now!(
        actor: actor,
        product: ::AdvancedSecurity::Public::Subscription::ADVANCED_SECURITY_MONTHLY_PRODUCT,
        account: self,
        purchase_subscription: false,
        seats: 0,
        skip_sync: true,
      )
      T.must(self.customer).onboard_to_billing_platform(
        products: [Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Ghas.serialize],
      )
    end
  end

  def convert_trial_failed
    update(seats: Billing::EnterpriseCloudTrial::INITIAL_SEAT_COUNT) if seats > Billing::EnterpriseCloudTrial::INITIAL_SEAT_COUNT
  end

  # Public: planned migration date that will be used for pre migration purposes like sending emails and displaying welcome banner
  #
  # Returns Date
  def vnext_planned_migration_date
    T.must(customer).billing_platform_enabled_product&.planned_migration_date
  end

  def expire_trial(actor = nil)
    return false unless trial?
    Business.transaction do
      touch :trial_completed_at
      trial_expired!
      downgrade_to_free_plan
      GlobalInstrumenter.instrument("enterprise_account.trial", {
        enterprise: self,
        actor: actor,
        user_initiated: actor ? :STAFF : :AUTOMATION,
        status: :EXPIRED,
        expiration_timestamp: trial_expires_at,
        upgraded_organization: self.upgraded_from,
        metered: metered_plan?,
        emu: enterprise_managed_user_enabled?
      })
      GlobalInstrumenter.instrument("enterprise_account.salesforce_trial_update", {
        enterprise: self,
        actor: actor,
        user_initiated: actor ? :STAFF : :AUTOMATION,
        status: :EXPIRED,
        expiration_timestamp: trial_expires_at,
        upgraded_organization: self.upgraded_from,
        metered: metered_plan?,
        emu: enterprise_managed_user_enabled?
      })
      update trial_expires_at: 1.second.ago if T.must(trial_expires_at) > Time.current
      if self.eligible_for_expired_trial_deletion?
        update trial_deleted_at: 90.days.from_now
      end
      invited_organization_ids = organization_invitations.with_status(:confirmed).distinct.pluck(:invitee_id)
      invited_organization_ids.each_slice(DELETE_BATCH_SIZE) do |organization_ids|
        Organization.where(id: organization_ids).find_each do |organization|
          remove_organization(organization) if self == organization.business
        end
      end
      reload
      if upgraded_from.present? &&
        T.must(upgraded_from).business_membership.present? &&
        T.must(upgraded_from).business_membership&.business_id == id
        remove_organization(upgraded_from)
      end
      organization_invitations.where(confirmed_at: nil).destroy_all
      instrument :expire_trial
      GitHub.dogstats.increment("business.trial.expire")
      owners.each do |owner|
        BusinessMailer.trial_period_ended_for_enterprise_trial_account(owner, self).deliver_later
      end
    end
    true
  end

  def cancel_trial(actor, staff_initiated: false)
    return false unless trial?
    business_owners = owners
    trial_expired = trial_expired?

    transaction do
      touch :trial_completed_at
      trial_cancelled!
      downgrade_to_free_plan
      GlobalInstrumenter.instrument("enterprise_account.trial", {
        enterprise: self,
        actor: actor,
        user_initiated: staff_initiated ? :STAFF : :USER,
        status: :CANCELLED,
        expiration_timestamp: trial_expires_at,
        upgraded_organization: self.upgraded_from,
        metered: metered_plan?,
        emu: enterprise_managed_user_enabled?
      })
      GlobalInstrumenter.instrument("enterprise_account.salesforce_trial_update", {
        enterprise: self,
        actor: actor,
        user_initiated: staff_initiated ? :STAFF : :USER,
        status: :CANCELLED,
        expiration_timestamp: trial_expires_at,
        upgraded_organization: self.upgraded_from,
        metered: metered_plan?,
        emu: enterprise_managed_user_enabled?
      })
      update trial_expires_at: nil

      if metered_ghe?
        T.must(customer).update azure_subscription_id: nil, azure_subscription_name: nil
      end

      instrument :cancel_trial
      GitHub.dogstats.increment("business.trial.cancel")
      BusinessTrialCancellationCleanupJob.perform_later(self)
    end

    business_owners.each do |owner|
      BusinessMailer.cancel_trial_for_enterprise_trial_account(owner, self, trial_expired).deliver_later
    end

    true
  end

  def reset_trial(actor)
    return false if trial_converted?
    return false if trial_conversion_initiated?
    return false if trial? && no_trial_or_active_trial?

    transaction do
      update trial_completed_at: nil, trial_expires_at: 1.month.from_now,  trial_completion_status: 0
      upgrade_to_business_plus_plan if downgraded_to_free_plan?
      if update_billing_end_date_on_trial_extension?(trial_expires_at)
        T.must(customer).update(billing_end_date: trial_expires_at)
      end
      GlobalInstrumenter.instrument("enterprise_account.trial", {
        enterprise: self,
        actor: actor,
        user_initiated: :STAFF,
        status: :RESET,
        expiration_timestamp: trial_expires_at,
        upgraded_organization: self.upgraded_from,
        metered: metered_plan?,
        emu: enterprise_managed_user_enabled?
      })
      GlobalInstrumenter.instrument("enterprise_account.salesforce_trial_update", {
        enterprise: self,
        actor: actor,
        user_initiated: :STAFF,
        status: :RESET,
        expiration_timestamp: trial_expires_at,
        upgraded_organization: self.upgraded_from,
        metered: metered_plan?,
        emu: enterprise_managed_user_enabled?
      })
      instrument :reset_trial
      GitHub.dogstats.increment("business.trial.reset")
      update(trial_deleted_at: nil)
    end

    true
  end

  def trial_days_remaining
    return unless trial?
    unless T.must(trial_expires_at) < GitHub::Billing.today
      (T.must(trial_expires_at).to_date - GitHub::Billing.today).to_i
    end
  end

  # Public: Update the Business status to indicate that an organization upgrade is in progress.
  # This status is used to indicate that the Enterprise Account has been created as a result of
  # an organization upgrade. The created EA will not contain the upgraded organization until payment is successful.
  # This state serves to identify recently created Enterprises, before they have attempted to make a payment.
  # Only applies to non-trial accounts. This state is used for a direct purchase from an Organization to Enterprise.
  #
  # actor - User initiating the upgrade
  #
  # Returns nothing
  def initiate_organization_upgrade(actor = nil)
    actor = actor || self.actor

    return if GitHub.single_business_environment?
    return if trial?

    organization_upgrade_initiated!
    instrument_organization_upgrade_event(actor, :UPGRADE_INITIATED)
  end

  # Public: Update the Business status to indicate that a purchase has been initiated on an Enterprise Account
  # that is being upgraded from an organization.
  # The Enterprise must be in the 'organization_upgrade_initiated' state before transitioning to this one.
  # Only applies to non-trial accounts. This state is used for a direct purchase from an Organization to Enterprise.
  #
  # actor - User initiating the upgrade purchase
  #
  # Returns nothing
  def initiate_organization_upgrade_purchase(actor = nil)
    actor = actor || self.actor

    return if GitHub.single_business_environment?
    return if trial?
    return unless self.organization_upgrade_initiated?

    transaction do
      organization_upgrade_purchase_initiated!
      touch :upgrade_purchase_initiated_at
    end

    instrument_organization_upgrade_event(actor, :UPGRADE_PURCHASE_INITIATED)
    EnterpriseAccounts::KV.store.set("organization_upgrade_purchase_initiated/#{self.id}", "true", expires: 48.hours.from_now)
  end

  # Public: Update the Business status to indicate that purchase of the Enterprise Account
  # is complete
  # The Enterprise must be in the 'organization_upgrade_purchase_initiated' state before transitioning to this one.
  # Only applies to non-trial accounts. This method is used for a direct purchase from an Organization to Enterprise.
  #
  # actor - User completing the upgrade
  #
  # Returns nothing
  def upgrade_from_organization(actor = nil)
    return if GitHub.single_business_environment?
    return if trial?
    return unless self.organization_upgrade_purchase_initiated?

    actor = actor || self.actor

    org_to_attach = self.upgrade_initiated_from_organization
    initiating_owner = self.owners.first

    # Mark as completed since payment has been processed
    organization_upgrade_completed!

    if org_to_attach.present? && self == org_to_attach.upgrade_to_enterprise_in_progress
      begin
        attach_organization_for_upgrade(org_to_attach, initiating_owner) if org_to_attach.adminable_by?(initiating_owner)
      rescue ActiveRecord::RecordInvalid => e
        # Catch the potential race condition where the organization cannot be attached to the EA
        # if the organization seat count has increased while the payment has been processing.
        BusinessMailer.attach_organization_to_enterprise_failure(initiating_owner, self).deliver_later
        initiating_owner.reset_notice("org_attachment_failure")
        EnterpriseAccounts::KV.store.set(org_attachment_failure_notice_key(initiating_owner), Time.now.utc.iso8601)
      end
      # Unmark the organization as in process for upgrade
      org_to_attach.clear_upgrade_to_enterprise_in_progress!
      instrument_organization_upgrade_event(actor, :PURCHASE_UPGRADED)
    end

    instrument :upgrade_from_organization, org: org_to_attach

    enable_automatic_self_serve_payment(actor, reason: :enterprise_purchase)
    sync_all_organization_billing_settings(
      enterprise_purchase: true,
      switch_org_billing_to_invoice: false
    )

    set_org_upgrade_onboarding_notice(initiating_owner: initiating_owner, organization: org_to_attach)
    EnterpriseAccounts::KV.store.del("organization_upgrade_purchase_initiated/#{self.id}")

    true
  end

  # Public: Cancels the organization upgrade into an Enterprise Account.
  # This enqueues the BusinessUpgradeCancellationJob, and will delete the Enterprise Account.
  # The Enterprise must be in the 'organization_upgrade_initiated' state.
  # This method is used to cancel a direct purchase from an Organization to Enterprise.
  #
  # actor - User cancelling the upgrade
  #
  # Returns Boolean indicating whether the cancellation was enqueued.
  def cancel_organization_upgrade(actor = nil)
    actor = actor || self.actor

    return if GitHub.single_business_environment?
    return unless self.organization_upgrade_initiated?

    instrument_organization_upgrade_event(actor, :UPGRADE_CANCELLED)
    BusinessUpgradeCancellationJob.perform_later(self, email_owners = false)

    true
  end

  # Public: Update the Business status to indicate that it has been created in the process of redeeming a GHEC coupon
  # Only applies to non-trial accounts. This state is used for creating a new Enterprise account from a coupon.
  # The force flag is only used to return a business that is in the creation_from_coupon_purchase_initiated state
  # back to the creation_initiated_from_coupon while bypassing the feature flag check if it's been disabled.
  #
  # actor - User initiating the Enterprise creation
  #
  # Returns nothing
  def initiate_creation_from_coupon(actor = nil, coupon_code: nil, force: false)
    actor = actor || self.actor

    return if GitHub.single_business_environment?
    return if trial?
    return if !actor&.feature_enabled?(:new_ea_creation_from_coupon) && !force

    creation_initiated_from_coupon!

    instrument_ea_creation_from_coupon_redemption(actor, :CREATION_INITIATED_FROM_COUPON, coupon: coupon_code)
  end

  # Public: Update the Business status to indicate that the creation from a coupon is in the purchase state.
  # This indicates that there is a balance to pay that exceeds the coupon amount, and that we must wait for
  # a successful payment before granting full access to the Enterprise account.
  # Only applies to non-trial accounts. This state is used for creating a new Enterprise account from a coupon.
  #
  # actor - User initiating the Enterprise creation
  #
  # Returns nothing
  def initiate_creation_purchase_from_coupon(actor = nil)
    actor = actor || self.actor

    return if GitHub.single_business_environment?
    return if trial?
    return unless actor&.feature_enabled?(:new_ea_creation_from_coupon)
    return unless self.creation_initiated_from_coupon?

    transaction do
      creation_from_coupon_purchase_initiated!
      touch :upgrade_purchase_initiated_at
    end

    instrument_ea_creation_from_coupon_redemption(actor, :CREATION_FROM_COUPON_PURCHASE_INITIATED)
  end

  # Public: Update the Business status to indicate that the creation of the Enterprise account is complete.
  # The account was created by redeeming a GHEC coupon.
  # The Enterprise can either be in the 'creation_initiated_from_coupon' state or the 'creation_from_coupon_purchase_initiated'
  # state before transitioning to this one. This is because payment may or may not be required depending on the coupon amount
  # and the number of desired seats.
  # Only applies to non-trial accounts. This state is used for creating a new Enterprise account from a coupon.
  #
  # actor - User completing the Enterprise creation
  # payment_required - Boolean indicating if a payment was required to complete the creation of this account from a coupon
  #
  # Returns nothing
  def complete_creation_from_coupon(actor = nil, payment_required: false)
    actor = actor || self.actor

    return false if GitHub.single_business_environment?
    return false if trial?
    return false unless owners.first.feature_enabled?(:new_ea_creation_from_coupon)
    return false if !(self.creation_initiated_from_coupon? || self.creation_from_coupon_purchase_initiated?)

    org_to_attach = self.upgrade_initiated_from_organization
    initiating_owner = self.owners.first

    # Mark as completed since coupon has been redeemed
    created_from_coupon!

    if org_to_attach.present? && self == org_to_attach.upgrade_to_enterprise_in_progress
      attach_organization_for_upgrade(org_to_attach, initiating_owner) if org_to_attach.adminable_by?(initiating_owner)
      org_to_attach.clear_upgrade_to_enterprise_in_progress!
    end

    sync_all_organization_billing_settings(
      enterprise_purchase: true,
      switch_org_billing_to_invoice: false
    )

    instrument_ea_creation_from_coupon_redemption(actor, :CREATED_FROM_COUPON, coupon: self.coupon&.code)

    BusinessMailer.creation_from_coupon_success(initiating_owner, self).deliver_later

    true
  end

  # Public: Cancels the coupon redemption to create an Enterprise Account.
  # This enqueues the BusinessUpgradeCancellationJob, and will delete the Enterprise Account.
  # The Enterprise must be in the 'creation_initiated_from_coupon' state.
  # This method is used to cancel a creation of an Enterprise account from a coupon.
  #
  # actor - User cancelling the upgrade. Must be an owner.
  #
  # Returns Boolean indicating whether the cancellation was enqueued.
  def cancel_creation_from_coupon(actor = nil)
    actor = actor || self.actor

    return if GitHub.single_business_environment?
    return unless self.creation_initiated_from_coupon?
    return unless self.owners.include?(actor)

    instrument_ea_creation_from_coupon_redemption(actor, :REDEMPTION_CANCELLED)
    BusinessUpgradeCancellationJob.perform_later(self, email_owners = false)

    true
  end

  def org_attachment_failure_notice_key(user)
    "user.set_notice.org_attachment_failure.#{self.id}.#{user.id}"
  end

  def set_org_upgrade_onboarding_notice(initiating_owner:, organization: nil)
    return unless self.upgraded_from_organization?
    business_owners = organization.present? ? organization.admins : [initiating_owner]

    business_owners.each do |owner|
      EnterpriseAccounts::KV.store.set(self.org_upgrade_onboarding_notice_key(owner), Time.now.utc.iso8601, expires: 6.months.from_now)
    end
  end

  def org_upgrade_onboarding_notice_set?(user)
    return false unless self.upgraded_from_organization?

    EnterpriseAccounts::KV.store.get(org_upgrade_onboarding_notice_key(user)).value { true }.present?
  end

  def org_upgrade_onboarding_notice_key(user)
    "user.set_business_notice.org_upgrade_onboarding.#{self.id}.#{user.id}"
  end

  # Public: returns true if the business was created from a free/team-org to EA upgrade
  # or from a GHEC-org to EA upgrade.
  def upgraded_from_organization?
    self.organization_upgrade_completed? || self.organization_direct_upgraded?
  end

  # Public: Get the IP allow list entries for the Business matching the given query.
  #
  # query - String representing the query
  #
  # Returns ActiveRecord::Relation.
  def filtered_ip_allowlist_entries(query: nil)
    self.ip_allowlist_entries
      .for_query(query)
      .order(allow_list_value: :asc)
  end

  # Public: Get the IP allow list entries for any GitHub Apps installed on the
  # Business matching the given query.
  #
  # query - String representing the query
  #
  # Returns ActiveRecord::Relation.
  def filtered_installed_app_ip_allowlist_entries(query: nil)
    IpAllowlistEntry.installed_for(self)
      .for_query(query)
      .order(allow_list_value: :asc)
  end

  # Helper for customer.billing_end_date to return it as a Date in UTC.
  #
  # Handles a nil customer; this might come up in a single business environment
  # case, where there is no associated customer record.
  #
  # Returns a Date or nil.
  def billing_term_ends_on
    if customer&.billing_end_date
      T.must(T.must(customer).billing_end_date).utc.to_date
    else
      # N.B. we'd like to deprecate this column but until requirements around
      # billing information for the single business is clearer, we're allowing
      # this fallback.
      billing_term_ends_at&.to_date
    end
  end

  sig { returns(T::Boolean) }
  def billing_term_expired?
    return false if billing_term_ends_on.nil?
    return false if GitHub::Billing.today?(billing_term_ends_on)

    GitHub::Billing.past?(T.must(billing_term_ends_on))
  end

  def billing_term_ends_at=(value)
    date =
      if value.present?
        parsed_date(value)
      else
        nil
      end

    super(date)

    if customer
      # N.B. this should exist unless we're in a single business environment.
      # until the requirements around the single business and certain billing
      # fields is clearer, we're dual writing this to the business's
      # billing_term_ends_at column as well.
      T.must(customer).billing_end_date = date
    end
  end

  def event_prefix
    :business
  end

  def event_key
    :business
  end

  def event_context(prefix: event_prefix)
    {
      prefix => slug,
      :"#{prefix}_id" => id,
    }
  end

  def event_payload
    {
      business: self,
      name: name,
    }
  end

  # Public: The query string used to find all of this Business' audit log events.
  #
  # driftwood_ade - Boolean indicating whether to return the Driftwood Azure Data Explorer
  # version of the query.
  #
  # Returns String
  def site_admin_audit_log_query(driftwood_ade: false)
    if driftwood_ade
      "webevents | where business_id == #{id}"
    else
      "business_id:#{id}"
    end
  end

  # Public: Find audit log events for the Business matching a specific action.
  #
  # action - String representing the action.
  def find_audit_events(action)
    find_audit_events_for_actions([action])
  end

  # Public: Find audit log events for the Business matching specific actions.
  #
  # actions - Array of String representing actions.
  def find_audit_events_for_actions(actions)
    options = {
      business_id: id,
      allowlist: actions,
      raw: true,
    }
    Audit::Driftwood::Query.new_org_business_query(options).execute.results
  end

  def role_for(user)
    return Business::OWNER_ROLE if owner?(user)
    return Business::BILLING_MANAGER_ROLE if billing_manager?(user)
    return :member if member?(user)
    Business::UNAFFILIATED_ROLE if supports_unaffiliated_user_accounts? && unaffiliated_member?(user)
  end

  # Public: Allows bulk setting of the initial owners. Only allowed when
  # initially creating the business.
  #
  # Since owners are set via Abilities, actual records will be inserted
  # after create.
  #
  # owners  - An Array of Users to grant admin privileges to.
  #
  # Returns nothing.
  def owners=(owners)
    if persisted?
      raise "Bulk owner setter only available on new records. Use add_owner or remove_owner instead."
    else
      @owners = owners
    end
  end

  # Public: The users who are owners of this business.
  #
  # For new records, returns the users who will be granted admin rights once
  # the business is created.
  #
  # Returns an Array of Users.
  def owners
    return @owners if defined?(@owners)

    members(action: :admin).where("users.type = 'User'")
  end

  # Public: Does the given user have owner privileges on this Business?
  #
  # user  - The User to check.
  #
  # Returns a Boolean.
  def owner?(user)
    permit?(user, :admin)
  end

  # temporary logging to track business admin checks
  # https://github.com/github/authz-exp/issues/49
  def permit?(actor, action)
    if action == :admin && feature_enabled?(:log_business_admin_check)
      log_info = {
        "gh.business.id" => self.id,
        "gh.actor.id" => actor&.id,
        "gh.actor.type" => actor&.class&.name,
        "gh.method" => "permit?",
        "gh.caller" => caller.to_s
      }
      GitHub.logger.info("Business admin check executed", log_info)
      GitHub.dogstats.increment "business_admin_check.executed", tags: ["method:permit?"]
    end
    super
  end

  # temporary logging to track business admin checks
  # https://github.com/github/authz-exp/issues/49
  def async_permit?(actor, action)
    if action == :admin && feature_enabled?(:log_business_admin_check)
      log_info = {
        "gh.business.id" => self.id,
        "gh.actor.id" => actor&.id,
        "gh.actor.type" => actor&.class.name,
        "gh.method" => "async_permit?",
        "gh.caller" => caller.to_s
      }
      GitHub.logger.info("Business admin check executed", log_info)
      GitHub.dogstats.increment "business_admin_check.executed", tags: ["method:async_permit?"]
    end
    super
  end

  # Public: Find an unaccepted admin invitation for the user/email.
  #
  # invitee - User to find an invitation for.
  # email   - optional — String email to find an invitation for.
  # role    - optional — a String specifying the role of the admin being invited
  #
  # Returns a BusinessAdministratorInvitation, or nil when not found.
  def pending_admin_invitation_for(invitee = nil, email: nil, role: nil)
    return if !invitee.present? && !email.present?
    return if invitee.present? && !invitee.is_a?(User)
    return if email.present? && !User.valid_email?(email)

    scope = T.unsafe(invitations.pending).with_invitee_or_normalized_email(invitee: invitee, emails: email)
    scope = scope.with_business_role(role) if role.present?
    scope.last
  end

  # Public: Find an unaccepted organization invitation for the organization
  #
  # invitee - Organization to find an invitation for.
  #
  # Returns a BusinessOrganizationInvitation, or nil when not found.
  def pending_organization_invitation_for(invitee = nil)
    return if !invitee.present? || !invitee.is_a?(Organization)

    organization_invitations.pending.find_by(invitee: invitee)
  end

  # Public: Invite a user or email to become an admin of this business.
  # Provided either user or email, not both. An invitation can only be made to
  # either a user or an email address.
  #
  # user    - A User to invite to become a business admin
  # email   - A String email address to invite to become a business admin.
  # inviter - User sending the invitation.
  # role    - String role of the admin being invited
  # stafftools_invite - flag that signifies the invitation is coming from stafftools
  #                     (relaxes the validations by allowing a business owner or a
  #                     site admin to issue an invitation)
  #
  # Returns a BusinessAdministratorInvitation.
  def invite_admin(user: nil, email: nil, role:, inviter:, stafftools_invite: false)
    if !stafftools_invite && enterprise_managed_user_enabled?
      raise InvalidAdminStateError, "Administrators cannot be invited into an IdP managed enterprise."
    end

    pending_admin_invitation_for(user, email: email, role: role) ||
      invitations.create!(invitee: user, email: email, inviter: inviter,
                          role: role, stafftools_invite: stafftools_invite)
  end

  # Public: Invite a user or email to become an unaffiliated member of this business.
  # Provided either user or email, not both. An invitation can only be made to
  # either a user or an email address.
  #
  # Since Member invitations and Admin invitations share a model this calls
  # Business#invite_admin internally
  #
  # user    - A User to invite to become a business member
  # email   - A String email address to invite to become a business member.
  # inviter - User sending the invitation.
  # stafftools_invite - flag that signifies the invitation is coming from stafftools
  #                     (relaxes the validations by allowing a business owner or a
  #                     site admin to issue an invitation)
  #
  # Returns a BusinessAdministratorInvitation.
  def invite_unaffiliated_member(user: nil, email: nil, inviter:, stafftools_invite: false)
    if !stafftools_invite && enterprise_managed_user_enabled?
      raise InvalidAdminStateError, "Members cannot be invited into an IdP managed enterprise."
    end

    invite_admin(user: user, email: email, inviter: inviter, role: :unaffiliated, stafftools_invite: stafftools_invite)
  end

  # Public: Is the given user in a valid state to become an administrator of the
  # enterprise account?
  #
  # This is a general validation that is performed when attempting to add owners
  # and billing managers. There are additional validations performed for enterprise
  # accounts with more specific requirements, such as the two-factor requirement.
  #
  # user - The User being added as an enterprise account administrator.
  #
  # Returns Boolean
  def valid_administrator_state?(user)
    !user.suspended? && !user.deceased?
  end

  # Public: Grants a user admin privilege on this business.
  #
  # user  - The User to grant privilege to.
  # actor - The User granting the privilege.
  # send_email_notification - Boolean indicating whether the admin is notified
  #   by email. Currently only passed as true when staff directly add admins and
  #   the invitation flow is bypassed.
  # staff_action - true if the original add or invite originated from stafftools so hide staff user information.
  #   There is a catchall if actions come directly from a stafftools endpoint, but if data is persisted or scheduled
  #   for later work we might accidentally expose support logins.
  #
  # Returns nothing.
  def add_owner(user, actor:, send_email_notification: false, staff_action: false)
    raise ArgumentError, "admin must be a User" unless user.try(:user?)
    if two_factor_requirement_enabled? && !user.two_factor_authentication_enabled?
      raise UserHasTwoFactorDisabledError, "User must have two-factor authentication enabled"
    end
    if !external_identity_session_owner.external_sso_requirement_met_by?(user)
      raise UserHasNoExternalIdentityError, "User must have a linked external identity provisioned by the identity provider"
    end
    return true if owner?(user)

    unless valid_administrator_state?(user)
      raise InvalidAdminStateError, "User cannot be added as an owner"
    end

    grant user, :admin
    add_user_accounts([user.id]) unless GitHub.single_business_environment?
    update_license_usage

    payload = { user: user }
    if staff_action
      payload.update(GitHub.guarded_audit_log_staff_actor_entry(actor))
    else
      payload.update(actor: actor)
    end
    instrument :add_admin, payload

    sync_global_business_owner_and_site_admin(user, true)
    if send_email_notification
      send_admin_added_email_notification(role: :owner, admin: user)
    end

    # Only send the welcome email if the user is the only owner of the business and it's not a trial account.
    send_welcome_net_new_enterprise_account_email if self.owner_ids == [user.id] && !self.trial?

    BusinessMailer.premium_support_notice(self).deliver_later if send_initial_premium_support_mailer?(admin: user)
  end

  # Public: Revokes a user's admin privilege on this business.
  #
  # user    - The User to revoke the privilege from.
  # actor   - The User revoking the privilege.
  # reason  - (Optional) A String stating why the privilege was revoked.
  # send_notification - Whether or not the user should be sent a notification
  #                     about being removed from the business.
  # allow_removal_of_last_owner - Whether the last owner can be
  #                               removed, only used for cancelling
  #                               trials
  #
  # Returns nothing.
  def remove_owner(user, actor:, reason: nil, send_notification: true, allow_removal_of_last_owner: false, new_role: nil)
    return unless owner?(user)
    block_removal_of_last_owner user unless allow_removal_of_last_owner
    block_removal_of_first_emu_owner user
    cancel_all_invitations_involving(user)
    revoke user

    # do not remove business user account if the user is enterprise managed
    remove_user_from_business(user) unless user.is_enterprise_managed?
    update_license_usage

    instrument :remove_admin, user: user, actor: actor, reason: reason
    GlobalInstrumenter.instrument("enterprise_account.remove_admin", {
      enterprise: self,
      actor: actor,
      user: user,
      role: :owner,
      reason: reason,
      new_role: new_role,
    })
    sync_global_business_owner_and_site_admin(user, false)

    send_admin_removed_email_notification(role: :owner, admin: user, reason: reason&.to_s) if send_notification
  end

  # Public: Cancel all invitations involving the given user, including:
  # - Any pending administrator invitations from and to the user
  # - Any pending organization invitations from the user
  #
  # user - The User for whom all invitations should be cancelled.
  #
  # Returns nothing.
  def cancel_all_invitations_involving(user)
    # Invitations don't exist in single enterprise account env (GHES)
    return if GitHub.bypass_business_member_invites_enabled?

    cancel_admin_invitations_involving(user)
    cancel_organization_invitations_from(user)
  end

  # Internal: Cancel all pending administrator invitations where the
  # inviter or invitee is the given user.
  #
  # user - The User who is the inviter or invitee.
  #
  # Returns nothing.
  def cancel_admin_invitations_involving(user)
    invitations.pending.where(
      "inviter_id = ? OR invitee_id = ?", user.id, user.id
    ).each do |invitation|
      invitation.cancel actor: user
    end
  end

  # Internal: Cancel all pending organization invitations where the
  # inviter is the given user.
  #
  # user - The User who is the inviter for whom invitations should be cancelled.
  #
  # Returns nothing.
  def cancel_organization_invitations_from(user)
    organization_invitations.pending.where(inviter_id: user.id).each do |invitation|
      invitation.cancel user
    end
  end

  # Public: Is the "Remove from enterprise" functionality available?
  #
  # Returns Boolean.
  def user_removal_available?
    !GitHub.single_business_environment? &&
    !enterprise_managed_user_enabled? &&
    !downgraded_to_free_plan?
  end

  # Public: Removes a user from this Enterprise
  #
  # user    - The User to remove
  # actor   - The User removing the User
  # reason  - (Optional) A String indicating why the user was removed
  # send_notification - Whether or not the user should be sent a notification
  #                     about being removed from the Enterprise.
  # force  - (Optional) A Boolean to skip permission checks and force remove
  #
  # Returns nothing.
  def remove_member(user, actor:, reason: nil, send_notification: true, force: false)
    if GitHub.single_business_environment?
      raise ForbiddenRemovalError.new("Users cannot be removed from the global enterprise in this environment")
    end

    unless owner?(actor) || force
      raise ForbiddenRemovalError.new("#{actor} does not have permission to remove a user from this enterprise")
    end

    # direct/indirect member of the enterprise, outside collaborator, or an org billing manager on any org
    unless user_connected_to_enterprise?(user) || force
      raise InvalidRemovalError.new("User #{user.display_login} doesn't belong to #{name}")
    end

    if owners == [user]
      raise Business::NoAdminsError.new(
        "User #{user.display_login} is the last admin in the #{name} enterprise",
      )
    end

    if solitarily_owned_member_organizations(user).any?
      orgs_part = solitarily_owned_member_organizations(user).map(&:display_login).join(", ")
      raise Organization::NoAdminsError.new \
        "User #{user.display_login} is the last admin in these organizations: #{orgs_part}"
    end

    roles_lost = Set.new
    organizations_removed_from = Set.new

    # NOTE: This is not used in production currently. It is here to support Enterprise Security Manager development,
    # which includes GHES or Proxima staffship
    bulk_remove_members = self.feature_enabled?(:business_bulk_members_actions) ||
      EnterpriseTeam.enabled_for_organizations?(business: user.business)
    if bulk_remove_members
      ability_ids, org_ids = Ability.where(
        actor_type: "User",
        actor_id: user.id,
        subject_type: "Organization",
        subject_id: organization_ids
      ).pluck(:id, :subject_id).transpose
      remove_abilities_from_business(ability_ids, actor: actor)
      organizations_removed_from = Organization.where(id: org_ids).to_set
    end

    organizations.each do |organization|
      # remove direct or pending member organization members
      if (organization.member?(user) && !bulk_remove_members) || organization.pending_members.include?(user)
        roles_lost.add :member
        organizations_removed_from.add organization
        with_write { organization.remove_member(user, send_notification: false, background_team_remove_member: true) }
      end
      # remove access to repos they're outside collaborators on
      if organization.user_is_outside_collaborator?(user.id)
        roles_lost.add :outside_collaborator
        organizations_removed_from.add organization
        with_write { organization.remove_outside_collaborator!(user, send_notification: false) }
      end
      # remove pending outside collaborator invitations
      if organization.repository_invitations.where(invitee: user).exists?
        roles_lost.add :outside_collaborator
        repository_ids = organization.repositories.pluck(:id)
        with_write { RepositoryInvitation.cancel_all_invitations_involving(user: user, repo_ids: repository_ids) }
      end
      # remove organization billing managers
      if organization.billing.manager?(user)
        roles_lost.add :billing_manager
        with_write { organization.billing.remove_manager(user, actor: actor) }
      end
    end

    # Remove direct enterprise membership a.k.a. owners/billing managers
    is_owner = owner?(user)
    pending_owner_invitation = pending_admin_invitation_for(user, role: "owner")
    if is_owner || pending_owner_invitation
      roles_lost.add(:owner)
      with_write do
        if is_owner
          remove_owner(user, actor: actor, send_notification: false)
        elsif pending_owner_invitation
          pending_owner_invitation.cancel(actor: user)
        end
      end
    end

    is_billing_manager = billing_manager?(user)
    pending_billing_manager_invitation = pending_admin_invitation_for(user, role: "billing_manager")
    if is_billing_manager || pending_billing_manager_invitation
      roles_lost.add(:billing_manager)
      with_write do
        if is_billing_manager
          billing.remove_manager(user, actor: actor, send_notification: false)
        elsif pending_billing_manager_invitation
          pending_billing_manager_invitation.cancel(actor: user)
        end
      end
    end

    send_member_removed_email_notification(user, roles_lost.to_a, organizations_removed_from.to_a) if send_notification
    with_write { remove_user_from_business(user, force: true) }
    instrument_remove_member(user: user, actor: actor, reason: reason)
  end

  # Public: Removes users from select organizations. This takes in ability ids to remove, and performs the
  # cleanup in bulk. It only works for removing org memberships, it does not remove outside collaborator records.
  #
  # This is designed to be used by records that keep track of ability IDs, ie OrganizationMembershipEntries.
  # Returns nothing
  def remove_abilities_from_business(ability_ids, actor:)
    # Validate that the abilities are all for this business
    business_all_user_ids = self.user_accounts.pluck(:user_id)

    # Assume the caller knows the abilities they are removing are for this business, but verify.
    # To avoid large IN queries, we'll filter the abilities to only those that are for this business in memory,
    # instead of in the query.
    ability_records = Ability.where(
      id: ability_ids,
      actor_type: "User",
      subject_type: "Organization"
    ).select(:id, :actor_id, :subject_id, :subject_type)

    unless GitHub.single_business_environment?
      ability_records = ability_records.reject do |ability|
        !organization_ids.include?(ability.subject_id) ||
        !business_all_user_ids.include?(ability.actor_id)
      end
    end

    Ability.delete_all_abilities(ability_records)

    # There could be 10,000 users to remove from 1 org, or 1 user to remove from 10,000 orgs.
    # Create a user -> org map and an org -> user map to compare which is smaller.
    org_with_users_removed = ability_records.group_by(&:subject_id).transform_values do |records|
      records.map(&:actor_id)
    end
    user_with_orgs_removed = ability_records.group_by(&:actor_id).transform_values do |records|
      records.map(&:subject_id)
    end

    org_ids_removed = org_with_users_removed.keys
    user_ids_removed = user_with_orgs_removed.keys

    # Bulk remove programmatic access.
    # First - get all programmatic access for the users and orgs removed. This might grab too many records,
    # for example if a user is not removed from one of the selected orgs.
    programmatic_access = UserProgrammaticAccess
      .where(owner: user_ids_removed)
      .joins(:organization_programmatic_access_grants)
      .where(organization_programmatic_access_grants: { target: org_ids_removed })

    # Now filter that down to only the programmatic access that should be removed by checking with the
    # ability records being removed.

    programmatic_access.each do |access|
      org_grant_ids_to_remove = []

      access.organization_programmatic_access_grants.each do |org_grant|
        grant_org_id = org_grant.organization_id
        access_user_id = access.user_id
        if org_ids_removed.include?(grant_org_id) && T.must(org_with_users_removed[grant_org_id]).include?(access_user_id)
          org_grant_ids_to_remove << org_grant.id
        end
      end

      org_grant_ids_to_remove.each_slice(100) do |ids|
        access.organization_programmatic_access_grants.where(id: ids).destroy_all
      end
    end

    OrganizationBulkRemoveMembersCleanupJob.perform_later(
      organization_ids: org_ids_removed,
      user_ids: user_ids_removed,
      remove_direct_repo_access: false,
      remove_team_membership: false, # ET sync already removes team membership
      actor: actor,
    )

    unless GitHub.single_business_environment?
      BusinessMembershipCleanupJob.perform_later(self, user_ids: user_ids_removed) unless enterprise_managed_user_enabled?
      update_license_usage
      Licensing::SnapshotLicensesJob.perform_later(self)
    end
  end

  # Public: Changes the administrator's role on this business
  #
  # admin_user    - The admin whose role is changing.
  # new_role      - The new role for the admin (:owner or :billing_manager).
  # actor         - The User making the change.
  # send_notification - Whether or not the user should be sent a notification
  #                     about their role changing.
  #
  # Returns nothing.
  def change_admin_role(admin_user, new_role:, actor:, send_notification: true)
    new_role = new_role&.to_sym

    if GitHub.single_business_environment? && OWNER_ROLE != new_role
      raise ArgumentError, "new role must be owner"
    elsif !ADMIN_ROLES.include?(new_role)
      raise ArgumentError, "new role must be owner or billing_manager"
    end

    # Remove user from old role; do nothing if new_role is the same as their current role
    if owner?(admin_user)
      return if new_role == OWNER_ROLE
      remove_owner(admin_user, actor: actor, send_notification: false, new_role: new_role)
    elsif billing_manager?(admin_user)
      return if new_role == BILLING_MANAGER_ROLE
      billing.remove_manager(admin_user, actor: actor, send_notification: false, new_role: new_role)
    else
      raise UserNotAnAdminError, "User must already be an Enterprise administrator"
    end

    # Add user to new role
    case new_role
    when :owner
      add_owner(admin_user, actor: actor, send_email_notification: false)
    when :billing_manager
      billing.add_manager(admin_user, actor: actor, send_notification: false)
    end

    send_admin_role_changed_notification(new_role: new_role, admin: admin_user) if send_notification
  end

  # Create BusinessUserAccounts in this Business for the given list of Users,
  # who do not already have a BusinessUserAccount.
  # If we find a BusinessUserAccount corresponding to any of the given users'
  # [verified] email addresses, update that account to be associated with
  # the User record
  #
  # user_ids - Array of Integer representing the IDs of the Users who are
  # joining the Business.
  # business_roles_bitfield - Value to use for business_roles_bitfield, defaults
  # to nil.
  def add_user_accounts(user_ids, business_roles_bitfield: nil)
    GitHub.tracer.in_span("Business#add_user_accounts", kind: :internal) do
      # remove user_ids of any Users who already have a BusinessUserAccount in this Business
      # that's associated with a User
      user_ids = user_ids.uniq - user_accounts.where(user_id: user_ids).pluck(:user_id)

      # Get verified email addresses for all the passed in Users and find any
      # BusinessUserAccount's that are associated with any of those emails in this
      # Business via an EnterpriseServerUserAccount only (i.e. a server-only member)
      user_emails_hash = UserEmail.verified.where(user_id: user_ids).pluck(:email, :user_id).to_h

      # Get email addresses from any linked external identities as well
      # Since we also match GHES users to GitHub Accounts based on exteral identity supplied emails
      ExternalIdentity.where(user_id: user_ids, provider: all_external_identity_providers).with_attributes.each do |ext_ident|
        ext_ident.emails.each do |email|
          # If we already have the email from verified emails, don't overwrite the user_id for it
          unless user_emails_hash.has_key?(email)
            user_emails_hash[email] = ext_ident.user_id
          end
        end
      end

      accounts_hash = enterprise_users_from_emails(user_emails_hash.keys)

      # For any server-only BusinessUserAccount's that we found, associate them with the User
      # instead of creating a new BusinessUserAccount
      accounts_hash.each do |email, business_user_account|
        business_user_account.update(user_id: user_emails_hash[email]) if business_user_account.present?
        user_ids.delete(user_emails_hash[email])
      end

      users = User.where(id: user_ids).map { |u| [u.id, u] }.to_h
      user_account_ids = user_ids.map do |user_id|
        next if users[user_id].nil?
        user_accounts.create(user: users[user_id], business_roles_bitfield: business_roles_bitfield).id
      end.flatten
      BusinessUserAccountUpdateAttributesJob.enqueue(self, user_account_ids: user_account_ids)
    end
  end

  def add_users_to_organizations(user_ids, organization_ids, action: :read, actor:, caller_type: nil, team_ids: [], synchronous_orchestration: false)
    # Verify that only enterprise members can be added to enterprise orgs.
    # If there are no members or organizations, return early.
    return {} if user_ids.empty? || organization_ids.empty?
    unless GitHub.single_business_environment?
      user_ids = user_accounts.where(user_id: user_ids).pluck(:user_id)
      return {} if user_ids.empty?
    end
    organizations = self.organizations.where(id: organization_ids).to_a

    if use_organization_orchestrator?
      users = User.where(id: user_ids).to_a
      teams = Team.where(id: team_ids).to_a
      return OrganizationOrchestration.add_users(actor: actor, action: action.to_s, business_id: id, organizations: organizations, teams: teams, users: users, caller_type: caller_type).execute(synchronous: synchronous_orchestration)
    end

    organization_ids = organizations.pluck(:id)
    return {} if organization_ids.empty?

    needed_memberships = Organization.add_users_to_organizations(user_ids: user_ids, organization_ids: organization_ids, action:, business: self, actor:, caller_type:, team_ids:)
    new_memberships = []
    needed_memberships.each do |uid, org_ids|
      org_ids.each { |oid| new_memberships.push([uid, oid]) }
    end

    OrganizationBulkAddMembersJob.perform_later(business: self, memberships: new_memberships, action: action, actor: actor, caller_type: caller_type) if new_memberships.any?
    needed_memberships
  end

  # Public: Enqueue BusinessUserAccountCreateForOrganizationJob to create BusinessUserAccount records for the
  # members of the given organization.
  #
  # organization - The Organization.
  #
  # Returns nothing.
  def add_user_accounts_for_organization_members(organization)
    BusinessUserAccountCreateForOrganizationJob.perform_later(self, organization)
  end

  # Public - find the BusinessUserAccount for the given user in this Business
  #
  # user  -   User whose account we're looking up
  #
  # Returns: a BusinessUserAccount if one exists, nil otherwise
  def business_user_account_for(user)
    return nil unless user.present?
    user_accounts.find_by(user_id: user.id)
  end

  # Public - Should this business create business user accounts for collaborators?
  #
  # Returns Boolean
  def add_collaborator_user_accounts?
    !GitHub.single_business_environment?
  end

  # Public - Should this business store roles and license information on the business user account?
  #
  # Returns Boolean
  def include_attributes_on_user_account?
    return false if GitHub.single_business_environment?

    true
  end

  # Public - Does this business support unaffiliated members?
  #
  # Returns Boolean
  def supports_unaffiliated_user_accounts?
    return false if GitHub.single_business_environment?

    return true if enterprise_managed_user_enabled?
    return true if seats_plan_basic?
    return true if self.feature_enabled?(:enterprise_teams_migrate_from_cfb)
    return true if self.feature_enabled?(:copilot_metered_enterprise) && metered_ghe?
    self.feature_enabled?(:unaffiliated_user_accounts)
  end

  # Public - Does this business support invitations for unaffiliated members?
  #
  # Returns Boolean
  def can_invite_unaffiliated_user_accounts?
    return false unless supports_unaffiliated_user_accounts?
    return false if enterprise_managed_user_enabled?
    true
  end

  # Check whether the copilot licensing is enabled at enterprise level for enterprise team group mappings.
  # Not to be confused with the copilot licensing enabled at organization level.
  #
  # Returns Boolean.
  def copilot_licensing_enabled?
    return false if GitHub.single_business_environment?
    return false unless supports_unaffiliated_user_accounts?
    return true if self.feature_enabled?(:copilot_metered_enterprise) && metered_ghe?
    seats_plan_basic?
  end

  ##
  # Summary: Check whether the enterprise teams are enabled for this business.
  #
  # Returns Boolean.
  def enterprise_teams_enabled?
    copilot_licensing_enabled? || EnterpriseTeam.enabled_for_organizations?(business: self)
  end

  # Public: Add an organization to this business.
  #
  # organization - The Organization to add.
  #
  # Returns the Business::OrganizationMembership whether valid or not.
  def add_organization(organization, organization_upgrade: false, new_organization: false, actor: nil)
    raise ArgumentError, "organization must be an Organization" unless organization.try(:organization?)
    previous_plan = organization.plan.name

    membership = upsert_organization_membership(organization, organization_upgrade)

    # configure tenant for organization
    if team_sync_enabled? && membership.valid?
      UpdateTeamSyncForBusinessOrganizationJob.perform_later(org_id: organization.id)
    end

    GlobalInstrumenter.instrument("enterprise_account.organization_add", {
      enterprise_id: id,
      organization_id: organization.id,
      actor_id: actor&.id,
      new_organization: new_organization,
      previous_plan: previous_plan
    })

    RestoreSoftDeletedPagesJob.perform_later(organization) unless GitHub.single_or_multi_tenant_enterprise?

    if self.feature_enabled?(:collaborator_cache_write) || organization.feature_enabled?(:collaborator_cache_write)
      OrganizationCollaborator.where(organization_id: organization.id).update_all(business_id: id)
      OrganizationCollaboratorBackfillJob.perform_later(org: organization)
    end

    DeleteConflictCustomPropertyDefinitionsJob.perform_later(org: organization, business: self) if CustomProperties::Public.enterprise_properties_enabled?(self)

    membership
  end

  # Public: Can the specified actor transfer organizations out of this business?
  #
  # actor - User representing the actor.
  #
  # Returns Boolean.
  def actor_can_transfer_organizations?(actor:)
    return false if GitHub.single_business_environment?
    return false if enterprise_managed_user_enabled?
    return false if spammy?
    return false if trial?

    actor.present? && owner?(actor)
  end

  # Public: Can the specified User remove Organizations from the Business?
  #
  # actor - The User that is the actor to check.
  #
  # Returns Boolean.
  def actor_can_remove_organizations?(actor:)
    !GitHub.single_business_environment? && !enterprise_managed_user_enabled? && actor.present? && owner?(actor)
  end

  class OrganizationIsNotMemberError < StandardError; end
  class OrganizationHasNoAdminsError < StandardError; end
  class CannotRemoveOrganizationError < StandardError; end

  # Public: Check if the removal of a given organization is restricted depending on whether the organization was
  # transferred to the trial business, or if it was created in the trial business. Only organizations transferred to
  # the trial business are eligible for removal. However, an organization created in the trial business can be removed
  # if the cap_enterprise_in_trial_org_creation feature flag is enabled.
  #
  # organization - The Organization to check
  # actor - The actor checking if they can remove the organization
  #
  # Returns a Boolean.
  def organization_removal_restricted_due_to_trial?(organization, actor)
    return false if actor.site_admin?
    return false unless trial?
    return false if GitHub.flipper[:cap_enterprise_in_trial_org_creation].enabled?
    return false if upgraded_from_id == organization.id
    organization_invitations.with_status(:confirmed).find_by(invitee_id: organization.id).blank?
  end

  # Public: Remove an Organization from this Business.
  #
  # organization - The Organization to remove.
  # is_transfer  - Boolean value to signify if removal was triggered by a transfer
  # actor        - User performing the action.
  #
  # Returns nothing, raises Business::OrganizationIsNotMemberError,
  # OrganizationHasNoAdminsError.
  def remove_organization(organization, is_transfer: false, actor: nil)
    actor ||= organization
    remove_one_organization(organization, is_transfer, actor)
  end

  # Public: Transfer an organization from this business to another business.
  #
  # organization    - The Organization to transfer
  # target_business - The Business to transfer the organization to
  # actor           - User performing the action.
  #
  # Returns the Business::OrganizationMembership whether valid or not.
  def transfer_organization(organization, target_business, actor: nil)
    repo_ids = organization.repositories.pluck(:id)

    transaction do
      remove_organization(organization, is_transfer: true, actor: actor)
      organization.copy_personal_access_token_expiration_limits(self, actor: actor) if organization.feature_enabled?(:personal_access_token_org_expiration_ui)
      InternalRepository.where(repository_id: repo_ids).update_all(business_id: target_business.id)
      target_business.add_organization(organization)
    end
  end

  # Public: Attach an organization to this business that will be treated as the "upgraded" organization.
  # This is used for organizations that upgrade their plan, and purchase an Enterprise Account (or trial)
  #
  # organization    - The Organization to upgrade
  # actor           - User performing the action.
  # settings_to_transfer - Array of Hash representing additional settings to transfer.
  #
  # Returns nothing.
  def attach_organization_for_upgrade(organization, actor, settings_to_transfer: [])
    Business.transaction do
      self.upgraded_at = Time.current
      self.upgraded_from = organization
      self.upgraded_from_plan = organization.plan.name

      ghec_org_to_ea_transfer = organization.plan.business_plus?
      transfer_billing_from_organization(organization, actor) if ghec_org_to_ea_transfer
      transfer_settings_from_organization(organization, actor)

      organization.billing_email = billing_email
      organization.save

      self.save!

      new_membership = self.add_organization(organization, organization_upgrade: true, actor: actor)
      new_membership.save!

      # We have to expire the coupon after the business membership is created to send the correct email.
      # Don't send an email for this if it's a GHEC org to EA upgrade
      # since the coupon will be transferred to the EA
      organization.expire_active_coupon(quiet: ghec_org_to_ea_transfer)
      Billing::EnterpriseCloudTrialCheckJob.perform_later(organization.id)
    end

    BusinessCreatedFromOrganizationJob.perform_later \
      self,
      organization,
      actor,
      settings_to_transfer
  end

  # Public: Cache that will update business method IDs when the values are retreived
  def write_through_cache
    @write_through_cache ||= Business::WriteThroughCache.new(self)
  end

  # Private: Encapsulates logic for removing an Organization from this Business.
  #
  # organization - The Organization to remove.
  # is_transfer  - Boolean value to signify if removal was triggered by a transfer
  # actor        - User performing the action.
  #
  # Returns nothing, raises Business::OrganizationIsNotMemberError,
  # OrganizationHasNoAdminsError, CannotRemoveOrganizationError
  private def remove_one_organization(organization, is_transfer, actor)
    if enterprise_managed_user_enabled?
      raise CannotRemoveOrganizationError.new("Organization #{organization} cannot be removed from an externally managed enterprise.")
    end

    if organization_removal_restricted_due_to_trial?(organization, actor)
      raise CannotRemoveOrganizationError.new(
        "#{organization} cannot be removed during the trial period since it was created in this enterprise account."
      )
    end

    if organization.admins.empty?
      raise OrganizationHasNoAdminsError.new("#{organization} has no owners")
    end

    if organization.integration_installations.any?
      organization.integration_installations.includes(:integration).each do |installation|
        if installation.integration.internal_visibility?
          installation.uninstall
        end
      end
    end

    valid_transfer_environment = is_transfer || GitHub.single_business_environment?

    memberships_scope = organization_memberships
    if GitHub.single_business_environment?
      memberships_scope = memberships_scope.excluding_github_enterprise_org
    end
    membership = memberships_scope.find_by(organization_id: organization&.id)

    if !membership
      raise OrganizationIsNotMemberError.new("#{organization} is not a member organization")
    end

    membership.actor = actor
    membership.destroy
    organizations.reload

    # Disable GHAS on all the repositories when we remove org from business
    SecurityAnalysisSettingsUpdateJob.perform_later(
      actor: actor,
      owner: organization,
      update_type: :advanced_security_disable_all
    )

    # Clear any organization-specific GHAS licensing. If GHAS is still required it must be explictly and manually
    # enabled as part of the support action.
    organization.mark_advanced_security_as_not_purchased_for_entity(actor: actor) if organization.advanced_security_purchased_for_entity?

    unless valid_transfer_environment
      RemoveInternalRepositoriesJob.perform_later(organization, actor: actor)
      DestroyPrivatePageJob.perform_later(organization) unless GitHub.single_or_multi_tenant_enterprise?
    end

    if team_sync_enabled? && organization.team_sync_tenant.present?
      organization.team_sync_tenant.disable
    end

    if source_ip_disclosure_enabled?
      organization.reload
      organization.disable_source_ip_disclosure(actor: actor)
    end

    if self.feature_enabled?(:collaborator_cache_write) || organization.feature_enabled?(:collaborator_cache_write)
      with_write { OrganizationCollaborator.where(organization_id: organization.id).update_all(business_id: nil) }
      OrganizationCollaboratorBackfillJob.perform_later(org: organization)
    end

    # For an organization being removed from a business to be made an independent organization where billing enabled:
    #
    # - switch to self serve billing
    # - update the organization plan to GitHub::Plan::FREE
    # - plan duration to the default
    # - User::BillingDependency::MONTHLY_PLAN
    # - change Terms of Service to our standard Terms of Service
    # - send email notifications to enterprise owners and org owners on these changes
    if GitHub.billing_enabled?
      old_billing_type = organization.billing_type

      unless old_billing_type == User::BillingDependency::CARD_BILLING_TYPE
        organization.switch_billing_type_to_card(actor)
        GitHub.instrument(
          "billing.change_billing_type",
          old_billing_type: old_billing_type,
          billing_type: organization.billing_type,
          user: organization,
          actor: actor
        )
      end

      old_plan_duration = organization.plan_duration
      if trial? || trial_expired? || trial_cancelled?
        old_plan = organization.reload.plan
        mailer_plan = old_plan.display_name
        organization.resume_billing
        organization.track_plan_change(actor, old_plan, { old_plan_duration: old_plan_duration })
      else
        mailer_plan = nil
        old_plan = organization.plan
        seats_was = organization.seats
        organization.update(plan: GitHub::Plan::FREE, plan_duration: User::BillingDependency::MONTHLY_PLAN, seats: 0)
        organization.terms_of_service.update(
          type: "Corporate",
          actor: actor,
          change_note: "Organization removed from the #{self.name} enterprise",
          removed_from_business: true
        )
        organization.track_plan_change(actor, old_plan, { old_plan_duration: old_plan_duration, filled_seats: 0, old_seat_count: seats_was })
      end

      organization.reload.disable_business_plus_features(actor: actor) unless is_transfer

      if !GitHub.single_business_environment?
        GlobalInstrumenter.instrument("enterprise_account.organization_remove", {
          enterprise_id: id,
          organization_id: organization.id,
          actor_id: actor&.id
        })
      end

      # Delete the values for the business properties that are not inherited anymore
      if CustomProperties::Public.enterprise_properties_enabled?(self)
        biz_props = CustomProperties::Public.business_definitions_manager(self).get_definitions
        DeleteCustomPropertyValuesJob.perform_later(org: organization, definitions: biz_props)
      end

      if self_serve_payment?
        cancel_member_organization_subscription_items!(organization, actor: actor)
      end

      if self.feature_enabled?(:remove_et_migration_ff_dependencies)
        if !is_transfer && organization.gh_role != "staff_delete"
          BusinessMailer.organization_removed_from_business(
            self, organization, mailer_plan
          ).deliver_later
        end
      else
        # Prefer the transfer notification email when performing a transfer.
        # TODO: The opt-out of this email with the enterprise_teams_migrate_from_cfb flag
        # is temporary and will be removed after all $0 SKU enterprises have been migrated.
        if !is_transfer && !GitHub.flipper[:enterprise_teams_migrate_from_cfb].enabled?(self)
          BusinessMailer.organization_removed_from_business(
            self, organization, mailer_plan
          ).deliver_later
        end
      end
    end
  end

  # Public: Returns the list of users that are members of the global business
  # in an Enterprise Server environment.
  #
  # This represents the active users on the installation that are consuming
  # license seats.
  #
  # Returns an ActiveRecord::Relation.
  def single_business_members
    return User.none unless GitHub.single_business_environment?

    User.users_consuming_seats
  end

  # Is the specified user a member of an organization owned by the enterprise
  # account?
  #
  # user - The User to check.
  #
  # Returns Boolean.
  def user_is_member_of_owned_org?(user)
    organization_member_ids(actor_ids: [user.id]).any?
  end

  # Is the specified user an owner of an organization owned by the enterprise
  # account?
  #
  # user - The User to check.
  #
  # Returns Boolean.
  def user_is_owner_of_owned_org?(user)
    (user.owned_organization_ids & self.organization_ids).any?
  end

  # ID's of users who are members of one or more of this business' organizations.
  #
  # action  - [optional] Symbol action (:read, :write, :admin) to limit actions
  # org_ids - [optional] Array of Integers. Only return members belonging to
  #   orgs with database IDs in the provided Array.
  # actor_ids - [optional] Array of Integers. Only return members from a given
  #   subset of Users (with database IDs in the provided Array).
  #
  # Returns an Array of User IDs (integers)
  def organization_member_ids(action: nil, org_ids: nil, actor_ids: nil)
    return [] if organizations.none?

    business_org_abilities(action: action, org_ids: org_ids, actor_ids: actor_ids).
      pluck(:actor_id)
  end

  # Users who are members of one or more of this business's organizations.
  #
  # action  - [optional] Symbol action (:read, :write, :admin) to limit actions
  # org_ids - [optional] Array of Integers. Only return members belonging to
  #   orgs with database IDs in the provided Array.
  # actor_ids - [optional] Array of Integers. Only return members from a given
  #   subset of Users (with database IDs in the provided Array).
  #
  # Returns an ActiveRecord::Relation.
  def organization_members(action: nil, org_ids: nil, actor_ids: nil)
    return User.none if organizations.none?

    user_scope = User.where(id: organization_member_ids(action: action, org_ids: org_ids, actor_ids: actor_ids))
    if enterprise_managed_user_enabled?
      emu_admin_login = User.standardize_login(shortcode, suffix: User::EnterpriseManagedDependency::ADMIN_SUFFIX)
      user_scope = user_scope.active_external_identities(emu_admin_login)
    end

    user_scope
  end

  # Public: retrieve user_id's of Business owners
  #
  # Returns: an array of user_id's
  def owner_ids
    owners.pluck(:id)
  end

  # Public: retrieves [de-duplicated] user_id's for this business' members and admins; admins
  # include Business owners and billing managers, as well as member organizations' billing managers
  #
  #   Note: the following are not included: server-only users, outside collaborators,
  #   and any users who have only been invited to the business (Business admins,
  #   Organization members, Outside collaborators)
  #
  # include_org_billing_managers - include organization billing managers (not business billing managers), default is true
  #
  # Returns: an array of (de-duplicated) user_id's
  def admin_and_organization_member_ids(actor_ids: nil, include_org_billing_managers: true)
    abilities = business_org_abilities(actor_ids: actor_ids, include_billing_managers: include_org_billing_managers).pluck(:actor_id)

    ids = Set.new(owner_ids + billing_manager_ids + abilities).to_a
    return ids & actor_ids if actor_ids
    ids
  end

  # Public: Get the Organizations within the Business where the specified
  # User has the given membership type.
  #
  # user    - Find organizations that this User belongs to.
  # type    - Optional Symbol action to limit membership type.
  #   Valid values are: :all, :admin, :member_without_admin.
  #   Defaults to :all.
  # org_ids - Optional Array of Integers. Limit search only to orgs with
  #   database IDs in the provided Array.
  #
  # Returns an ActiveRecord::Relation.
  def organizations_for_member(user, type: :all, org_ids: nil)
    return Organization.none if organizations.none?

    action = case type
    when :all
      nil
    when :admin
      :admin
    when :member_without_admin
      :read
    else
      raise ArgumentError, "Business#organizations_for_member type must be valid"
    end

    organization_ids = business_org_abilities(action: action, org_ids: org_ids, actor_ids: [user.id]).
      pluck(:subject_id)
    Organization.where(id: organization_ids)
  end

  # Public: Generate an Abilities ActiveRecord::Relation for the organizations and
  # members of this Business, using the specified criteria.
  #
  # action  - [optional] Symbol action (:read, :write, :admin) to limit actions
  # org_ids - [optional] Array of Integers. Limit search only to orgs with
  #   database IDs in the provided Array.
  # actor_ids - [optional] Array of Integers. Limit search only to users with
  #   database IDs in the provided Array.
  # include_billing_managers - Flag indicating whether or not we want the call to also return
  #   the id's of organizations' billing managers (false by default)
  #
  # Returns an ActiveRecord::Relation.
  def business_org_abilities(action: nil, org_ids: nil, actor_ids: nil, include_billing_managers: false)
    # Only find members in a subset of orgs if specified.
    subject_ids = if org_ids.present?
      org_ids & organization_ids
    elsif !GitHub.single_business_environment?
      organization_ids
    end

    subject_types = ["Organization"]
    subject_types << "Organization::BillingManagement" if include_billing_managers
    criteria = {
      "actor_type"   => "User",
      "subject_type" => subject_types,
      "priority"     => Ability.priorities[:direct],
    }

    # Skip setting subject_id as part of the criteria only when subject_ids is nil
    unless subject_ids.nil?
      criteria["subject_id"] = subject_ids
    end

    if action.present?
      raise ArgumentError, "invalid action" unless Ability.actions.include?(action)
      criteria["action"] = Ability.actions[action]
    end

    if actor_ids
      criteria["actor_id"] = actor_ids
    end

    Ability.where(criteria).distinct
  end

  # Public: get a list of logins for organizations within the business that the given
  # user belongs to
  #
  # member - member to find organizations for
  # member_ids - [Optional] list of users to user as the actor_ids parameter for the Abilities
  #              query, if caller knows the list can be scoped down to just these users
  #
  # Array[String]
  def organization_logins_for_member(member, member_ids: nil)
    @member_abilities_hash ||= business_org_abilities(actor_ids: member_ids).group_by(&:actor_id)
    return [] unless @member_abilities_hash.key?(member.id)
    org_ids = @member_abilities_hash[member.id].map(&:subject_id)
    organizations_hash(value_field: :display_login).slice(*org_ids).values
  end

  # Public: return a Hash of all the organizations that belong to this Business.
  #
  # key_field: field on Organization to use as the key for the Hash
  # value_field: field on Organization to use as the value for the Hash
  #
  # Hash of Organization fields
  def organizations_hash(key_field: :id, value_field: :login)
    return @orgs_hash if defined?(@orgs_hash)

    @orgs_hash = Hash.new { |h, k| h[k] = [] }
    organizations.each { |org| @orgs_hash[org[key_field]] = org[value_field] }
    @orgs_hash
  end

  # Returns a comprehensive list of users who could possibly authenticate via a Business' SSO IdP including:
  #
  #   * direct Business members (#members from the Ability::Membership module, currently only Business owners)
  #   * Business billing managers
  #   * Members of any Organization in the Business
  #
  # Returns ActiveRecord::Relation of Users
  def external_members
    # For an EMU all user linked to external identities should be returned
    if enterprise_managed_user_enabled?
      User.joins(:external_identities).where("external_identities.provider_id = :provider_id AND external_identities.provider_type = :provider_type", provider_id: external_provider.id, provider_type: external_provider.class.name).order(:login)
    else
      # the order here is important. with `members` first we'll get errors like:
      # - Relation passed to #or must be structurally compatible. Incompatible values: [:joins, :readonly]
      organization_members.or(owners).or(billing_managers).distinct
    end
  end
  alias :saml_members :external_members

  def public_organization_member_ids
    User.publicly_belongs_to(organization_ids).pluck(:id)
  end

  # Returns whether the user is a any kind of member of the business,
  # e.g. if a BusinessUserAccount exists
  #
  # user: user to check for business membership
  #
  # Returns Boolean
  def unaffiliated_member?(user)
    business_user_account_for(user).present?
  end

  # Returns whether the user is an unaffiliated member of the business
  #
  # user: user to check for business membership
  #
  # Returns Boolean
  def exclusive_unaffiliated_member?(user)
    user_accounts.where(user_id: user.id).exclusive_unaffiliated_role.exists?
  end

  # Returns whether the user is a member of the business, e.g.
  # is an admin or is a member of any business organization
  #
  # user: user to check for business membership
  #
  # Returns a Promise that resolves to true if user is a member of the business.
  def async_member?(user)
    return Promise.resolve(false) unless user.is_a?(User) && user.user?
    Promise.all([super, async_organizations]).then do |direct_member, _|
      direct_member || billing_manager?(user) || organization_member_ids(actor_ids: user.id).any?
    end
  end

  # This allows for API compatibility with Organization
  def async_business
    Promise.resolve(self)
  end

  def async_target_for_conditional_access
    async_business
  end

  # Public: The verified or approved domains associated with this Business.
  #
  # Returns a Promise<Array[VerifiableDomain]>.
  def async_email_eligible_domains
    Promise.resolve(VerifiableDomain.usable_for(self).verified_or_approved)
  end

  # Public: sync version of async_email_eligible_domains
  #
  # Returns: Array[VerifiableDomain]
  def email_eligible_domains
    async_email_eligible_domains.sync
  end

  # Public: get UserEmail's for a user, where the email domain is one of the verified or approved
  # domains available to the given organization. Will memoize the results as much as possible: the
  # business domains are memoized; domains for all the member orgs are retrieved in a single query
  # up front and are memoized; UserEmail results for just the business domains are cached and
  # returned automatically for any organizations that do not have any verified or approved domains
  # of their own. Results can optionally be limited to include verified or approved domains only.
  #
  # Note: Will only return verified email addresses when email verification is enabled. If
  # GitHub.email_verification_enabled? returns false (email verification disabled), the check
  # for whether a user email is verified is bypassed, and all matching emails are returned.
  #
  # organization      -   Organization whose verifiable domains we'll check
  # user              -   User to find emails for
  # include_verified  -   include verified domains
  # include_approved  -   include approved domains
  #
  # Returns: Array[UserEmail]
  def email_eligible_domain_user_emails_for(organization, user, include_verified: true, include_approved: true)
    return [] unless include_verified || include_approved
    return [] unless organization.verified_domain_restriction_should_check_user?(user)
    return [] unless organization_ids.include?(organization.id)

    # Internal cache keys for different memoization variables.
    # These keys have to take into account all the arguments in order to prevent
    # leaking values from different method calls with different arguments
    status_key = "#{include_verified}:#{include_approved}"
    owner_key = "#{organization.id}:#{status_key}"
    user_key = "#{user.id}:#{owner_key}"

    # NOTE: The __ prefix in variable names is set to prevent name clashes with the original method
    @__business_domains ||= {}
    @__business_domains[status_key] ||= VerifiableDomain
      .usable_for(self)
      .filtered_by_type(include_verified, include_approved)
      .map(&:domain)

    @__organization_domains ||= {}
    unless @__organization_domains.key?(owner_key)
      VerifiableDomain
        .where(owner_type: "User", owner_id: organization_ids)
        .filtered_by_type(include_verified, include_approved)
        .group_by(&:owner_id)
        .each do |owner_id, domains|
          @__organization_domains["#{owner_id}:#{status_key}"] = domains.map(&:domain)
        end
    end

    domains = @__business_domains[status_key] || []
    domains += @__organization_domains[owner_key] unless @__organization_domains[owner_key].nil?

    @__eligible_domain_user_emails ||= {}
    @__eligible_domain_user_emails[user_key] ||= UserEmail.email_addresses_from_domains(domains, [user.id])[user.id]
  end

  # Updates the notification restriction policies of child organizations when an enterprise
  # verified or approved domain is deleted. Does nothing if there are other verified or approved
  # enterprise domains still available. If there aren't:
  #  - if notification restriction policy was enabled for the enterprise, will enable the policy
  #    for any orgs that have at least one domain they've verified or approved themselves
  #  - if notification restriction policy was not enabled for the enterprise, will disable the
  #    policy for any orgs that had it enabled, but did not have domains they had verified or
  #    approved themselves
  #
  # verified_domain_id  - id of the enterprise VerifiableDomain that was being deleted. Since this
  #                       method is expected to run in a background job, this domain may or may not
  #                       still be present, so make the determination based on whether or not there
  #                       are any other enterprise domains
  # actor               - actor taking the action (should be a Business owner, but let's not
  #                       assume that, just in case the user was demoted from being an owner after
  #                       they had deleted a verified or approved domain, but before this job had run)
  # notifications_restricted - whether the Enterprise notification restriction setting was enabled
  #                            before this operation
  #
  # Returns: nothing
  def update_dependent_notification_restriction_policies!(verified_domain_id, actor:, notifications_restricted:)
    return if VerifiableDomain.usable_for(self).verified_or_approved.where.not(
      id: verified_domain_id
    ).any?

    organizations.includes(:verifiable_domains).each do |organization|
      domains = organization.verifiable_domains.select { |domain| domain.eligible_for_emails? }
      if domains.any?
        if notifications_restricted
          organization.enable_notification_restrictions(actor: actor, notify_members: false)
        end
      else
        organization.disable_notification_restrictions(actor: actor)
      end
    end
  end

  def outside_collaborators(
    on_repositories_with_visibility: [:public, :private],
    with_two_factor_status: nil,
    include_forks: true,
    organization_ids: nil
  )
    user_ids = outside_collaborator_ids(
                  on_repositories_with_visibility: on_repositories_with_visibility,
                  include_forks: include_forks,
                  organization_ids_filter: organization_ids
                                      )

    return User.none if user_ids.empty?

    collabs = filter_users_by_two_factor_status(User.where(id: user_ids), with_two_factor_status)

    if GitHub.single_business_environment?
      collabs = collabs.where("users.suspended_at IS NULL")
    end

    collabs.distinct.includes(:two_factor_credential)
  end

  def outside_collaborator_ids(
    on_repositories_with_visibility: [:public, :private],
    include_forks: true,
    organization_ids_filter: nil,
    skip_cache: false,
    force_cache: false
  )
    visibility = on_repositories_with_visibility.map do |visibility|
      { public: 1, private: 0 }[visibility]
    end.compact
    if (self.feature_enabled?(:collaborator_cache_read) && !skip_cache) || force_cache
      query = OrganizationCollaborator.where(business_id: id)
      query = query.where(organization_id: organization_ids_filter) unless organization_ids_filter.nil?
      query = if visibility.size == 1
        if on_repositories_with_visibility.include?(:public)
          if include_forks
            query.where(public: true).or(OrganizationCollaborator.where(public_only_forks: true))
          else
            query.where(public: true)
          end
        else
          if include_forks
            query.where(private: true).or(OrganizationCollaborator.where(private_only_forks: true))
          else
            query.where(private: true)
          end
        end
      elsif !include_forks
        query.where(private_only_forks: false, public_only_forks: false)
      else
        query
      end
      return query.pluck(:user_id).uniq
    elsif !skip_cache && self.feature_enabled?(:collaborator_cache_write) && !self.feature_enabled?(:collaborator_cache_read)
      return science "collaborator_cache_business_experiment" do |e|
        e.context({ business_id: id, on_repositories_with_visibility: on_repositories_with_visibility, include_forks: include_forks, organization_ids_filter: organization_ids_filter })
        e.compare do |control, candidate|
          control.sort == candidate.sort
        end
        e.try do
          outside_collaborator_ids(
            on_repositories_with_visibility: on_repositories_with_visibility,
            include_forks: include_forks,
            organization_ids_filter: organization_ids_filter,
            force_cache: true
          )
        end
        e.use do
          outside_collaborator_ids(
            on_repositories_with_visibility: on_repositories_with_visibility,
            include_forks: include_forks,
            organization_ids_filter: organization_ids_filter,
            skip_cache: true
          )
        end
      end
    end
    if self.feature_enabled?(:business_use_organization_outside_collaborator_ids)
      ids = organization_ids
      ids = ids & organization_ids_filter unless organization_ids_filter.nil?
      return Organization.where(id: ids).map do |org|
        next [] if !organization_ids_filter.nil? && !organization_ids_filter.include?(org.id)
        org.outside_collaborator_ids(
          on_repositories_with_visibility: on_repositories_with_visibility,
          include_forks: include_forks
        ).to_a
      end.flatten.uniq
    end

    # if both visibility options are included (public and private), then _all_
    # repos are included and repository_visibility is nil so that it isn't
    # included in the query as a filter
    repository_visibility = visibility.first if visibility.count == 1

    permission_cache_key = ["business_outside_collaborator_ids_without_join",
                            id,
                            on_repositories_with_visibility,
                            (:exclude_forks unless include_forks)]

    PermissionCache.fetch permission_cache_key do
      # Remove advisory workspaces from the list of repos.
      # Collaborators on advisory workspaces are not considered
      # outside collaborators and should not count towards seats
      workspace_repo_ids = RepositoryAdvisory
        .where(owner_id: organization_ids)
        .where.not(workspace_repository_id: nil)
        .pluck(:workspace_repository_id)

      org_ids_by_repo_id = science "private_org_business_repos" do |e|
        e.context({ org_ids_filter: organization_ids_filter, workspace_repo_ids: workspace_repo_ids })
        e.clean { |value| value.keys }
        e.compare do |control, candidate|
          control.keys.sort == candidate.keys.sort
        end
        e.try do
          filtered_org_ids = if !organization_ids_filter.nil?
            organization_ids & organization_ids_filter
          else
            organization_ids
          end

          privacy = if repository_visibility
            repository_visibility == 1 ? Repositories::RepositoryPrivacy::Public : Repositories::RepositoryPrivacy::Private
          else
            nil
          end

          repositories_domain.org_repos_and_forks_by_privacy(
            organization_ids: filtered_org_ids,
            excluded_repo_ids: workspace_repo_ids,
            privacy:,
            include_forks:
          )
        end
        e.use do
          repos_scope = Repository.active
          repos_scope = repos_scope.where(organization_id: organization_ids_filter) unless organization_ids_filter.nil?
          repos_scope = repos_scope.where(public: repository_visibility) if repository_visibility
          repos_scope = repos_scope.where(parent_id: nil) unless include_forks
          repos_scope = repos_scope.where.not(id: workspace_repo_ids)

          # An user is an outside collaborator for a business if they have a repo-level ability
          # for one of the business's organizations, but that user is not a member of that org.
          # A user can be a member of one of the business's orgs, but still be an outside collaborator
          # if they are invited to a single repo in a different org of the business.
          Hash[repos_scope.where(organization_id: organization_ids).pluck(Arel.sql("/*vt+ IGNORE_MAX_MEMORY_ROWS=1 */ id, organization_id"))]
        end
      end
      repo_ids = org_ids_by_repo_id.keys

      return [] if repo_ids.empty?

      org_members = Ability.where(
        subject_id: organization_ids,
        actor_type: "User",
        subject_type: "Organization",
        priority: Ability.priorities[:direct],
      ).pluck(:actor_id, :subject_id)

      # the keys are user IDs and the values are a set of all repo IDs the user has direct access to (not through org access)
      direct_repo_access_by_user_id = Hash.new { |h, k| h[k] = Set.new }
      users_with_direct_repo_access(repo_ids).each { |actor_id, repo_id| direct_repo_access_by_user_id[actor_id] << repo_id }

      # this is a mapping of user IDs to org IDs the user is a member of, but rather just org IDs where the user has direct access to at least one of its repos
      orgs_users_are_repo_collaborators_on = Hash.new { |h, k| h[k] = Set.new }
      direct_repo_access_by_user_id.each do |user_id, repo_ids|
        repo_ids.each { |repo_id| orgs_users_are_repo_collaborators_on[user_id] << org_ids_by_repo_id[repo_id] }
      end

      # this maps user IDs to the orgs they have direct access to
      orgs_users_are_members_of = Hash.new { |h, k| h[k] = Set.new }

      org_members.each do |user_id, org_id|
        orgs_users_are_members_of[user_id] << org_id
      end

      Array.new.tap do |outside_collaborator_ids|
        direct_repo_access_by_user_id.each do |user_id, _collaborator_repo_ids|
          # a user is an outside collaborator if they have abilities on at least one repo in an org they aren't a member of
          if (orgs_users_are_repo_collaborators_on[user_id] - orgs_users_are_members_of[user_id]).any?
            outside_collaborator_ids << user_id
          end
        end
      end
    end
  end

  private def users_with_direct_repo_access(repo_ids)
    T.unsafe(Ability.from("abilities FORCE INDEX(subject_and_actor_and_priority_and_action)")).batched_scope(:subject_id, values: repo_ids) do |scope|
      scope
        .where(subject_type: "Repository", actor_type: "User", priority: Ability.priorities[:direct])
        .group(:subject_id, :subject_type, :actor_type, :actor_id)
    end.pluck(:actor_id, :subject_id)
  end

  def async_outside_collaborators(**args)
    async_organizations.then { outside_collaborators(**args) }
  end

  def target_for_conditional_access
    self
  end

  # The class name persisted as `target_type` when a UserRole is created
  # with this object as target.
  def user_role_target_type
    "Business"
  end

  # Determines the target for for conditional access for multiple Business instances
  #
  # business - an enumerable of Business
  #
  # returns Hash[Business] => target for conditional access
  def self.multiple_target_for_conditional_access(businesses)
    ConditionalAccess::Filter.ensure_with_class(businesses, Business)
    businesses.each_with_object({}) { |v, h| h[v] = v }
  end

  # Public: Scope of Users associated with this business, limited by user's ability
  # to see their association with the business.
  #
  # viewer - The User viewing the business.
  # type - What types of org members do we want to see?
  #   :all                  - Show all visible business org users.
  #   :admin                - Only show users who are admins of an org.
  #   :member_without_admin - Only show users who are direct members of
  #                           the org but NOT admins.
  # ignore_visibility - A Boolean indicating whether to ignore whether or not
  #   org memberships are visible to the viewer. Defaults to false.
  # org_ids - Array of Integers. Only return members belonging to orgs with
  #   database IDs in the provided Array.
  #
  # Returns an ActiveRecord::Relation
  def visible_organization_members_for(viewer, type: :all, ignore_visibility: false, org_ids: nil)
    scope = case type
    when :all, :unaffiliated
      if GitHub.single_business_environment? && org_ids.blank?
        single_business_members
      else
        organization_members(org_ids: org_ids)
      end
    when :admin
      organization_members(action: :admin, org_ids: org_ids)
    when :member_without_admin, :guest_collaborator
      organization_members(action: :read, org_ids: org_ids)
    else
      raise ArgumentError, "Business#visible_organization_members_for type must be valid"
    end

    # Bypass checking which org memberships are visible to the viewer if
    # the viewer is a business admin or ignore_visibility is true.
    bypass_visibility_check = owner?(viewer) || ignore_visibility

    unless bypass_visibility_check
      visible_member_ids = organizations.flat_map { |org| org.visible_user_ids_for(viewer) }.uniq

      scope = scope.where(id: visible_member_ids)
    end

    # In case the `ghost` user gets added to the global business, make sure they
    # are never included in business member results.
    scope = scope.where("login <> ?", GitHub.ghost_user_login)

    scope
  end

  def primary_avatar_path
    "/b/#{id}"
  end

  def tenant_slug_for_avatar
    return "" unless GitHub.multi_tenant_enterprise?
    slug
  end

  def avatar_editable_by?(actor)
    owner?(actor)
  end

  def keep_old_avatar?
    false
  end

  # Public: See if any S4 stats exist for any EnterpriseInstallations belonging to this Business
  #
  # Returns boolean
  def has_s4_stats?
    s4 = GitHub::Connect::S4.new
    s4.record_count("b#{id}") > 0
  end

  # Public: Download the usage metrics data for all EnterpriseInstallation objects
  # associated with this business.
  #
  # format - the format we want the data in: "json" or "csv"
  #
  # Returns a hash of:
  #   :blob - the JSON/CSV data from the github/s4 service
  #   :record_count - the number of records in the blob
  #   :content_type - the content type of the blob (JSON or CSV mimetype on success)
  def s4_usage_metrics(format: "json")
    s4 = GitHub::Connect::S4.new
    s4.metrics_export("b#{id}", format: format)
  end

  # Public: Instrument creating records.
  #
  # payload - Hash of custom payload data.
  #
  # Returns nothing.
  def instrument_creation(payload = {})
    instrument :create, payload
  end

  # Public: Instrument marking as deleted (soft-deleting a record).
  #
  # payload - Hash of custom payload data.
  #
  # Returns nothing.
  def instrument_deletion(payload = {})
    instrument :delete, payload
  end

  # Public: Instrument restoration.
  #
  # payload - Hash of custom payload data.
  #
  # Returns nothing.
  def instrument_restoration(payload = {})
    instrument :restore, payload
  end

  # Public: Instrument permanent destruction (purging a soft-deleted record).
  #
  # payload - Hash of custom payload data.
  #
  # Returns nothing.
  def instrument_destruction(payload = {})
    instrument :destroy, payload
  end

  # Public: Instrument acceptance of terms of service when creating trial account.
  #
  # payload - Hash of custom payload data.
  #
  # Returns nothing.
  def instrument_accept_terms_of_service(payload = {})
    if trial?
      instrument :accept_terms_of_service, payload.merge!(tos_type: terms_of_service_type)
    end
  end

  # Public: Instrument changes to terms of service.
  #
  # payload - Hash of custom payload data.
  #
  # Returns nothing.
  def instrument_update_terms_of_service(payload = {})
    if saved_change_to_terms_of_service_type? ||
      saved_change_to_terms_of_service_notes? ||
      saved_change_to_terms_of_service_company_name?

      # Instrument a change if the ToS type, notes, or company name changes
      tos_changes = {}
      tos_changes[:terms_of_service_type] = {
        old_value: terms_of_service_type_before_last_save, new_value: terms_of_service_type
      }
      tos_changes[:terms_of_service_notes] = {
        old_value: terms_of_service_notes_before_last_save, new_value: terms_of_service_notes
      }
      tos_changes[:terms_of_service_company_name] = {
        old_value: terms_of_service_company_name_before_last_save, new_value: terms_of_service_company_name
      }

      instrument :update_terms_of_service, payload.merge!(tos_changes)
    end
  end

  # Public: Instrument an import of Enterprise Server license usage, either
  # via a manual upload or via an automatic upload with GitHub Connect.
  #
  # payload - Hash of custom payload data.
  #
  # Returns nothing.
  def instrument_import_license_usage(payload = {})
    instrument :import_license_usage, payload
  end

  # Public: Instrument an external identity for a user within this Business'
  # SAML Provider getting revoked
  #
  # payload - Hash of custom payload data.
  #
  # Returns nothing.
  def instrument_external_identity_revoked(payload = {})
    instrument :revoke_external_identity, payload
  end

  # Public: Instrument a user's SAML SSO session getting revoked.
  #
  # payload - Hash of custom payload data.
  #
  # Returns nothing.
  def instrument_sso_session_revoked(payload = {})
    instrument :revoke_sso_session, payload
  end

  # Public: Instrument a request to export GitHub Connect usage metrics data for
  # EnterpriseInstallations belonging to this Business.
  #
  # payload - Hash of custom payload data.
  #
  # Returns nothing.
  def instrument_connect_usage_metrics_export(payload = {})
    instrument :connect_usage_metrics_export, payload

    GlobalInstrumenter.instrument("github_connect.usage_metrics_export_request", {
      target_type: "BUSINESS",
      target_name: self.slug,
      target_id: self.id,
      requested_at: Time.now.utc
    })
  end

  # Public: Instrument removing a member from an enterprise.
  #
  # user   - The User to remove.
  # actor  - User performing the action.
  # reason - Text describing how or why.
  #
  # Returns nothing
  def instrument_remove_member(user:, actor:, reason:)
    instrument :remove_member, user: user, actor: actor, reason: reason

    GlobalInstrumenter.instrument("enterprise_account.remove_member", {
      enterprise: self,
      actor: actor,
      user: user,
      reason: reason
    })
  end

  def instrument_change_seats_plan_type(seats_plan_type_was:, seats_plan_type:)
    instrument :change_seats_plan_type, \
      seats_plan_type_was: seats_plan_type_was,
      seats_plan_type: seats_plan_type
  end

  # Public: Sync some of the values from a GitHub Enterprise license belonging
  # to the business. Currently only relevant in a single global business
  # environment (GitHub Enterprise Server).
  #
  # license - A GitHub::Enterprise::License belonging to this business.
  #
  # Returns the updated Business if successfully synced otherwise false.
  def sync_enterprise_license(license)
    return unless GitHub.single_business_environment?

    update \
      billing_term_ends_at: license.expire_at,
      seats: license.seats
  end

  # Public: Returns whether the business should be readable by a user
  #
  # user - user to check for visibility
  #
  # Returns true if the viewer should be able to see the business, false otherwise
  def readable_by?(user)
    return true if super

    return false if user.nil?
    return false if !user.is_a?(User) || !user.user?

    # all business members can access the business
    return true if member?(user)

    # users that have a removed member notification can see the business to
    # get access to the notification message
    return true if Business::RemovedMemberNotification.new(self, user).any?

    # users with a pending invitation can access the business
    return true if invitations.pending.where(invitee: user).exists?

    # admins for organizations with a pending invitation to join the business
    # can access the business
    if organization_invitations.pending.includes(:invitee).any? { |invite| T.must(invite.invitee).adminable_by?(user) }
      return true
    end

    false
  end

  # Public: The description of the Business run through the profile bio pipeline.
  #
  # Returns ActiveSupport::SafeBuffer
  def safe_description
    return @safe_description if defined? @safe_description
    @safe_description = GitHub::Goomba::ProfileBioPipeline.to_html(self.description)
  end

  # Public: Get the long description as HTML.
  #
  # Returns String.
  def long_description_html
    return @long_description_html if defined? @long_description_html
    @long_description_html = GitHub::Goomba::BusinessLongDescriptionPipeline.to_html(self.long_description)
  end

  def safe_profile_name
    name.blank? ? slug : name
  end

  def create_user_accounts_for_members
    user_ids = organization_member_ids + owner_ids + billing_manager_ids
    add_user_accounts(user_ids.uniq)
  end

  # Internal: performs cleanup to finish removing a user from a Business.
  # just a wrapper for remove_users_from_business (below)
  #
  # user  - user to be removed from the business
  # force - Removes the Business user account even if the business supports unaffiliated user accounts
  #
  # Returns nothing
  def remove_user_from_business(user, force: false)
    remove_users_from_business([user.id], force: force)
  end

  # Internal: performs cleanup for a list of users who are no longer part of the business:
  #  - deletes BusinessUserAccounts
  #  - destroys EnterpriseTeam memberships
  #  - unlinks ExternalIdentity's (SAML-provisioned ones only, keep SCIM-provisioned identities)
  #  - runs the RemoveBizUserForksJob job to clean up forks
  # (first checks if the users are still connected to the business in any way and only
  #  cleans up the ones who are not)
  #
  # user_ids - the ids of users to be removed from the business
  # force    - Removes the account even if the business supports unaffiliated user accounts or
  #            if the user may still be part of the business through other means.
  #
  # Returns nothing.
  def remove_users_from_business(user_ids, force: false)
    return if GitHub.single_business_environment?
    return if user_ids.empty?

    user_ids_to_remove = user_ids
    # Don't remove users that are still member of an org, owner or billing manager when account doesn't support
    # unaffiliated users or force is not used
    if !supports_unaffiliated_user_accounts? || !force
      business_user_ids = organization_member_ids + owner_ids + billing_manager_ids
      user_ids_to_remove -= business_user_ids
    end

    # Don't remove user if they are still a collaborator and business creates user accounts for collaborators.
    if add_collaborator_user_accounts? && !force && !user_ids_to_remove.empty?
      # Skip expensive outside_collaborator_id check if we're just dealing with 1 user
      if self.feature_enabled?(:skip_collaborator_query_for_single_user_removal) && user_ids.length == 1
        user = User.find(user_ids.first)
        user_ids_to_remove -= [user.id] if user.outside_collaborator_repositories(business: self).any? || user.guest_collaborator?
      else
        collaborator_ids = outside_collaborator_ids + guest_collaborator_ids
        user_ids_to_remove -= collaborator_ids
      end
    end

    GitHub.logger.info(
      "Business#remove_users_from_business",
      business_id: self.id,
      force: force,
      supports_unaffiliated_user_accounts: supports_unaffiliated_user_accounts?,
      user_ids: user_ids,
      user_ids_to_remove: user_ids_to_remove,
      owner_ids: owner_ids,
      billing_manager_ids: billing_manager_ids
    )

    unless user_ids_to_remove.empty?
      # Remove user accounts only if account does not support unaffiliated user accounts or force is enabled
      if !supports_unaffiliated_user_accounts? || force
        T.unsafe(user_accounts).remove_members(user_ids_to_remove)
      end

      user_ids_to_remove.each do |user_id|
        RemoveBizUserForksJob.perform_later(biz_id: self.id, belonging_to_user_id: user_id)
      end

      remove_support_entitlees(users: User.where(id: user_ids_to_remove))

      # Remove enterprise team memberships only if account does not support unaffiliated user accounts or force is enabled
      if !supports_unaffiliated_user_accounts? || force
        EnterpriseTeam.destroy_memberships_for(user_ids: user_ids_to_remove, business_id: T.must(self.id))
      end
    end

    if saml_sso_enabled?
      user_ids_to_deprovision = user_ids - admin_and_organization_member_ids
      unless user_ids_to_deprovision.empty?
        ExternalIdentity.unlink_saml_identities(provider: saml_provider,
                                                user_ids: user_ids_to_deprovision)
      end
    end

    RevokeInternalAppAuthorizationsJob.perform_later(enterprise_id: self.id, user_ids: user_ids)
  end

  # Check whether the Dependency Insights feature is enabled and visible
  # to the given user.
  #
  # Returns a Boolean value.
  def dependency_insights_enabled_for?(viewer)
    return false unless GitHub.dependency_graph_enabled?
    business_authz = SecurityProduct::Permissions::BusinessAuthz.new(self, actor: viewer)

    business_authz.can_modify_code_security_policies?
  end

  # Given a list of email addresses, look up any existing BusinessUserAccounts that
  # correspond to any of the given emails and belong to this Business.
  #
  # Note: The email addresses used as the keys in the returned Hash are downcased
  # to support case insensitive lookups by email on the Hash.
  #
  # emails - Array of String representing email addresses.
  #
  # Returns: A Hash of the form: { String => BusinessUserAccount, ... }
  #   where String is a downcased email address.
  def dotcom_users_from_emails(emails, slice_size: 1_000)
    users = {}
    emails.each_slice(slice_size).each_with_object({}) do |slice, _hash|
      user_emails = UserEmail.verified.where(email: slice).to_a
      user_ids = user_emails.map(&:user_id)
      user_accounts = self.user_accounts.where(user_id: user_ids).map do |a|
        [a.user_id, a]
      end.to_h
      users.merge!(user_emails.filter_map { |email| [email.email.downcase, user_accounts[email.user_id]] if user_accounts[email.user_id] }.to_h)
    end
    users
  end

  # Given a list of email addresses, return all existing BusinessUserAccounts that
  # correspond to any of the external identities that have any of the given emails
  # associated with the SAML-provided emails or username-related attributes.
  #
  # Note: The email addresses used as the keys in the returned Hash are downcased
  # to support case insensitive lookups by email on the Hash.
  #
  # emails - Array of String representing email addresses.
  #
  # Returns: A Hash of the form: { String => BusinessUserAccount, ... }
  #   where String is a downcased email address.
  def dotcom_users_from_extid_emails(emails, slice_size: 1_000)
    emails = emails.map(&:downcase)
    external_identities = T.let([], T::Array[T.untyped])
    user_accounts = {}
    providers = all_external_identity_providers

    emails.each_slice(slice_size).each do |slice|
      providers.each do |provider|
        e = ExternalIdentity.by_provider(provider).by_emails_in_attributes(slice)
        user_ids = e.map(&:user_id).compact
        ua = self.user_accounts.where(user_id: user_ids).map do |a|
          [a.user_id, a]
        end.to_h
        user_accounts.merge!(ua)
        # Whittle down the list of external identities to those that have BusinessUserAccounts
        external_identities += e.select { |e| user_accounts[e.user_id] }
      end
    end

    return {} if external_identities.empty?

    ActiveRecord::Associations::Preloader.new(
      records: external_identities,
      associations: [:identity_attribute_records]
    ).call
    external_identities.uniq.map do |ei|
      ext_emails = ei.emails.map(&:downcase)

      matching_email = emails.intersection(ext_emails).first
      [matching_email, user_accounts[ei.user_id]]
    end.to_h
  end

  def all_external_identity_providers
    providers = all_saml_providers
    providers << self.oidc_provider if self.oidc_enabled?
    providers
  end
  private :all_external_identity_providers

  # Get all unique SAML providers for the business or all of its orgs
  def all_saml_providers
    if self.saml_sso_enabled?
      [self.saml_provider]
    else
      Organization::SamlProvider.where(organization_id: self.organizations.pluck(:id)).to_a.uniq { |p| [p.sso_url, p.issuer] }
    end
  end

  # Given a list of email addresses, look up any EnterpriseInstallationUserAccounts
  # (representing GHES users) that correspond to any of the given emails and belong
  # to this Business, but are not yet associated with a GHEC User.
  #
  # Note: The email addresses used as the keys in the returned Hash are downcased
  # to support case insensitive lookups by email on the Hash.
  #
  # emails - Array of String representing email addresses.
  # slice_size - Integer value representing the batch size for user account ids
  # and emails when running queries.
  #
  # Returns: A Hash of the form: { String => BusinessUserAccount, ... }
  #   where String is a downcased email address.
  def enterprise_users_from_emails(emails, slice_size = 1_000)
    users = {}
    emails.each_slice(slice_size).each_with_object({}) do |slice, _hash|
      emails_to_buas = self.user_accounts
        .joins(:enterprise_installation_user_account_emails)
        .where(user_id: nil, enterprise_installation_user_account_emails: { email: slice })
        .select("business_user_accounts.*", "enterprise_installation_user_account_emails.email")
        .distinct
        .index_by { |bua| bua["email"].downcase }
      users.merge!(emails_to_buas)
    end
    users
  end

  def connected_enterprise_installations
    enterprise_installations
      .where.not(integration_id: nil)
      .order("host_name ASC")
  end

  def platform_type_name
    "Enterprise"
  end

  # Public: Send a notification to an admin after they are added.
  #
  # role - A Symbol representing the admin role (:owner, :billing_manager).
  # admin - The User that was added as an admin.
  #
  def send_admin_added_email_notification(role:, admin:)
    if enterprise_managed_user_enabled? && is_first_emu_owner?(user: admin)
      GitHub.logger.info("Sending first EMU business admin email for #{self.name}")
      EnterpriseManagedUserMailer.added_as_first_emu_business_admin(self, role, admin).deliver_later
    else
      GitHub.logger.info("Sending business admin email for #{self.name}")
      BusinessMailer.added_as_business_admin(self, role, admin).deliver_later
    end
  end

  # Public: Send a notification to an admin after they were removed.
  #
  # role - A Symbol representing the admin role (:owner, :billing_manager).
  # admin - The User that was removed as an admin.
  #
  def send_admin_removed_email_notification(role:, admin:, reason: nil)
    BusinessMailer.removed_as_business_admin(self, role, admin, reason).deliver_later
  end

  # Public: Send a notification to a user after they were removed.
  #
  # user - The User that was removed from the enterprise
  # roles_lost - The list of roles the user previously had across the enterprise and its organizations
  # organizations_removed_from - the organizations the user no longer has access to
  #
  def send_member_removed_email_notification(user, roles_lost, organizations_removed_from)
    BusinessMailer.removed_as_business_member(self, user, roles_lost, organizations_removed_from).deliver_later
  end

  # Public: Send a notification to an admin that their role has changed.
  #
  # new_role - A Symbol representing the admin role (:owner, :billing_manager).
  # admin - The admin whose role has changed
  #
  def send_admin_role_changed_notification(new_role:, admin:)
    BusinessMailer.admin_role_changed(self, new_role, admin).deliver_later
  end

  # Public: Whether the premium support mailer should be sent to the added admin
  #
  # The mailer should be sent if the added admin is the first admin
  # and the support plan is premium
  def send_initial_premium_support_mailer?(admin:)
    return false unless calculated_support_plan.starts_with?("premium")

    if enterprise_managed_user_enabled?
      is_first_emu_owner?(user: admin)
    else
      owner_ids == [admin.id]
    end
  end

  # Public: Whether the Business has configured and enabled Team Sync.
  #
  # Returns a Boolean.
  def team_sync_enabled?
    !!team_sync_tenant&.enabled?
  end

  # Also implemented by Organization, this allows config modules that apply to both
  # organizations and businesses (e.g. Configurable::MembersCanCreateRepositories)
  # to call `supports_internal_repositories?` without first checking whether it's
  # an Organization or Business.
  def supports_internal_repositories?
    true
  end

  # Handles the legacy settingValue argument in the
  # UpdateEnterpriseMembersCanCreateRepositoriesSetting mutation.
  #
  # permission - Required. The settingValue field provided to the mutation.
  # actor - Required. The user performing the mutation.
  #
  # Returns an array of enabled visibilities or nil if no policy is set.
  #
  # Note that we only handle legacy settings in this deprecated field. Internal repositories are
  # turned on when unspecified to match the behavior before granular permissions shipped. Setting
  # explicit permissions that include/exclude internal repositories is only possible with the new
  # boolean members_can_create_[public|private|internal]_repositories arguments.
  def legacy_graphql_set_repo_creation_permissions(permission, actor)
    case permission
    when T.must(Platform::Enums::EnterpriseMembersCanCreateRepositoriesSettingValue.values["ALL"]).value
      allow_members_can_create_repositories(force: true, actor: actor)
      %w[public private internal]
    when T.must(Platform::Enums::EnterpriseMembersCanCreateRepositoriesSettingValue.values["PRIVATE"]).value
      disallow_members_can_create_public_repositories(force: true, actor: actor)
      %w[private internal]
    when T.must(Platform::Enums::EnterpriseMembersCanCreateRepositoriesSettingValue.values["PUBLIC"]).value
      allow_members_can_create_repositories_with_visibilities(force: true, actor: actor,
        public_visibility: true,
        private_visibility: false,
        internal_visibility: true)
    when T.must(Platform::Enums::EnterpriseMembersCanCreateRepositoriesSettingValue.values["DISABLED"]).value
      disallow_members_can_create_repositories(force: true, actor: actor)
      []
    when T.must(Platform::Enums::EnterpriseMembersCanCreateRepositoriesSettingValue.values["NO_POLICY"]).value
      clear_members_can_create_repositories(actor: actor)
      nil
    end
  end

  def business?
    true
  end

  def user?
    false
  end

  def organization?
    false
  end

  def searchable?
    !deleted? && !destroyed?
  end

  # Public: Get the description for the terms of service type.
  #
  # Returns String.
  def terms_of_service_type_description
    TERMS_OF_SERVICE_TYPE_DESCRIPTIONS.at(T.must(TERMS_OF_SERVICE_TYPES.index(self.terms_of_service_type)))
  end

  # Public: Get the terms of service notes as HTML.
  #
  # Returns String.
  def terms_of_service_notes_html
    GitHub::Goomba::DescriptionPipeline.to_html(self.terms_of_service_notes)
  end

  # Get the human readable enterprise account administrator role based on the
  # role Symbol.
  #
  # role - Symbol or String representing the role (:owner, :billing_manager).
  #
  # Returns String
  def self.admin_role_for(role)
    case role&.to_sym
    when UNAFFILIATED_ROLE
      "Unaffiliated member"
    else
      role.to_s.titleize
    end
  end

  # Public: Returns the human readable role attribute of an administrator for
  # use in a message, with a preceding indefinite article.
  #
  # role - Symbol or String representing the administrator role (:owner, :billing_manager).
  #
  # Example usage:
  #
  # "This will add #{Business.admin_role_for_message(:owner)} to the enterprise."
  #
  # Returns String.
  def self.admin_role_for_message(role)
    case role&.to_sym
    when OWNER_ROLE
      "an owner"
    when BILLING_MANAGER_ROLE
      "a billing manager"
    when UNAFFILIATED_ROLE
      "an unaffiliated member"
    else
      "an administrator"
    end
  end

  # Public: Returns the instructions to tell owners how to manage enterprise
  # owners when owners are managed via an external authentication system in the
  # GHES environment.
  #
  # operation - Symbol representing the operation for which the instructions are
  #   relevant. Must be either `:add` or `:remove`.
  #
  # Returns String.
  def external_auth_system_owner_instructions(operation:)
    unless [:add, :remove].include?(operation)
      raise ArgumentError, "invalid operation: #{operation}"
    end

    auth_system_instructions = if GitHub.auth.ldap?
      if operation == :add
        "adding them to the LDAP admin group '#{GitHub.ldap_admin_group}'"
      elsif operation == :remove
        "removing them from the LDAP admin group '#{GitHub.ldap_admin_group}'"
      end
    elsif GitHub.auth.saml? && enterprise_server_scim_enabled?
      if operation == :add
        "assigning 'Enterprise Owner' application role to a user through SCIM provisioning via your IdP"
      elsif operation == :remove
        "removing 'Enterprise Owner' application role from a user through SCIM provisioning via your IdP"
      end
    elsif GitHub.auth.saml?
      if operation == :add
        "setting their SAML 'administrator' attribute to 'true'"
      elsif operation == :remove
        "removing their SAML 'administrator' attribute"
      end
    end

    auth_name = if GitHub.auth.saml? && enterprise_server_scim_enabled?
      "SCIM"
    else
      GitHub.auth.name
    end

    <<~MSG.squish
      Owners for the enterprise are managed via #{auth_name}.
      #{operation.to_s.titleize} owners by #{auth_system_instructions}.
    MSG
  end

  # Public: Is user the last remaining owner of this business?
  def last_owner?(user)
    adminable_by?(user) && members_count(action: :admin) == 1
  end

  # Public: check if admin invites are enabled for this business. Admins are added directly
  # for managed enterprises and for server (GHES) instances. Non-EMU dotcom
  # businesses go through the invitation process.
  #
  # Returns: Boolean
  def bypass_admin_invites?
    return true if enterprise_managed_user_enabled?
    GitHub.bypass_business_member_invites_enabled?
  end

  # Public: Review this Business, having been upgraded from an organization. This can only be done
  # on dotcom by GitHub staff for enterprises upgraded from organizations. Also, already reviewed
  # upgrades are not reviewable again.
  #
  # upgrade_reviewed_by - The User reviewing the upgrade.
  #
  # Returns a Boolean.
  def review_upgrade(upgrade_reviewed_by)
    return false if GitHub.single_business_environment?
    return false unless upgrade_reviewed_by.site_admin?
    return false unless upgraded?

    if reviewed?
      raise AlreadyReviewedUpgradeError, "Organization to enterprise upgrade already reviewed."
    end

    Business.transaction do
      touch :upgrade_reviewed_at
      update upgrade_reviewed_by_id: upgrade_reviewed_by.id
    end

    true
  end

  # Public: Checks if this Business was created as a result of being upgraded from an organization.
  #
  # Returns a Boolean.
  def upgraded?
    upgraded_at.present?
  end

  # Public: Checks if this Business has been reviewed by GitHub staff, having been upgraded from an
  # organization.
  #
  # Returns a Boolean.
  def reviewed?
    upgrade_reviewed_at.present?
  end

  # returns boolean if current business should display optional event settings
  def show_optional_audit_log_event_settings?
    can_enable_audit_log_ip_disclosure? || can_enable_audit_log_event_settings?
  end

  # Public: returns boolean if a business can use the Audit Log Code Search
  def can_enable_audit_log_code_search?
    return false if GitHub.enterprise?
    self.feature_enabled?(:code_search_query_processor)
  end

  # Public: returns boolean if biz can enable event settings
  def can_enable_audit_log_event_settings?
    return false if GitHub.enterprise?
    self.feature_enabled?(:audit_log_api_events_write)
  end

  # returns boolean if current business can disclose ip
  def can_enable_audit_log_ip_disclosure?
    !GitHub.enterprise?
  end

  # Public: returns boolean if biz can enable event settings
  def audit_log_multiple_streaming_endpoint_enabled?
    self.feature_enabled?(:audit_log_streaming_multiple_endpoints)
  end

  # Public: Use GitHub::SpamChecker to check whether this Business is spammy.
  def check_for_spam
    return if spammy?

    if reason = GitHub::SpamChecker.test_business(self)
      safer_mark_as_spammy(reason: reason)
    end
  end

  # Check whether this business has the plan support and either:
  #  settings enabled for display commenter full name on the business
  #  or user level enabling of the flag
  #
  # at a per repo level by visibility#
  #
  # visibility  - The visibility scope. :public or :internal.
  def display_commenter_full_name_for_repo?(visibility:, viewer:)
    is_allowed_scope_to_enable_in_business_settings = [:public, :internal].include?(visibility)
    self.plan_supports_display_commenter_full_name?(visibility: visibility) && self.display_commenter_full_name_setting_enabled? && is_allowed_scope_to_enable_in_business_settings
  end

  # Check if this business has a plan supporting display commenter full name
  #
  # visibility  - The visibility scope. :public or :internal.
  def plan_supports_display_commenter_full_name?(visibility:)
    self.plan.supports?(:display_commenter_full_name, visibility: visibility)
  end

  # Public: returns true if the user has any existing/pending connections to the enterprise account
  def user_connected_to_enterprise?(user)
    member?(user) || # direct/indirect member
      outside_collaborators.include?(user) ||
      # org billing manager or pending org member
      organizations.any? { |org| org.billing.member?(user) || org.pending_members.include?(user) } ||
      pending_admin_invitation_for(user, role: "owner") ||
      pending_admin_invitation_for(user, role: "billing_manager") ||
      (supports_unaffiliated_user_accounts? && user_accounts.where(user_id: user.id).exists?)
  end

  # Find businesses with name matching a specific query.
  #
  # Params:
  #
  #   query  - The string to search for
  #
  # Returns an Array of Businesses.
  def self.search(query, limit: 30)
    businesses = if query.present?
      query = ::Search::Queries::EnterpriseQuery.new(query: query, limit: limit)
      results = query.execute
      if results.empty?
        Business.none
      else
        Business.where(id: results.map { |hit| hit["_id"] })
      end
    else
      ::Business.by_slug
    end
    businesses
  end

  def solitarily_owned_member_organizations(user)
    @solitarily_owned_member_organizations ||= Hash.new do |hash, key|
      hash[key] = organizations
                    .where(id: user.solitarily_owned_organizations.pluck(:id))
                    .order(:login)
    end
    @solitarily_owned_member_organizations[user]
  end

  # Public: Sends welcome email to owners of the net new enterprise account.
  # The mailer should only be sent if the business is not in a single business environment.
  def send_welcome_net_new_enterprise_account_email
    return if GitHub.single_business_environment?

    if enterprise_web_business_id.present?
      BusinessCampaignMailer.welcome_net_new_enterprise_account_ghes(self).deliver_later(wait: 1.day)
    else
      if resource_creation_enabled? && self.feature_enabled?(:ghec_receive_net_new_enterprise_account_email_variation_a)
        BusinessCampaignMailer.welcome_net_new_enterprise_account_variation_a(self).deliver_later(wait: 1.day)
      elsif resource_creation_enabled? && self.feature_enabled?(:ghec_receive_net_new_enterprise_account_email_variation_b)
        BusinessCampaignMailer.welcome_net_new_enterprise_account_variation_b(self).deliver_later(wait: 1.day)
      else
        BusinessCampaignMailer.welcome_net_new_enterprise_account(self).deliver_later(wait: 1.day)
      end
    end
  end

  # Public: Returns organizations created from this Business account. This excludes organizations invited to the
  # Business account, and in the case the Business was upgraded from an organization, the organization it was
  # upgraded from is excluded too.
  #
  # Returns ActiveRecord::Relation.
  def enterprise_created_organizations
    non_enterprise_created_org_ids = organization_invitations.with_status(:confirmed).distinct.pluck(:invitee_id)
    if upgraded_from&.business_membership&.business_id == id
      non_enterprise_created_org_ids << upgraded_from_id
    end

    organizations.where.not(id: non_enterprise_created_org_ids)
  end

  # Public: Returns whether this Business has reached the limit for creation of organizations from
  # the Business account while in trial. Returns false for non-trial accounts.
  #
  # Returns Boolean.
  def trial_org_creation_limit_reached?
    return false unless trial?
    return false unless GitHub.flipper[:cap_enterprise_in_trial_org_creation].enabled?
    enterprise_created_organizations.count >= TRIAL_ORG_CREATION_LIMIT
  end

  def eligible_for_expired_trial_deletion?(feature_flag_check: true)
    return false if feature_flag_check && !self.feature_enabled?(:expired_trial_deletion)
    return false if enterprise_managed_user_enabled?
    return false if has_commercial_interaction_restriction?
    return false unless self.trial_expired?
    return false if self.invoiced?
    return false if self.deleted?
    return false if self.staff_owned?
    return false if self.trial_conversion_initiated?
    true
  end

  def expired_trial_business_deletion_email_sent!
    with_database_error_fallback do
      Growth::LastActivity::KV.store.set(
        self.expired_trial_business_deletion_email_key,
        "true",
        expires: 48.hours.from_now
      )
    end
  end

  def expired_trial_business_deletion_email_sent?
    Growth::LastActivity::KV.store.get(
      self.expired_trial_business_deletion_email_key
    ).value { nil }
  end

  def expired_trial_business_deletion_email_key
    "expired_trial_business_email_sent.#{self.id}"
  end

  def digital_front_door_authorization!
    with_database_error_fallback do
      Growth::LastActivity::KV.store.set(
        self.digital_front_door_authorization_key,
        "true",
        expires: 48.hours.from_now
      )
    end
  end

  def digital_front_door_authorization_sent?
    Growth::LastActivity::KV.store.get(
      self.digital_front_door_authorization_key
    ).value { nil }
  end

  def digital_front_door_authorization_key
    "digital_front_door_authorization.#{self.id}"
  end

  # Public: Determine if the business is a stafftools tenant in a multi-tenant environment
  #
  # Returns Boolean
  def stafftools_tenant?
    return false unless GitHub.multi_tenant_enterprise?
    if Rails.env.development?
      return GitHub::CurrentTenant::DEVELOPMENT_STAFFTOOLS_TENANTS.include?(slug)
    end
    GitHub::CurrentTenant::PRODUCTION_STAFFTOOLS_TENANTS.include?(slug)
  end

  # Public: Check if the business is eligible for onboarding resource creation.
  # The business must meet some conditions
  #
  # business - an enterprise account
  #
  # Returns true or false
  def resource_creation_enabled?
    return false if enterprise_managed?
    return false if seats.zero? && !metered_plan?
    return false unless feature_enabled?(:onboarding_resources_link_in_email)
    return false if part_of_startup_program?
    if coupon.present?
      return false if STARTUP_PROGRAM_COUPONS.include?(coupon.code)
      return false if STARTUP_PROGRAM_COUPONS_PREFIX.any? { |prefix| coupon.code.match?(/\A#{prefix}/) }
    end

    # Some more restrictions for the initial launch. See https://github.com/github/githubcustomers-bot/issues/280
    return false if self.customer&.billing_type != Customer::BILLING_TYPE_CARD
    RESOURCE_CREATION_ELIGIBLE_COUNTRY_CODE.include?(self.trade_screening_record.country_code)
  end

  # Public: Class method to generate a unique slug given a base string.
  # If not taken, the base string is returned. Otherwise, the method is called recursively
  # and appends a numeric suffix until a unique slug is found.
  # Arbitrarily picks 12 as the max attempt number, to not affect existing tests, and avoid infinite recursion.
  #
  # base    - The base string to generate a slug from.
  # attempt - The current attempt number.
  #
  # Returns a String slug.
  def self.unique_slug(base, attempt = 1)
    return "" if attempt >= 12
    return "" unless base

    candidate = if attempt == 1
      base
    else
      suffix = "-#{attempt}"
      prefix = base.first(MAX_SLUG_LENGTH - suffix.length)
      prefix + suffix
    end

    if Business.including_deleted.find_by(slug: candidate).present?
      unique_slug(base, attempt + 1)
    else
      candidate
    end
  end

  private

  # Private: The user who performed the action as set in the GitHub request context. If the context doesn't
  # contain an actor, fallback to the ghost user.
  def actor
    @actor ||= (User.find_by(id: GitHub.context[:actor_id]) || User.ghost)
  end

  # Private: Generates a unique URL-friendly slug for this business from its name.
  # If the slug is already taken a numeric suffix will be appended (i.e. "-2")
  # until a unique slug is found.
  #
  # Returns the String slug that was set.
  def generate_slug
    return unless name.present?

    unless T.cast(self.slug, T.nilable(String))
      self.slug = Business.unique_slug(name.parameterize.presence || GitHub.default_business_base_slug)
    end
  end

  def grant_initial_owners
    return unless defined?(@owners)
    initial_admins = remove_instance_variable(:@owners)

    initial_admins.each { |owner| grant owner, :admin }
  end

  def ensure_initial_owners_are_all_users
    return unless defined?(@owners)
    return if @owners.all? { |owner| owner.try(:user?) }

    errors.add(:owners, "must all be users")
  end

  def ensure_enough_seats
    return if metered_ghe?
    # The validation should allow overallocation of GHE seats, because, in
    # reality, what matters is the total consumed vs the total purchased
    # (both GHE and VSS)
    return if total_consumed_licenses <= total_purchased_licenses_with_overages

    errors.add(:seats, "must be equal to or greater than #{total_consumed_licenses - purchased_volume_licenses_with_overages}. " \
                "The total consumed licenses (both GHE and VSS), which is currently #{total_consumed_licenses}, " \
                "cannot be more than the total purchased licenses (both GHE and VSS), which is currently #{total_purchased_licenses_with_overages}")
  end

  def ensure_website_url_is_valid
    return unless website_url?

    errors.add(:website_url, "is not a valid http(s) URL") unless UrlHelper.valid_url?(website_url)
  end

  def business_type_not_modified
    if business_type_changed? && self.persisted?
      errors.add(:business_type, "Cannot change an existing business type")
    end
  end

  def shortcode_not_modified
    if shortcode_changed? && persisted?
      errors.add(:shortcode, "can't be changed")
    end
  end

  def ensure_ghas_seats_valid
    if !advanced_security_purchased_for_entity? && advanced_security_seats_for_entity != 0
      errors.add(:advanced_security_seats_for_entity, "must be 0 if advanced security is not enabled")
    end
  end

  def block_removal_of_last_owner(user)
    return if owners.count > 1
    error_message = "Last owner cannot be removed"
    raise Business::NoAdminsError.new(error_message) if last_owner?(user)
  end

  # Private: Instruments the github.enterprise_account.v0.OrganizationUpgrade event
  # based on the status of an organization upgrade into an Enterprise Account.
  def instrument_organization_upgrade_event(actor, status)
    organization = self.upgraded_from || self.upgrade_initiated_from_organization
    return unless organization

    GlobalInstrumenter.instrument("enterprise_account.organization_upgrade", {
      organization_id: organization.id,
      enterprise_id: self.id,
      actor_id: actor.id,
      organization_previous_plan: organization.plan_was&.name,
      organization_previous_customer_id: organization.customer&.id,
      billing_type: self.billing_type,
      status: status,
      marketplace_subscription: organization.active_marketplace_listing_subscription_items.any?
    })
  end

  # Private: instruments the github.enterprise_account.v0.CreationFromCouponRedemption event
  # based on the status of the creation process.
  def instrument_ea_creation_from_coupon_redemption(actor, status, coupon: nil)
    organization = self.upgraded_from || self.upgrade_initiated_from_organization

    GlobalInstrumenter.instrument("enterprise_account.creation_from_coupon_redemption", {
      enterprise_id: self.id,
      slug: self.slug,
      status: status,
      coupon: coupon,
      organization_id: organization&.id,
      actor_id: actor.id,
      organization_previous_plan: organization&.plan_was&.name,
    })
  end

  def set_default_terms_of_service_company_name
    self.terms_of_service_company_name = self.name unless self.terms_of_service_company_name.present?
  end

  def parsed_date(text)
    Date.strptime(text.to_s, "%Y-%m-%d").to_time(:utc)
  rescue ArgumentError
    nil
  end

  def ensure_single_global_business
    # A single global business already exists before the current business would
    # be created. Don't allow an additional business to be created.
    if Business.count > 0
      raise SingleGlobalBusinessError, "Only a single global business may exist in this environment"
    end
  end

  # Sync the global business admin status of the user with the site admin
  # status.
  def sync_global_business_owner_and_site_admin(user, is_owner)
    return unless GitHub.single_business_environment?

    if is_owner
      user.grant_site_admin_access "Promoted as admin of single global business" unless user.site_admin?
    else
      user.revoke_privileged_access "Demoted from admin of single global business" if user.site_admin?
    end
  end

  # Private: This method is used during an organization upgrade to a new enterprise account. It runs settings transfers
  # that must be done before the organization is added to the enterprise account, to ensure that the business
  # is in a certain desired state before the attachment. These operations should be small and non-blocking.
  # For settings transfers that can happen after the organization is added, please use the BusinessCreatedFromOrganizationJob.
  def transfer_settings_from_organization(organization, actor)
    return if self.trial?
    return if organization.invoiced?

    # Transfer over actions worflows permission values from the organization, to avoid invalid permissions for existing actions workflows.
    # This must be done before the organization is added, so that there is no disruption of service.
    self.set_default_workflow_permissions("write", actor) unless organization.actions_default_workflow_permissions_read_only?
    self.set_actions_workflow_permission_can_approve_pr(true, actor) if organization.actions_workflow_permission_can_approve_pr?
    # If the organization has the deploy key policy enabled or is unset, we need to enable it on the Business
    # even if the deploy key policy FF is not enabled for the business.
    self.configure_deploy_key_policy_on_creation(actor: actor, enable: true) if organization.deploy_key_policy_enabled? || organization.deploy_key_policy_unset?
    if organization.can_run_fork_pr_workflows?
      policy = Configurable::ForkPrWorkflowsPolicy::RUN_WORKFLOWS
      policy |= Configurable::ForkPrWorkflowsPolicy::RUN_WITH_TOKENS if organization.can_run_fork_pr_workflows_with_write_tokens?
      policy |= Configurable::ForkPrWorkflowsPolicy::RUN_WITH_SECRETS if organization.can_run_fork_pr_workflows_with_secrets?
      self.set_fork_pr_workflows_policy(policy: policy, actor: actor)
      self.set_actions_private_fork_pr_approvals_policy(policy: Configurable::ActionsPrivateForkPrApprovals::READ_ONLY_USERS, actor: actor) if organization.actions_private_fork_pr_approvals_policy == Configurable::ActionsPrivateForkPrApprovals::READ_ONLY_USERS
    end

    return unless self.has_valid_payment_method?

    # Enable Copilot on the Business if the upgrading Organization has it enabled
    # This must be done before the organization is added, so that its configuration settings are not lost upon joining.
    if Copilot::Organization.new(organization).copilot_enabled?
      Copilot::Business.new(self).enable_copilot_for_selected_organizations!([organization.id], actor)
    end

    # Transfer over all existing spending limits that the upgrading Organization has set to the Business.
    # This must be done before the organization is added, so that there is no disruption of service.
    # Currently the two possible spending limits are: codespaces and shared (actions & packages).
    organization.budgets.each do |budget|
      if budget.valid? || (budget.errors.count == 1 && budget.errors.first&.attribute == :payment_method)
        budget.errors.clear
        self.budget_for(group: budget.product.to_sym).configure(
          enforce_spending_limit: budget.enforce_spending_limit?,
          limit: budget.spending_limit_in_subunits / 100
        )
      end
    end
  end

  def upsert_organization_membership(organization, organization_upgrade)
    organization_membership = retry_on_find_or_create_error do
      organization_memberships.find_by(organization: organization) ||
        organization_memberships.create(organization: organization, organization_upgrade: organization_upgrade)
    end
    organizations.reload
    if organization_membership.valid?
      # At this point, the organization is a member of the business, but due to the has_one :through organization_memberships
      # relationship, organization.business is not set in memory
      # we do it manually so that we don't have to reload the organization_membership before organization.business is available
      organization.business = self
    end
    organization_membership
  end

  def synchronize_search_index
    if searchable?
      Search.add_to_search_index("enterprise", id)
    else
      RemoveFromSearchIndexJob.perform_later("enterprise", id)
    end
  end

  def set_spammy_notice
    return unless GitHub.spamminess_check_enabled?

    SpammyBusinessCheckJob.perform_later(self) if spammy?
  end

  # Private: Determine if this business needs to have its billing_end_date updated when the trial
  # expiration date of the business is updated. This can happen when the trial is extended or reset.
  #
  # new_trial_expires_at - The date the trial expiration is being updated to.
  #
  # Returns nothing.
  def update_billing_end_date_on_trial_extension?(new_trial_expires_at)
    return false unless trial?
    billing_term_ends_on < new_trial_expires_at
  end

  # Private: Restore soft deleted orgs that were deleted at the time of the business soft-deletion.
  # This will in turn restore the repos that were soft-deleted at the time of the orgs' soft-deletion.
  def restore_soft_deleted_org_repos(deleted_at)
    return unless soft_deleted_organizations.any?
    RestoreSoftDeletedBusinessOrganizationsJob.perform_now(self, deleted_at.to_i)
  end

  # Private: Determine the payment method enum for the Salesforce trial update Hydro event. A
  # Metered GHE business can use an Azure subscription as a payment method.
  #
  # Returns Symbol.
  def payment_method_enum
    if metered_ghe? && linked_azure_subscription?
      :AZURE_SUBSCRIPTION
    elsif has_credit_card? || has_paypal_account?
      :CARD
    else
      :UNKNOWN_METHOD
    end
  end

  # Private: Determine if autopay needs to be enabled for the business on trial conversion.
  #
  # Returns a Boolean.
  def enable_autopay_on_trial_conversion?
    return false unless self_serve_payment?
    return false if metered_ghe_with_azure_subscription?
    return false if autopay_disabled_by_india_rbi?
    true
  end

  # Private: Set the business's fine-grained PATs expiration limit config to a default value of 1 year.
  #
  # Returns nothing.
  sig { void }
  def set_default_fine_grained_token_expiration_limit
    return unless GitHub.flipper[:set_default_fg_pat_expr_limit_on_creation].enabled?

    set_fine_grained_personal_access_token_expiration_limit(actor: User.ghost, expiration: Configurable::PersonalAccessTokenExpirationLimit::DEFAULT_FINE_GRAINED_PAT_EXPIRATION_LIMIT)
  end
end
