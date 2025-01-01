# typed: false
# frozen_string_literal: true

class User < ApplicationRecord::Domain::Users
  after_commit :forget_plan_changed_this_save

  include Users::IUser

  include GitHub::Validations

  extend GitHub::SimplePagination
  include GitHub::Relay::GlobalIdentification

  include AbuseReportable
  include Configurable::ActionInvocation
  include Configurable::DefaultNewRepoBranch
  include Configurable::RestrictNonCommentPullRequestReviews
  include GitHub::ApplicationsCreationLimit
  include Dumpable
  include GitHub::FlipperActor
  include GitHub::VexiActor
  include User::AvatarList::Model
  include User::NewsiesAdapter
  include PrimaryAvatar::Model
  include Marketplace::Listable
  include StaffAccessible
  include Instrumentation::Model
  include SecurityAnalysisDependency
  include LegacyImportable
  include User::NotificationsDependency
  include User::PrivateProfileDependency
  include User::IssuesGraphDependency
  include User::PrivateAuditLogDependency
  include User::SecurityCenterDependency
  include Billing::Public::Product::Subscribable
  include GitHub::BatchedScope
  include Coders::CodableColumn
  include User::ExperimentDependency
  include StaffNotesDependency
  include User::InteractionLimitDependency
  include User::OrcidDependency
  include User::IssueTypesDependency
  include User::RemovalDependency
  include User::EducationDependency
  include User::SparkFeatureDependency

  include Permissions::Attributes::Wrapper
  self.permissions_wrapper_class = Permissions::Attributes::User

  attr_accessor :company_name

  # Selectively opt out of `validates_presence_of :admins` on orgs.
  # Use only when absolutely needed.
  attr_accessor :skip_admins_presence_validation

  # Selectively opt out of `validate :cannot_add_sanctioned_billing_emails` on orgs.
  # Use only when absolutely needed.
  attr_accessor :skip_sanctioned_billing_emails_validation

  # Logins are limited to alphanumerics and hyphens, and must start and end with
  # an alphanumeric. This can basically never change.
  # All sorts of code depends on these restrictions.
  LOGIN_REGEX = /\A[a-zA-Z0-9]+(-[a-zA-Z0-9]+)*\z/
  LOGIN_VALIDATION_MESSAGE = "may only contain alphanumeric characters or single hyphens, and cannot begin or end with a hyphen"
  LOGIN_MAX_LENGTH = 39
  PASSPHRASE_LENGTH = 15
  NOT_UNIQUE_LOGIN_MESSAGE = "is not available"
  PASSWORD_RULES = "minlength: #{PASSPHRASE_LENGTH}; allowed: unicode;"

  # same as LOGIN_REGEX except start/end regex matching
  ENTERPRISE_MANAGED_USER_LOGIN_REGEX = /\A[a-zA-Z0-9]+(-[a-zA-Z0-9]+)*-?/
  ENTERPRISE_MANAGED_BUSINESS_SUFFIX_REGEX = /[a-zA-Z0-9]+\z/i
  ENTERPRISE_MANAGED_USER_LOGIN_SEPARATOR = "_"

  # Logins for Emus will allow ENTERPRISE_MANAGED_USER_LOGIN_SEPARATOR (_) followed by alpha-numeric business suffix https://rubular.com/r/mR079p9MXcraMv
  LOGIN_REGEX_FOR_EMUS = /#{ENTERPRISE_MANAGED_USER_LOGIN_REGEX}#{ENTERPRISE_MANAGED_USER_LOGIN_SEPARATOR}#{ENTERPRISE_MANAGED_BUSINESS_SUFFIX_REGEX}/i
  LOGIN_VALIDATION_MESSAGE_FOR_EMUS = "prefix may only contain alphanumeric characters or a hyphen separating two portions of a username and the end of it, and it cannot begin with a hyphen, followed by a separator and a business shortcode."

  # We use a **very** loose regex here on purpose. We do not want anything
  # like an RFC-level validation, especially because we explicitly allow
  # emails like "johndoe@localhost" for git commit emails.
  #
  # See user_email_test for what this allows and doesn't allow,
  # and make sure to add tests if you change behavior.
  EMAIL_REGEX = /\A[^@\s.\0][^@\s\0]*@\[?[a-z0-9.-]+\]?\z/i

  MEGA_USER_REPOS_THRESHOLD = 50_000

  include User::AbilityDependency
  include User::AchievementsDependency
  include User::AdvancedSecurityDependency
  include User::AuthorEmailsDependency
  include User::NoticesDependency
  include User::OrganizationsDependency
  include User::RoleBasedPermissionsDependency
  include User::EnterpriseDependency
  include User::IgnoreDependency
  include User::RemoteAuthenticationDependency
  include User::CouponsDependency
  include User::BillingDependency
  include User::RolesDependency
  include User::ContributionsDependency
  include User::TwoFactorAuthenticationDependency
  include User::TwoFactorRegistrationsDependency
  include User::TwoFactorRequirementDependency
  include User::AccountTwoFactorRequirementDependency
  include User::InstrumentationDependency
  include User::InteractionsDependency
  include User::EnterpriseArOverridesDependency
  include User::TradeControlsDependency
  include TradeControls::TradeScreeningDependency
  include User::ConfigurationDependency
  include User::LdapDependency
  include User::DeveloperProgramDependency
  include Repositories::AssociatedRepositoriesDependency
  include User::PinsDependency
  include User::RateLimitAllowlistingDependency
  include User::DormancyDependency
  include User::EmailVerificationDependency
  include User::EmailUnlinkDependency
  include User::WikiDependency
  include User::OnboardingDependency
  include User::OauthDependency
  include User::SavedRepliesDependency
  include User::LanguagesDependency
  include User::ThirdPartyAnalyticsDependency
  include User::SecurityCheckupDependency
  include User::TwoFactorCheckupDependency
  include User::TwoFactorHolidayWarningDependency
  include User::ProjectsDependency
  include User::BusinessDependency
  include User::UserRankedDependency
  include User::UserStatusDependency
  include User::SponsorsDependency
  include User::ConfigRepoDependency
  include User::RepositoryTemplateDependency
  include User::PasswordDependency
  include User::ProfileReadmeDependency
  include User::ProfileNavigationDependency
  include User::ProfilesDependency
  include User::SignInAnalysisDependency
  include User::DiscussionsDependency
  include User::SuccessorsDependency
  include User::PreReleaseFeaturesMethods
  include User::FeatureFlagMethods
  include User::MarketplaceDependency
  include User::EnterpriseManagedDependency
  include User::MultiTenantEnterpriseManagedDependency
  include User::IntegrationInstallationDependency
  include User::CodespacesDependency
  include WorkspaceEditor::User::Dependency
  include Workbench::User::Dependency
  include User::AdvisoryCreditsDependency
  include User::ReviewRequestsDependency
  include User::CommandPaletteDependency
  include User::MobileDependency
  include User::TombstoneDependency
  include Rest::HasPinnedApiVersion
  include User::UserListsDependency
  include User::SettingsDependency
  include User::MemexProjectsDependency
  include User::AbuseDependency
  include User::StarsDependency
  include User::CustomRolesDependency
  include User::ProgrammaticAccessDependency
  include Marketplace::DelistDependency
  include Spam::MarkableAsSpammy
  include Suspension::SuspensionDependency
  include User::SpamDependency
  include User::AccountManagementDependency
  include User::LegalHoldsDependency
  include User::ClientApplicationDependency
  include User::AssignmentDependency
  include User::AccountAgeDependency
  include User::FeedPostDependency
  include User::PermissionsDependency
  include User::StratocasterDependency
  include User::RepositoryForkingDependency
  include User::FeedsConfigurationDependency
  include User::PackagesDependency
  include User::VulnerabilityAlertRuleDependency
  include UploadContainer::UserUploadContainerDependency
  include User::IssueTypesDependency
  include User::ConduitDependency
  include User::GitHubModelsDependency
  include User::StarredCopilotSpacesDependency
  include User::ZeroUserDependency

  validates_presence_of     :email, unless: proc { |user| !user.email_address_required? }
  validates_format_of       :billing_email, with: EMAIL_REGEX, message: "does not look like an email address", allow_nil: true, allow_blank: true
  validates :gravatar_email, unicode3: true
  validates :profile_name, :profile_email, :profile_blog, :profile_company,
            :profile_location, if: :profile_updated?,
            length: { maximum: 255 }
  validates :profile_bio, length: { maximum: Profile::BIO_MAX_LENGTH },
                          if: :limit_bio_length?
  validates :profile_pronouns,
    length: { maximum: Profile::PRONOUNS_MAX_LENGTH },
    allow_nil: true,
    if: :profile_updated?
  validate :profile_email_is_known, if: :profile_updated?
  validate :profile_social_accounts_are_valid, if: :profile_updated?
  validates_inclusion_of :profile_local_time_zone_name,
                         in: ActiveSupport::TimeZone.all.map { |tz| tz.name },
                         allow_nil: true,
                         message: "is not a valid time zone",
                         if: :profile_updated?

  # Passwords must adhere to these rules:
  #   - Must be at least `GitHub.password_minimum_length` characters long
  #   - Must be at most 72 characters long (anything longer is ignored by BCrypt)
  #   - Can't be your username
  # If the password is less than 16 chars and doesn't contain 2 spaces:
  #   - Must contain 1 lowercase letter
  #   - Must contain 1 number
  # If the password is 16 chars or more and has two spaces, we assume it is a
  # passphrase, and therefore exempt from specific char requirements.
  # Only run validation when password is present
  validates_presence_of     :password,                    if: :password_validation_required?
  validates_confirmation_of :password,                    if: :password_validation_required?, message: "doesn't match the password"
  validate                  :password_not_too_long,       if: :password_validation_required?
  validate                  :password_not_weak,           if: :password_validation_required?
  validate                  :enforce_stronger_password

  # Logins must adhere to these rules:
  #  - Must be unique, case insensitive
  #  - Must be no more than 40 characters long
  #  - Can only contain alphanumeric characters and dashes
  #  - Cannot begin with a dash
  #  - Cannot be one of DeniedLogins
  validates_presence_of     :login
  validates_length_of       :login, within: 1..LOGIN_MAX_LENGTH

  validates_format_of       :login, with: LOGIN_REGEX, if: :validate_personal_account_login?, message: LOGIN_VALIDATION_MESSAGE

  validates_format_of       :login, with: LOGIN_REGEX_FOR_EMUS, if: :validate_enterprise_account_login?, message: LOGIN_VALIDATION_MESSAGE_FOR_EMUS
  validates_format_of       :display_login, with: LOGIN_REGEX, if: :validate_enterprise_account_display_login?, message: LOGIN_VALIDATION_MESSAGE

  validate                  :ensure_login_not_reserved, if: :login_changed?
  validate                  :uniqueness_of_login
  validate                  :uniqueness_of_email, on: :create
  validate                  :staff_must_be_an_employee, if: :will_save_change_to_gh_role?
  validate                  :email_not_sanctioned, on: :create
  validate                  :email_not_disposable, on: :create
  validate                  :email_domain_not_reserved, on: :create, unless: :skip_reserved_domain
  attr_accessor :skip_reserved_domain

  validate :enforce_seat_limit, on: :create, unless: :skip_seat_limit_enforcement?

  validates :business_id, unless: :validate_multi_tenant_business_id?, numericality: { only_integer: true, equal_to: 0 }
  validates :business_id, if: :validate_multi_tenant_business_id?, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :prevent_changes_to_business_id, on: :update

  validates_presence_of :display_login
  validate :display_login_based_on_login

  encrypts :weak_password_check_result

  before_validation :sanitize_profile_name, if: :profile_updated?
  before_validation :set_display_login

  before_save    :hash_password
  before_create  :set_analytics_tracking_id
  before_create  :set_initial_primary_email
  before_save    :set_initial_gravatar_email

  # This is used to force staff==employee validation during any
  # `update_attribute` calls and is defined in roles_dependency.rb.
  before_save    :staff_must_be_an_employee!, if: :will_save_change_to_gh_role?

  before_create  :mark_for_spam_check
  before_create  :regenerate_token_secret
  before_create  :enable_mandatory_email_verification, if: lambda { GitHub.mandatory_email_verification_enabled? }

  before_update  :regenerate_token_secret, if: :will_save_change_to_password?
  before_update  :clear_spam_flag_if_allowlisted
  after_commit   :instrument_creation, on: :create
  after_commit   :sync_site_admin_and_global_business_admin, on: :create
  after_update   :sync_site_admin_and_global_business_admin
  after_save     :update_business_user_account_login, if: :saved_change_to_login?
  attr_accessor :provisioning_an_emu_user

  after_save     :update_business_user_account_spammy, if: :saved_change_to_spammy?
  after_save     :update_profile

  # Delete the following 2 hooks once the FF use_billing_locked_rather_than_disabled is fully enabled
  after_save     :record_plan_change_transaction, if: -> { saved_change_to_disabled? && !self.feature_flag_enabled?(:use_billing_locked_rather_than_disabled, default: false) }
  after_commit   :instrument_disabled, if: -> { saved_change_to_disabled? && !self.feature_flag_enabled?(:use_billing_locked_rather_than_disabled, default: false) }, on: [:create, :update]
  # Delete use_billing_locked_rather_than_disabled end

  after_commit   :enqueue_check_for_spam
  after_commit   :synchronize_search_index

  after_commit   :set_disabled_personal_billing_notice, on: [:create, :update]

  after_commit   :delist_marketplace_apps, on: [:create, :update], if: -> { previous_changes[:spammy] }
  after_commit   :set_spammy_notice, on: [:create, :update], if: -> { previous_changes[:spammy] }
  after_commit   :invalidate_pages_protected_domains, on: [:create, :update], if: -> { previous_changes[:spammy] }
  after_commit   :set_or_unset_staff_without_two_factor_notice, on: [:create, :update], if: :saved_change_to_gh_role
  after_commit   :alert_sponsors_listing_time_zone_changed, if: -> { GitHub.sponsors_enabled? }, on: [:update]
  after_commit   :tombstone_user_login, on: [:destroy, :update], if: -> { destroyed? || saved_change_to_login? }
  after_commit   :invalidate_cache
  after_update   :enqueue_update_locked_repositories, if: :plan_changed_to_paid?
  after_update   :remove_coupon_on_business_plus_upgrade
  after_update   :instrument_last_ip_update, if: :saved_change_to_last_ip?

  # NOTE: Need to declare these before associations so the emails aren't destroyed first.
  before_destroy       :memoize_email_for_instrument_deletion
  before_destroy       :destroy_user_callbacks_before_destroy
  after_destroy_commit :instrument_deletion
  after_destroy_commit :destroy_user_callbacks_after_commit

  # Use the CurrentTenant in the request to determine the scope of the user lookup for multi tenant environments.
  # Each business is independent and has no visibility into other businesses on the same instance.
  #
  # Only load this default scope if we are in multi tenant or test mode.
  if GitHub.multi_tenant_enterprise? || Rails.env.test?
    default_scope do
      scope_to_current_tenant if scope_to_current_tenant?
    end
  end

  # Should we scope the user lookups to the current tenant?
  #
  # Only applies to multi tenant environments.
  def self.scope_to_current_tenant?
    return false unless GitHub.multi_tenant_enterprise?
    return false if GitHub::CurrentTenant.unscoped?

    true
  end

  scope :by_ip, lambda { |ip| where(last_ip: ip) }
  scope :oldest_to_newest, -> { order("id ASC") }
  scope :newest_to_oldest, -> { order("id DESC") }
  scope :by_login, -> { order("login ASC") }

  scope :publicly_belongs_to, ->(org) {
    joins("INNER JOIN `public_org_members` " +
          "ON `public_org_members`.`user_id` = `users`.`id`").
        where(public_org_members: { organization_id: org })
  }

  # Users with a explicitly set marketing mail preference.
  scope :accepts_marketing_mail, -> {
    joins("INNER JOIN newsletter_preferences ON users.id = newsletter_preferences.user_id")
    .where("newsletter_preferences.elected_marketing_at IS NOT NULL")
    .where("newsletter_preferences.elected_transactional_at IS NULL")
  }

  scope :has_verified_email, lambda {
    where("EXISTS (SELECT 1 FROM user_emails where users.id = user_id AND user_emails.state = 'verified')")
  }
  scope :suspended, -> { where("suspended_at IS NOT NULL") }
  scope :not_suspended, -> { where(suspended_at: nil) }

  scope :exclude, lambda { |*users|
    users.empty? ? nil : where("users.id NOT IN (?)", users.flat_map(&:id))
  }

  scope :active_external_identities, -> (admin_login) {
    where("(EXISTS (SELECT 1 FROM external_identities
      WHERE external_identities.user_id = users.id
      AND   external_identities.active = 1)
      OR  login = :login)", { login: admin_login })
  }

  scope :disabled_by_scim, -> () {
    where("NOT EXISTS (SELECT 1 FROM external_identities
      WHERE external_identities.user_id = users.id
      AND   external_identities.active = 1)")
  }

  scope :like_login_or_profile_name, -> (input) {
    includes(:profile)
      .where(["users.login LIKE :q OR profiles.name LIKE :q", {
        q: "%#{ActiveRecord::Base.sanitize_sql_like(input)}%",
      }])
      .references(:profile)
  }

  scope :like_display_login_or_profile_name, -> (input) {
    includes(:profile)
      .where(["(users.business_id = :bid AND users.display_login LIKE :q) OR profiles.name LIKE :q", {
        bid: GitHub::CurrentTenant.get.try(:id) || NON_ENTERPRISE_MANAGED_BUSINESS_ID,
        q: "%#{ActiveRecord::Base.sanitize_sql_like(input)}%",
      }])
      .references(:profile)
  }

  scope :order_by_login_asc, -> {
    order("login ASC")
  }

  # time    :renamed_at
  # boolean :renaming
  # string  :_primary_email
  # string  :gravatar_id
  # string  :avatar_uuid
  # string  :deleted_by
  # string  :_billing_email
  # boolean :repository_next_participant
  # boolean :repository_navigation_v3_participant
  # string  :raw_login

  # Sticky protocol preferences.  See GitHub::RepositoryProtocolSelector.

  # { "push" => "ssh"
  # , "clone" => "gitweb"
  # }
  # hash :protocols

  # If we have to sync the ldap memberships after creating the user
  # boolean :needs_ldap_memberships_sync

  # Flag for users who have browsed from a known anonymizing proxy (e.g. Tor) at
  # some point.
  # boolean :has_used_anonymizing_proxy
  serialize_with_coder :raw_data, Coders::UserCoder

  has_many :repositories,
    -> { where(active: true) },
    foreign_key: :owner_id,
    inverse_of: :owner,
    after_add: [:synchronize_search_index],
    after_remove: [:synchronize_search_index] do

    def visible
      where(deleted: false).to_a
    end

    def sorted_visible
      @sorted_visible ||= visible.sort_by { |r| r.name.downcase }
    end
  end

  # rubocop:todo Rails/InverseOf
  has_many :deleted_repositories,
    -> { where(active: nil) },
    foreign_key: :owner_id, class_name: "Repository"

  has_many :public_repositories,
    -> { where(public: true, active: true) },
    foreign_key: :owner_id, class_name: "Repository"

  has_many :private_repositories,
    -> { where(public: false, active: true) },
    foreign_key: :owner_id, class_name: "Repository"

  has_many :owned_private_repositories,
    -> { where(public: false, parent_id: nil, active: true,  locked: false) },
    foreign_key: :owner_id,
    class_name: "Repository"

  has_one :first_non_fork_public_repository,
    -> { public_scope.active.where(parent_id: nil) },
    foreign_key: :owner_id,
    class_name: "Repository"

  has_one :most_popular_public_repository,
    -> { where(active: true).most_starred.public_scope },
    foreign_key: :owner_id, class_name: "Repository"
  # rubocop:enable Rails/InverseOf

  has_one :most_recent_session,
    -> { where(impersonator_session_id: nil).order("accessed_at DESC") },
    class_name: "UserSession"

  # Find all active (ie not soft-deleted) Organizations owned by this user that are not paying their bill
  has_many :disabled_orgs, ->(user) do
    unscope(where: :user_id).where(id: user.owned_organization_ids).on_paid_plan.active.disabled
  end, class_name: "Organization"

  has_one :mobile_push_notification_setting, dependent: :destroy

  # Repositories you own that have been pushed to or created recently
  # rubocop:todo Rails/InverseOf
  has_many :recently_updated_owned_repos,
    -> { where(active: true).order("repositories.pushed_at DESC, repositories.created_at DESC") },
    class_name: "Repository",
    foreign_key: :owner_id
  # rubocop:enable Rails/InverseOf

  has_many :assets,
    -> { order("id DESC") },
    class_name: "UserAsset"

  # These are records that this user has uploaded an image that has been
  # determined to be illegal or of extreme violence.
  # See github.com/github/schaefer for more
  # rubocop:todo Rails/InverseOf
  has_many :photo_dna_hits,
    foreign_key: :uploader_id
  # rubocop:enable Rails/InverseOf

  # Public repositories you own that have been pushed to or created recently
  # rubocop:todo Rails/InverseOf
  has_many :recently_updated_public_repos,
    -> { where(active: true, public: true).order("repositories.pushed_at DESC, repositories.created_at DESC") },
    class_name: "Repository",
    foreign_key: :owner_id
  # rubocop:enable Rails/InverseOf

  has_many :projects, -> { where(owner_type: "User") }, foreign_key: :owner_id # rubocop:todo Rails/InverseOf

  has_many :memex_projects, -> { where(owner_type: "User") }, foreign_key: :owner_id # rubocop:todo Rails/InverseOf
  destroy_dependents_in_background :memex_projects

  has_many :memex_project_visits, foreign_key: :viewer_id # rubocop:todo Rails/InverseOf
  destroy_dependents_in_background :memex_project_visits

  has_many :memex_project_items, foreign_key: :creator_id # rubocop:todo Rails/InverseOf
  has_many :memex_project_column_values, foreign_key: :creator_id # rubocop:todo Rails/InverseOf

  has_many :sub_issues, foreign_key: :actor_id, inverse_of: :user

  # rubocop:todo Rails/InverseOf
  has_many :created_memex_projects,
    class_name: "MemexProject",
    foreign_key: :creator_id
  # rubocop:enable Rails/InverseOf

  has_many :recently_visited_memex_projects, through: :memex_project_visits, source: :memex_project

  before_destroy { delete_has_many_association(:stars) }
  has_many :stars, dependent: :delete_all

  before_destroy { destroy_has_many_association :delivered_repository_invitations }
  # rubocop:todo Rails/InverseOf
  has_many :delivered_repository_invitations, foreign_key: "inviter_id", class_name: "RepositoryInvitation", dependent: :destroy
  # rubocop:enable Rails/InverseOf
  before_destroy { destroy_has_many_association :received_repository_invitations }
  # rubocop:todo Rails/InverseOf
  has_many :received_repository_invitations, foreign_key: "invitee_id", class_name: "RepositoryInvitation", dependent: :destroy
  # rubocop:enable Rails/InverseOf
  has_many :invited_repositories, -> { active.distinct },
    through: :received_repository_invitations,
    source: :repository

  before_destroy { destroy_has_many_association :feature_enrollments }
  has_many :feature_enrollments, as: :enrollee, dependent: :destroy

  has_one :interaction_setting, dependent: :destroy

  has_many :reviews, class_name: "PullRequestReview"
  has_many :reviewed_files, class_name: "UserReviewedFile"

  before_destroy { destroy_has_many_association :sessions }
  has_many :sessions, class_name: "UserSession", dependent: :destroy do
    def active
      all.select(&:active?)
    end

    def inactive
      all.reject(&:active?)
    end
  end

  has_one :cas_mapping, dependent: :destroy
  has_one :global_notice, dependent: :destroy

  has_one :classroom_user, dependent: :destroy

  has_one :saml_session, class_name: "SAML::Session", inverse_of: :user, dependent: :destroy
  has_one :saml_mapping, dependent: :destroy
  has_one :in_product_messaging_subscription, dependent: :destroy

  before_destroy { destroy_has_many_association :external_identities }
  has_many :external_identities, dependent: :destroy
  has_many :external_identity_sessions, through: :sessions

  # Audit log export git event records where the user or organization is the subject
  before_destroy { destroy_has_many_association :audit_log_git_event_exports }
  has_many :audit_log_git_event_exports, as: :subject, dependent: :destroy
  # Audit log web export records where the user or organization is the subject
  before_destroy { destroy_has_many_association :audit_log_web_exports }
  has_many :audit_log_web_exports, as: :subject, dependent: :destroy

  # Audit log async queries records where the user is the actor
  before_destroy { destroy_has_many_association :audit_log_async_queries }
  has_many :audit_log_async_queries, as: :actor, dependent: :destroy

  before_destroy { destroy_has_many_association :organization_members_exports }
  has_many :organization_members_exports, as: :subject, dependent: :destroy

  before_destroy { destroy_has_many_association :tos_acceptances }
  has_many :tos_acceptances, dependent: :destroy

  # Repositories you can write to that have been pushed to or created recently
  def recently_updated_member_repos
    member_repositories.order("repositories.pushed_at DESC, repositories.created_at DESC")
  end

  has_many :showcases, class_name: "Showcase::Collection", foreign_key: :owner_id # rubocop:todo Rails/InverseOf

  before_destroy { destroy_has_many_association :newsletter_subscriptions }
  has_many :newsletter_subscriptions, dependent: :destroy

  # These associations only exist to get the :dependent => :destroy behavior, so
  # they’re private to prevent external callers from abusing them.
  before_destroy { destroy_has_many_association :organization_invitations }
  has_many :organization_invitations, foreign_key: :invitee_id, dependent: :destroy # rubocop:todo Rails/InverseOf
  private :organization_invitations

  before_destroy { destroy_has_many_association :business_administrator_invitations }
  has_many :business_administrator_invitations, foreign_key: :invitee_id, dependent: :destroy # rubocop:todo Rails/InverseOf
  private :business_administrator_invitations

  before_destroy { destroy_has_many_association :team_membership_requests }
  has_many :team_membership_requests, foreign_key: :requester_id, dependent: :destroy # rubocop:todo Rails/InverseOf
  private :team_membership_requests

  before_destroy { destroy_has_many_association :survey_answers }
  has_many :survey_answers, dependent: :destroy
  before_destroy { destroy_has_many_association :survey_groups }
  has_many :survey_groups, dependent: :destroy

  # Public: CustomerAccount record if this User is being paid for by a Customer
  # (optional).
  has_one :customer_account, -> { general_purpose }, dependent: :destroy

  # Public: Customer that pays for this user (optional).
  has_one :customer, through: :customer_account, autosave: true

  has_many :authentication_records
  has_many :authenticated_devices

  # Public: External asset status and usage for repositories this user owns.
  # rubocop:todo Rails/InverseOf
  has_one :asset_status,
    -> { lfs },
    class_name: "Asset::Status",
    foreign_key: :owner_id,
    dependent: :destroy
  # rubocop:enable Rails/InverseOf

  before_destroy { destroy_has_many_association :inbound_application_transfers }
  # rubocop:todo Rails/InverseOf
  has_many :inbound_application_transfers,
    class_name: "OauthApplicationTransfer",
    foreign_key: "target_id",
    dependent: :destroy
  # rubocop:enable Rails/InverseOf

  before_destroy { destroy_has_many_association :outbound_application_transfers }
  # rubocop:todo Rails/InverseOf
  has_many :outbound_application_transfers,
    class_name: "OauthApplicationTransfer",
    foreign_key: "requester_id",
    dependent: :destroy
  # rubocop:enable Rails/InverseOf

  before_destroy { destroy_has_many_association :inbound_integration_transfers }
  has_many :inbound_integration_transfers,
    class_name: "IntegrationTransfer",
    dependent: :destroy,
    as: :target

  before_destroy { destroy_has_many_association :outbound_integration_transfers }
  # rubocop:todo Rails/InverseOf
  has_many :outbound_integration_transfers,
    class_name: "IntegrationTransfer",
    foreign_key: "requester_id",
    dependent: :destroy
  # rubocop:enable Rails/InverseOf

  before_destroy { destroy_has_many_association :gpg_keys }
  has_many :gpg_keys, dependent: :destroy
  has_many :gpg_key_emails, through: :gpg_keys, source: :emails

  # Public: Integrations owned by this user/org
  before_destroy { destroy_has_many_association :integrations }
  has_many :integrations,
    dependent: :destroy,
    as: :owner

  # Public: Installations for an Integration
  before_destroy { destroy_has_many_association :integration_installations }
  has_many :integration_installations,
    as: :target,
    dependent: :destroy

  # Public: Installation requests for an Integration for this account.
  before_destroy { destroy_has_many_association :integration_installation_requests }
  # rubocop:todo Rails/InverseOf
  has_many :integration_installation_requests,
    foreign_key: :target_id,
    dependent: :destroy
  # rubocop:enable Rails/InverseOf

  # Public: Requests for integration installations.
  before_destroy { destroy_has_many_association :requested_integration_installations }
  # rubocop:todo Rails/InverseOf
  has_many :requested_integration_installations,
    class_name: "IntegrationInstallationRequest",
    foreign_key: :requester_id,
    dependent: :destroy
  # rubocop:enable Rails/InverseOf

  # rubocop:todo Rails/InverseOf
  has_one :prerelease_agreement,
    -> { where(member_type: "User") },
    foreign_key: :member_id,
    as: :member,
    class_name: "PrereleaseProgramMember"
  # rubocop:enable Rails/InverseOf

  has_many :packages, foreign_key: "owner_id", class_name: "Registry::Package" # rubocop:todo Rails/InverseOf
  has_many :package_files, through: :packages

  has_and_belongs_to_many :companies

  has_one :legal_hold

  has_many :retired_namespaces, primary_key: "login", foreign_key: "owner_login" # rubocop:todo Rails/InverseOf

  before_destroy { destroy_has_many_association :marketplace_order_previews }
  has_many :marketplace_order_previews, class_name: "Marketplace::OrderPreview", dependent: :destroy

  # rubocop:todo Rails/InverseOf
  has_many :received_abuse_reports,
    class_name: "AbuseReport",
    foreign_key: :reported_user_id
  # rubocop:enable Rails/InverseOf

  # rubocop:todo Rails/InverseOf
  has_one :latest_received_abuse_report,
    -> { order(id: :desc) },
    class_name: "AbuseReport",
    foreign_key: :reported_user_id
  # rubocop:enable Rails/InverseOf

  before_destroy { destroy_has_many_association :user_roles }
  has_many :user_roles, as: :actor, dependent: :destroy

  before_destroy { destroy_has_many_association :business_user_accounts }
  has_many :business_user_accounts, dependent: :destroy

  has_many :subjected_issue_event_details,
    class_name: "IssueEventDetail",
    as: :subject

  has_many :projects, as: :owner

  # rubocop:todo Rails/InverseOf
  has_many :created_projects,
    class_name: "Project",
    foreign_key: :creator_id
  # rubocop:enable Rails/InverseOf

  has_many :project_cards, foreign_key: :creator_id # rubocop:todo Rails/InverseOf

  has_many :pull_request_reviews

  has_many :pull_request_review_comments

  before_destroy { delete_has_many_association(:review_requests) }
  has_many :review_requests, as: :reviewer

  before_destroy { destroy_has_many_association :two_factor_recovery_requests }
  has_many :two_factor_recovery_requests, dependent: :destroy

  # rubocop:todo Rails/InverseOf
  has_many :targeted_attribution_invitations,
    class_name: "AttributionInvitation",
    foreign_key: :target_id
  # rubocop:enable Rails/InverseOf

  has_many :codespaces, foreign_key: :owner_id # rubocop:todo Rails/InverseOf

  after_commit :delete_dependent_codespaces, on: :destroy

  has_many :metered_usage_exports,
    class_name: "Billing::MeteredUsageExport",
    as: :billable_owner

  before_destroy { destroy_has_many_association :sent_successor_invitations }
  # rubocop:todo Rails/InverseOf
  has_many :sent_successor_invitations, class_name: "SuccessorInvitation", foreign_key: :inviter_id, dependent: :destroy
  # rubocop:enable Rails/InverseOf

  before_destroy { destroy_has_many_association :received_successor_invitations }
  # rubocop:todo Rails/InverseOf
  has_many :received_successor_invitations, class_name: "SuccessorInvitation", foreign_key: :invitee_id, dependent: :destroy
  # rubocop:enable Rails/InverseOf

  before_destroy { destroy_has_many_association :successor_invitations }
  has_many :successor_invitations, as: :target, dependent: :destroy

  has_many :profile_highlights, dependent: :destroy
  has_many :requested_features_to_organizations, class_name: "MemberFeatureRequest", foreign_key: :requester_id, dependent: :delete_all, inverse_of: :requester
  has_many :move_work, dependent: :destroy
  has_many :organization_membership_entries
  destroy_dependents_in_background :organization_membership_entries

  has_many :issue_types, foreign_key: :owner_id, inverse_of: :owner

  # Added in order to support preloading of soft deleted organizations and avoid N+1 queries
  has_one :soft_deleted_organization, dependent: :destroy, foreign_key: :organization_id, inverse_of: :organization
  scope :without_soft_deleted_organizations, -> { where.missing(:soft_deleted_organization) }

  has_many :enterprise_team_memberships, inverse_of: :user
  destroy_dependents_in_background :enterprise_team_memberships

  # Added in order to support https://github.com/github/search-and-flywheel/issues/193
  #
  # Gives us a mechanism to skip the reserved_domain validation for EMU users
  def initialize(opts = {}, &block)
    if FeatureFlag.vexi.enabled?(:reserved_domain, default: true)
      self.skip_reserved_domain = opts&.fetch("skip_reserved_domain", false)
    else
      self.skip_reserved_domain = false
    end
    self.provisioning_an_emu_user = opts&.fetch("provisioning_an_emu_user", false)
    super(opts, &block)
  end

  # validate personal account login handles in GitHub.  This validation will be skipped for EMU.
  # will_save_change_to_login and validates_login_format are over-written in Bot User model
  #
  # is_enterprise_managed_user is a dependency from "enterprise-managed" business types.
  def validate_personal_account_login?
    return false if GitHub.multi_tenant_enterprise?

    will_save_change_to_login? &&
    validates_login_format? &&
    !is_enterprise_managed_user?
  end

  # is_enterprise_managed_user logins are provisioned by service and have a different regex than personal account logins and Bot logins
  # Used for EMUs in dotcom and multi tenant mode when the shortcode suffix is being used.
  # Skips multi tenant enterprise where the shortcode suffix is not used.
  def validate_enterprise_account_login?
    will_save_change_to_login? &&
    validates_login_format? &&
    is_enterprise_managed_user?
  end

  # Same as validates_login_format? except it skips validation of users, only applies to organizations
  def validate_enterprise_account_display_login?
    login != display_login &&
    errors[:login].blank? &&
    validate_enterprise_account_login? &&
    organization?
  end

  # business_id cannot be changed after creation
  def prevent_changes_to_business_id
    return unless business_id_changed?

    errors.add :business_id, message: "cannot be changed"
  end

  def reload(*)
    @force_enterprise_managed = nil
    @login_suffix = nil
    @profile_settings = nil

    # Used to memoize the membership_via_org_ids method in business_dependency.rb
    remove_instance_variable(:@membership_via_org_ids) if defined?(@membership_via_org_ids)
    remove_instance_variable(:@codespaces_feature_enabled) if defined?(@codespaces_feature_enabled)

    remove_instance_variable(:@org_is_on_standard_tos) if defined?(@org_is_on_standard_tos)
    super
  end

  def change_owner_of!(project:, creator:, old_owner:)
    # On the off chance someone is transferring a note-only or empty project
    # from an Organization to a User, we need to clear the abilities out to
    # avoid transferring teams that don't exist on the User account
    Ability.clear(project) if old_owner.is_a?(Organization)
  end

  # Internal: an abstract collection, for the sub-resources the user
  # available for abilities
  def resources
    User::Resources.new(self)
  end

  # Internal: an abstract collection, for the sub-resources of repositories
  # available for abilities
  def repository_resources
    User::RepoCollection.new(self)
  end

  def member_repositories
    ids = Ability.where(
        subject_type: "Repository",
        actor_id: id,
        actor_type: "User",
        priority: Ability.priorities[:direct],
    ).pluck(:subject_id)
    Repository.active.where(id: ids)
  end

  def outside_collaborator_repositories(business:, on_repositories_with_visibility: [:public, :private])
    repository_visibility = on_repositories_with_visibility.map do |visibility|
      { public: 1, private: 0 }[visibility]
    end.compact

    permission_cache_key = [
      "user_outside_collaborator_repositories",
      id, business.id, on_repositories_with_visibility
    ]

    PermissionCache.fetch permission_cache_key do
      Repository.active.
        where(public: repository_visibility).
        where(id: associated_repository_ids(min_action: :read, including: [:direct])).
        where(organization_id: business.organization_ids - organization_ids)
    end
  end

  # Provide a reason why a hubber's stafftools page was viewed
  # Gives a viewing user one hour to make requests on the viewed hubber's stafftools page
  def set_hubber_access_reason(viewing, reason)
    Users::Kv.store.set("user.hubber_access_reason_provided.#{self.id}viewing#{viewing.id}", "true", expires: 1.hour.from_now)
    auditing_actor = GitHub.guarded_audit_log_staff_actor_entry(self)
    payload = auditing_actor.merge(
      user: viewing,
      viewing_reason: reason,
    )
    GitHub.instrument("staff.hubber_access_reason_provided", payload)
  end

  def hubber_access_reason_provided?(viewing)
    Users::Kv.store.get("user.hubber_access_reason_provided.#{self.id}viewing#{viewing.id}").value { nil }
  end

  # Public: Was this user created in the last 24 hours (default)?
  def recently_created?(since = 24.hours.ago)
    created_at > since
  end

  def all_repositories_count
    repositories.size + member_repositories.size
  end

  # Returns a 2-tuple:
  # [repos, repo_count_exceeds_limit]
  def owned_and_member_repos_by_name(limit:)
    limit = Integer(limit)
    owned = recently_updated_owned_repos.limit(limit)
    member = recently_updated_member_repos.limit(limit)
    exceeds_limit = (owned.size == limit || member.size == limit)
    result = (owned + member).sort_by { |r| r.name_with_owner.downcase }
    [result, exceeds_limit]
  end

  # Find this user's non-cnamed pages
  # and make sure they have valid https_redirect values.
  #
  # Returns nothing.
  def propagate_https_redirect
    recently_updated_owned_repos.each do |repo|
      if (page = repo.page) && page.cname.nil?
        page.set_https_redirect
        page.save if page.https_redirect_changed?
      end
    end
  end

  # This is where the follow associations used to be defined in-line.
  # For a yet unknown reason, some things break if we move this higher up with the other module includes
  # (specifically above User::IgnoreDependency)
  include User::FollowDependency

  has_many :pull_requests
  before_destroy -> { destroy_has_many_association(:u2f_registrations) }
  has_many :u2f_registrations,    dependent: :destroy
  has_many :trusted_device_client_registrations
  has_one  :webauthn_user_handle, dependent: :destroy
  before_destroy -> { destroy_has_many_association(:public_keys) }
  has_many :public_keys,          dependent: :destroy, extend: PublicKey::CreationExtension
  before_destroy -> { destroy_has_many_association(:git_signing_ssh_public_keys) }
  has_many :git_signing_ssh_public_keys, dependent: :destroy
  before_destroy -> { destroy_has_many_association(:commit_comments) }
  has_many :commit_comments,      dependent: :destroy
  has_one  :profile,             dependent: :destroy
  has_one  :interaction,         dependent: :destroy

  before_destroy -> { destroy_has_many_association(:issues) }, if: :spammy?
  has_many :issues
  before_destroy -> { destroy_has_many_association(:issue_comments) }, if: :spammy?
  has_many :issue_comments
  has_many :discussions
  has_many :discussion_comments

  has_many :gists
  has_many :gist_comments

  # rubocop:todo Rails/InverseOf
  has_many :gist_forks,
    -> { where("gists.parent_id IS NOT NULL AND gists.delete_flag = ?", false) },
    class_name: "Gist",
    foreign_key: :user_id
  # rubocop:enable Rails/InverseOf

  has_many :gist_stars

  has_many :starred_gists,
    -> { where(delete_flag: false) },
    through: :gist_stars,
    source: :gist

  before_destroy { delete_has_many_association(:email_roles) }
  has_many :email_roles, dependent: :delete_all

  before_destroy { delete_has_many_association(:emails) }
  has_many :emails, dependent: :delete_all, class_name: "UserEmail"

  has_one :primary_user_email_role, -> { primary }, class_name: "EmailRole"
  has_one :primary_private_user_email_role, -> { primary.where(public: false) }, class_name: "EmailRole"
  has_one :primary_user_email, through: :primary_user_email_role, source: :email
  has_one :primary_private_user_email, through: :primary_private_user_email_role, source: :email
  has_one :stealth_user_email_role, -> { stealth }, class_name: "EmailRole"
  has_one :stealth_user_email, through: :stealth_user_email_role, source: :email

  has_one :backup_user_email_role, -> { backup }, class_name: "EmailRole"
  has_one :backup_user_email, through: :backup_user_email_role, source: :email

  before_destroy { destroy_has_many_association(:reactions) }
  has_many :reactions, dependent: :destroy # deprecated, please use the specific {type}Reactions models below
  before_destroy { destroy_has_many_association(:commit_comment_reactions) }
  has_many :commit_comment_reactions, dependent: :destroy
  before_destroy { destroy_has_many_association(:discussion_reactions) }
  has_many :discussion_reactions, dependent: :destroy
  before_destroy { destroy_has_many_association(:discussion_comment_reactions) }
  has_many :discussion_comment_reactions, dependent: :destroy
  before_destroy { destroy_has_many_association(:issue_comment_reactions) }
  has_many :issue_comment_reactions, dependent: :destroy
  before_destroy { destroy_has_many_association(:issue_reactions) }
  has_many :issue_reactions, dependent: :destroy
  before_destroy { destroy_has_many_association(:pull_request_review_comment_reactions) }
  has_many :pull_request_review_comment_reactions, dependent: :destroy
  before_destroy { destroy_has_many_association(:pull_request_review_reactions) }
  has_many :pull_request_review_reactions, dependent: :destroy
  before_destroy { destroy_has_many_association(:release_reactions) }
  has_many :release_reactions, -> { where(subject_type: "Release") }, class_name: "Reaction"
  before_destroy { destroy_has_many_association(:repository_advisory_reactions) }
  has_many :repository_advisory_reactions, -> { where(subject_type: "RepositoryAdvisory") }, class_name: "Reaction"
  before_destroy { destroy_has_many_association(:repository_advisory_comment_reactions) }
  has_many :repository_advisory_comment_reactions, -> { where(subject_type: "RepositoryAdvisoryComment") }, class_name: "Reaction"
  before_destroy { destroy_has_many_association(:discussion_post_reactions) }
  has_many :discussion_post_reactions, -> { where(subject_type: "RepositoryAdvisoryComment") }, class_name: "Reaction"
  before_destroy { destroy_has_many_association(:discussion_post_reply_reactions) }
  has_many :discussion_post_reply_reactions, -> { where(subject_type: "RepositoryAdvisoryComment") }, class_name: "Reaction"

  has_one :dashboard, class_name: "UserDashboard", dependent: :destroy

  before_destroy { destroy_has_many_association(:dashboard_pins) }
  has_many :dashboard_pins, -> { ordered_by_position }, class_name: "UserDashboardPin", dependent: :destroy

  has_one :user_metadata, dependent: :destroy
  has_many :profile_pins, -> { ordered_by_position }, through: :profile

  has_many :pinned_repositories, -> { public_scope.active }, through: :profile_pins,
     source: :pinned_item, source_type: "Repository", disable_joins: true

  has_many :user_seen_features

  before_destroy { destroy_has_many_association(:advisory_credits) }
  # rubocop:todo Rails/InverseOf
  has_many :advisory_credits, -> { order(id: :asc) },
    foreign_key: "recipient_id", dependent: :destroy
  # rubocop:enable Rails/InverseOf

  has_many :mannequin_claims, foreign_key: :claimant_id # rubocop:todo Rails/InverseOf
  has_many :mannequins, through: :mannequin_claims

  has_many :releases

  has_many :release_mentions
  destroy_dependents_in_background :release_mentions

  has_many :search_custom_scopes, dependent: :destroy

  BATCH_SIZE = 100

  def verified_keys
    public_keys.where("verified_at is not null")
  end

  has_one :business_user_account, foreign_key: :user_id # rubocop:todo Rails/InverseOf

  # Queues a background job to suspend all dormant users. This is currently
  # only allowed under Enterprise.
  #
  # Returns nothing (false if run outside of Enterprise mode).
  def self.suspend_dormant_users(threshold = GitHub.dormancy_threshold)
    # running this on .com would be a big mistake
    return false unless GitHub.enterprise?

    UserSuspendDormantJob.perform_later(threshold.to_i)
  end

  def self.employees
    employees = Team.with_org_name_and_slug("github", "Employees")
    return [] if GitHub.enterprise? || employees.blank?

    employees.members.
      reject { |user| GitHub.hidden_teamster?(user) }
  end

  def self.interns
    interns = Team.with_org_name_and_slug("github", "Interns")
    return [] if GitHub.enterprise? || interns.blank?

    interns.members - employees
  end

  # Internal: users who have been inactive since signup
  #   signup_date - a Time object (e.g. 7.days.ago)
  #
  # Returns an Array of User objects
  def self.inactive_after_signup(signup_date)
    signup_from    = signup_date.beginning_of_day
    signup_to      = signup_date.end_of_day

    sql = Arel.sql(<<-SQL, signup_from: signup_from, signup_to: signup_to)
      SELECT users.* FROM users
      LEFT JOIN
        interactions ON interactions.user_id = users.id
      WHERE
      ( interactions.last_active_at is null OR
        interactions.last_active_at < :signup_to )
      AND
        users.created_at BETWEEN cast(:signup_from as datetime) AND cast(:signup_to as datetime)
      AND
        users.type = 'User'
    SQL

    self.find_by_sql(sql)
  end

  # Used by the API, GraphQL, and views to retrieve the profile email.
  # For users, the method respects the user's email privacy preferences, and
  # will return `nil` if the user has asked us not to publish their email.
  # Organization's profile emails are always considered public.
  #
  # logged_in - is the current viewing user logged in? Users are required to log
  #             in to see another user's email, unless in Enterprise
  #
  # Returns the user's profile email, as a string, or nil
  def publicly_visible_email(logged_in: false)
    return profile_email.presence if organization?
    return unless logged_in || GitHub.enterprise?
    return profile_email.presence if is_enterprise_managed?
    profile_email.presence if primary_user_email_role && primary_user_email_role.public?
  end

  # Public: Determines if the user's email is a valid email address.
  #
  # Returns true if valid, false otherwise.
  def self.valid_email?(email)
    return false if email.blank?
    return false if email.is_a?(User)
    (email =~ User::EMAIL_REGEX).present?
  end

  def safe_profile_name
    profile_name.blank? ? display_login : profile_name
  end

  def login=(login)
    super
    set_display_login
    login
  end

  # Set the User's primary email
  def email=(new_email)
    return if new_email.blank?
    add_email(new_email.to_s, is_primary: true)
  end

  # Internal: The user's primary email address.
  #
  # See also `outbound_email` and `git_author_email` -
  # client code should prefer those methods
  def email
    @primary_email ||= primary_user_email.try(:email)
  end

  # Internal: The user's backup email address. This email can be used for
  # password resets.
  def backup_email
    backup_user_email.try(:email)
  end

  # Public: The user's 'public facing' email address
  #
  # Use this for any sort of outbound email from GitHub,
  # as it will ensure that stealth emails get used if the user wants them
  def outbound_email
    if user? && is_enterprise_managed?
      profile_email
    elsif use_stealth_email?
      stealth_email.to_s
    else
      email
    end
  end

  # Public: Whether the user has a pro plan badge on their profile/hovercard
  def has_pro_plan_badge?
    return false if employee?

    can_have_pro_badge? && profile_settings.pro_badge_enabled?
  end

  # Public: The email to attribute commits to when a user importing a repository
  # maps an incoming commit author to an existing user on GitHub. Used instead
  # of git_author_email because the attribution is made by the user importing
  # the repository and not necessarily the user that is being attributed.
  #
  # Returns a String.
  def public_attribution_email
    if profile && profile.email.present?
      profile.email
    else
      anonymous_user_email
    end
  end

  # Public: did the user associate the specified email address
  # with this account?
  #
  # Returns Boolean
  def is_known_email?(email_address)
    if user? && is_first_emu_owner?
      # defined in enterprise_managed_dependency
      known_email?(email_address)
    else
      !!emails.user_entered_emails.find_by_email(email_address)
    end
  end

  # The primary email address with name part as a simple hash.
  def email_info
    {
      "name"    => safe_profile_name,
      "address" => outbound_email,
    }
  end

  attribute :color_mode, :color_mode_type
  attribute :light_theme, :user_theme_type
  attribute :dark_theme, :user_theme_type

  attribute :login, User::UserLoginType.new

  # Get the user's color mode or return default color mode,
  # allowing us to change the default color mode for users
  # that have yet to select one.
  #
  # Returns String
  def color_mode_with_default
    if color_mode.unset?
      ColorMode.default
    else
      color_mode
    end
  end

  def active_theme
    if color_mode_with_default.light?
      light_theme
    elsif color_mode_with_default.dark?
      dark_theme
    end
  end

  # Value to set when toggling a User's color mode.
  # For example, if a user is using LIGHT mode, return DARK
  #
  # Returns String
  def color_mode_toggle_target
    if color_mode_with_default.light?
      UserTheme::DEFAULT_DARK
    else
      UserTheme::DEFAULT_LIGHT
    end
  end

  # Extract git author info from an object representing a person.
  #
  # person - The person whose git author info we want. Can either be a
  #          User object or a hash with :name and :email keys.
  #
  # Returns an Array that looks like [name, email].
  def self.git_author_info(person)
    if person.is_a?(User)
      [person.git_author_name, person.git_author_email]
    else
      [person[:name], person[:email]]
    end
  end

  def user_type
    self[:type]
  end

  def gravatar_id
    return unless email = gravatar_email
    return if email.to_s.blank?
    GitHub.generate_gravatar_id(email.to_s.strip.downcase)
  end

  def identicon_id
    @identicon_id ||= begin
                        if GitHub.fips_mode?
                          Digest::SHA256.hexdigest(id.to_s)
                        else
                          Digest::MD5.hexdigest(id.to_s) # rubocop:disable GitHub/InsecureHashAlgorithm
                        end
                      end
  end

  # Internal: Set the gravatar email for the
  # user if it is already set.
  def set_gravatar_email(email)
    if emails.size == 1 && gravatar_email.nil?
      self.gravatar_email = email
    end
  end

  # Sets the gravatar email and the gravatar_id cache, as well as the
  # various view caches.
  #
  # email - The String email to set as the Gravatar email.
  #
  # Returns nothing.
  def gravatar_email=(new_email)
    new_email = new_email.to_s.strip
    write_attribute(:gravatar_email, new_email.blank? ? nil : new_email)
  end

  def self.primary_avatar_path_for_user_id(user_id)
    "/u/#{user_id}"
  end

  def primary_avatar_path
    @primary_avatar_path ||= self.class.primary_avatar_path_for_user_id(id)
  end

  # The user who performed the action as set in the GitHub request context. If the context doesn't
  # contain an actor, fallback to the ghost user.
  def actor
    @actor ||= (User.find_by_id(GitHub.context[:actor_id]) || User.ghost)
  end

  # Public: Adds the given email to the user's email collection.  If this is
  # the user's first email, make sure it becomes their primary email.
  #
  # email - String email address.
  #
  # Returns the (hopefully) created UserEmail...
  #   NOTE: It could be an invalid email that is not persisted!
  def add_email(email, options = {})
    options.reverse_merge! is_primary: false, actor: self,
      rebuild_contributions: true

    added = self.emails.build(email: email)
    # create an email as verified when EMU user is being provisioned
    added.state = "verified" if options[:verified] || self.provisioning_an_emu_user
    added.skip_reserved_domain = self.skip_reserved_domain

    if options[:is_primary] || emails.size == 1
      set_primary_email!(added) # also saves self, so will save the built user_email from that
    else
      GitHub.dogstats.increment "user", tags: ["action:add_email", "type:non_primary"]
      save
    end

    # Don't instrument when new users are validating on the signup form
    # Don't instrument invalid emails that won't be saved
    if !new_record? && valid?
      instrument :add_email, actor: options[:actor], email: email, note: email
      GitHub.dogstats.increment "contributions", tags: ["type:build_add_email"]
      unless self.feature_flag_enabled?(:skip_user_contribution_rebuild, default: false)
        rebuild_contributions(context: "user_add_email") if options[:rebuild_contributions]
      end

      GlobalInstrumenter.instrument "user.add_email", {
        user: self,
        actor: options[:actor],
        primary_email: primary_user_email,
        added_email: added,
      }

      return if options[:verified]
      # This is an unfortunate hack that is need to ensure tests pass. Tests
      # Do things technically impossible, i.e. deleting all email addresses,
      # causing errors in this code. We don't alert on actions taken by
      # users operating on other users' accounts (e.g. stafftools actions)
      if emails.size > 1 && self == options[:actor]
        AccountMailer.email_address_added(added).deliver_later
      end
    end

    added
  end

  # Public: Remove a given email from this user
  #
  # email - String email address
  # options - Hash of options
  #   actor - the User doing the removal; defaults to self
  #
  # Returns the UserEmail requested for deletion
  # Returns false if the removal fails
  def remove_email(email, options = {})
    errors.delete(:base)
    options.reverse_merge! actor: self

    to_remove = emails.find_by_email(email.to_s)
    unless to_remove
      errors.add :base, "Email not found."
      return false
    end
    if to_remove.last_email?
      errors.add :base, "Last email cannot be deleted."
      return false
    end

    if to_remove.sponsors_listing
      message = [
        "Cannot delete email because it is being used as your contact email for GitHub Sponsors.",
      ]

      if sponsors_listing.waitlisted?
        message << "Please change the email for your GitHub Sponsors waitlist application " \
          "and try again."
      else
        message << "Please change the email in your GitHub Sponsors settings and try again."
      end

      errors.add(:base, message.join(" "))
      return false
    end

    if primary_role = primary_user_email_role
      # If there is a primary role, wait for a lock on it to ensure the specified email is
      # safe to remove.
      primary_intact = primary_role.with_lock do
        if primary_role.email == to_remove
          new_primary = emails.notifiable.excluding_ids([to_remove, backup_user_email]).first
          unless new_primary
            if GitHub.email_verification_enabled?
              errors.add :base, "Cannot delete verified primary email without another verified email registered."
            else
              errors.add :base, "Cannot delete primary email without another email registered."
            end
            next false
          end

          status = set_primary_email(new_primary)
          unless status.success?
            errors.add :base, status.error
            next false
          end
        end

        # Ensure that the primary was successfully changed and/or the address we're removing
        # wasn't swapped in as primary unexpectedly.
        if primary_role.reload.email == to_remove
          errors.add :base, "Cannot delete primary email."
          next false
        else
          emails.destroy(to_remove)
        end

        to_remove.destroyed?
      end

      return false unless primary_intact
    else
      # If there is no primary role, then we can remove the email because it's not primary.
      emails.destroy(to_remove)
    end

    GitHub.newsies.get_and_update_settings(self) do |settings|
      settings.clear_unverified_emails(notifiable_emails, default_notification_email)
    end

    GlobalInstrumenter.instrument "user.remove_email", {
      user: self,
      actor: options[:actor],
      primary_email: primary_user_email,
      removed_email: to_remove,
    }

    payload = {
      email: to_remove.to_s,
      email_verified: to_remove.verified?,
      email_roles: options[:email_roles],
      actor: options[:actor],
      note: to_remove.to_s,
    }
    # Don't alert on actions taken on another's behalf (e.g. stafftools)
    if self == options[:actor]
      if options[:account_lockout]
        # email was removed as part of the email unlinking flow from 2FA lockout
        AccountMailer.email_address_unlinked(self, to_remove.to_s).deliver_later

        # annotate the audit log event to help support identify that this email was eligible for account recovery
        # prior to being unlinked.
        payload.merge!(options[:account_recovery_audit_metadata])
      else
        # email was removed as part of the normal user settings flow
        AccountMailer.email_address_removed(self, to_remove.to_s).deliver_later
      end
    end
    instrument(:remove_email, **payload)

    GitHub.dogstats.increment "user", tags: ["action:remove_email"]
    GitHub.dogstats.increment "contributions", tags: ["action:build_remove_email"]

    # If the user has commit contributions associated with this email, they should be removed. Since this
    # will only affect existing contributions, we can limit the rebuild to repos for which the user has
    # recorded contributions.
    rebuild_contributions(context: "user_remove_email", only_repos_with_contributions: true) unless options[:do_not_rebuild_contributions]

    to_remove.destroyed? ? to_remove : false
  end

  class NotificationServiceError < RuntimeError; end

  # Internal: Check if there are existing email roles
  #
  # Validations for roles run regardless of existing email roles,
  # and this will prevent those validations from running if empty
  def no_existing_email_roles?
    email_roles.count.zero?
  end

  # Public: Set the given UserEmail as the user's primary email address.
  #
  # email - The email address that should be used as the user's primary email address.
  #
  # Returns a SetPrimaryEmailStatus object, which can be asked about `success?` or `failure?`.
  def set_primary_email(email)
    previous_primary = primary_user_email
    set_primary_email_status = User::SetPrimaryEmailStatus::SUCCESS

    transaction do
      # When a user only wishes to have password resets sent to their primary
      # address, we track that by setting their backup to match their primary
      # email address. So, we need to update it if updating their primary
      # email. Because of how `password_reset_with_primary_email_only?` is
      # implemented, it is critical that we check
      # `password_reset_with_primary_email_only?` and call
      # `set_backup_email(email)` before updating the primary email role
      # below.
      set_backup_email(email) if password_reset_with_primary_email_only?
      # create an email role as hidden when EMU user is being provisioned
      primary_role = if self.provisioning_an_emu_user
        email.email_roles.build(role: "primary", user: self, public: false)
      else
        primary_user_email_role || email.email_roles.build(role: "primary", user: self)
      end
      primary_role.email = email
      cache_primary_email(email)

      unless new_record?
        GitHub.dogstats.increment "user_email", tags: ["action:save", "type:primary"]
        set_gravatar_email(email)

        [self, email, primary_role].each_with_index do |model, _index|
          unless model.save
            set_primary_email_status = User::SetPrimaryEmailStatus.new(invalid_model: model)
            raise ActiveRecord::Rollback
          end
        end
      end
    end

    if set_primary_email_status.success?
      send_signup_confirmation(new_email: email, old_email: previous_primary)
      reload_primary_user_email
    end

    set_primary_email_status
  end

  # Public: Set the given UserEmail as the user's primary email address, raising an error if the
  # operation fails.
  #
  # email - The email address that should be used as the user's primary email address.
  #
  # Returns the new primary UserEmail model.
  def set_primary_email!(email)
    status = set_primary_email(email)
    status.raise_on_error!
    primary_user_email
  end

  # Public: Set the Email's role to backup.
  #
  # email - The email address that should be used as the user's backup email
  # address.
  #
  # Returns the backup UserEmail.
  def set_backup_email(email)
    backup_role = backup_user_email_role ||
      email.email_roles.build(role: "backup", user: self)
    backup_role.email = email
    backup_role.save!
    GitHub.dogstats.increment "user_email", tags: ["action:save", "type:backup"]

    reload_backup_user_email
  end

  # Public: Clear any existing Email backup role. This results in our legacy
  # behavior of allowing all verified emails (if any are verified) to be used
  # password resets and all unverified emails for password resets if no emails
  # are verified.
  #
  # Returns nothing.
  def allow_password_reset_with_any_email
    backup_user_email_role.try(:destroy)
    reload_backup_user_email
    nil
  end

  # Public: Disables any backup email address. Only the primary email address
  # can be used for password resets once the backup email address is disabled.
  #
  # Note: This is implemented by setting the backup email to the user's
  # primary email address. This is kind of quirky, but it dramatically
  # simplifies the state necessary to implement such a feature without adding
  # additional state to the DB.
  #
  # Returns nothing.
  def allow_password_reset_with_primary_email_only
    set_backup_email(primary_user_email)
    nil
  end

  # Internal: Update the user's email address in MailChimp.
  # This method is also used for subscribing a user the first time.
  #
  # new_email - UserEmail
  # old_email - UserEmail. Must match what's stored in MailChimp.
  #
  # Returns true if job is enqueued, nil otherwise.
  def update_mailchimp_email(new_email:, old_email:)
    return unless GitHub.mailchimp_enabled?
    return unless old_email && new_email

    # Subscribe the new email being set as primary.
    MailchimpSubscribeJob.perform_later(new_email.id)

    # Only unsubscribe old email when changing primary emails;
    # for users verifying an email address for the first time,
    # the new_email and old_email will be the same.
    if new_email.email != old_email.email
      MailchimpUnsubscribeJob.perform_later(self.id, old_email.email)
    end
  end

  # Internal: Send a one-time welcome email to emails with a transactional
  # email preference set in order to confirm their signup.
  #
  # new_email - UserEmail
  # old_email - UserEmail.
  #
  # Returns true if job is enqueued, nil otherwise.
  def send_signup_confirmation(new_email:, old_email:)
    return unless GitHub.mailchimp_enabled?
    return unless old_email && new_email
    return if new_record?

    # The new_email and old_email will be the same for users verifying
    # an email address for the first time.
    if new_email.email == old_email.email
      UserSignupConfirmationJob.perform_later(new_email.id)
    end
  end

  # Public: Fixes an account which does not have a primary email set
  def repair_primary_email
    if has_primary_email?
      errors.add(:base, "primary email already set")
      return false
    end

    if emails.empty?
      errors.add(:base, "user has no emails set")
      return false
    end

    set_primary_email! emails.first
  end

  # Public: The email address to use to contact the user.
  #
  # Returns String
  def email_for_contact
    email.to_s
  end

  # Public: Returns a Set of notifiable String email addresses for this user.
  def notifiable_emails
    @notifiable_emails_set ||= all_notifiable_emails.map { |e| e.to_s.downcase }.to_set
  end

  # Public: get (and memoize) all the notifiable UserEmail's for this user.
  def all_notifiable_emails
    @user_notifiable_emails ||= emails.notifiable
  end

  # Internal
  def cache_primary_email(email)
    @primary_email = email.to_s
  end

  # Internal: The gravatar email defaults to their primary email. Fired via
  # before_save callback.
  #
  # We actually only want this to happen during creation, but
  # serialized_attributes get added to the data field during a before_save
  # callback and before_create gets called after that. If we called
  # set_initial_gravatar_email in a before_create callback, the gravatar_id
  # (set by #gravatar_email=) attribute wouldn't be persisted.
  #
  # TODO: This is terrible and should be refactored.
  def set_initial_gravatar_email
    return unless new_record?
    self.gravatar_email = email
  end

  # Internal: Default primary email to the first email. Fired via callback.
  #
  # NOTE: does NOT call set_primary_email -- probably not a good thing
  def set_initial_primary_email
    if email = emails.first
      cache_primary_email(email)
    end
    true
  end

  # Public: Set user's diff preference.
  #
  # view - :unified or :split Symbol
  #
  # Returns nothing.
  sig { params(view: Symbol).void }
  def set_diff_preference(view)
    raise ArgumentError, "unknown view type: #{view.inspect}" unless [:unified, :split].include?(view)
    new_split_preferred = (view == :split)

    if self.split_diff_preferred != new_split_preferred
      ActiveRecord::Base.connected_to(role: :writing) do
        update_column :split_diff_preferred, new_split_preferred
      end
      invalidate_cache("update_split_diff_preferred")
    end
  end

  def public_gists
    gists.active.are_public
  end

  def private_gists
    gists.active.are_secret
  end

  # can be passed login with tenant shortcode or not,
  # e.g. mtodd_ibm or mtodd
  def self.find_by_login(login)  # rubocop:disable GitHub/FindByDef
    ActiveRecord::Base.connected_to(role: :reading) do
      with_logins(login).first
    end
  end

  def self.tenant_namespacing_enabled?(tenant = GitHub::CurrentTenant.get)
    return false unless tenant.present?
    GitHub.multi_tenant_enterprise?
  end

  def self.unique_tenant_login?(login, tenant: GitHub::CurrentTenant.get)
    return true unless tenant_namespacing_enabled?(tenant)
    return true if login == GitHub.ghost_user_login
    return true if login == GitHub.staff_user_login
    return true if login == GitHub.trusted_oauth_apps_org_name
    return true if login == GitHub.proxima_third_party_apps_owner_login
    return true if login == "#{tenant.shortcode}_admin"

    login.end_with?("_#{tenant.shortcode}")
  end

  def self.to_display_login(login, tenant: GitHub::CurrentTenant.get)
    return login unless GitHub.multi_tenant_enterprise?
    return login if login.nil?
    return login if GitHub::CurrentTenant.stafftools_tenant?

    display_login, shortcode = login.split("_", 2)
    return login if shortcode.nil?
    return login if shortcode == ADMIN_SUFFIX
    return login unless shortcode.match(Business::SHORTCODE_REGEX)

    display_login
  end

  def self.find_by_login_or_email(login)  # rubocop:disable GitHub/FindByDef
    if login.nil?
      nil
    elsif login["@"]
      u = find_by_email(login)
      # if we're in a multi-tenant enterprise, and we weren't able to
      # find the user by email, try again formatting the email as the first enterprise owner
      if GitHub.multi_tenant_enterprise? && (current_tenant = GitHub::CurrentTenant.get)
        u ||= find_by_email(current_tenant.add_emu_shortcode_to_emails(login, first_enterprise_owner: true))
      end
      u
    else
      find_by_login(login)
    end
  end

  # Public: Takes a user or user identifier and returns the actual user object.
  #
  # user_or_identifier - The User or their login/email.
  #
  # Returns a User object or nil if no User exists.
  def self.reify(user_or_identifier)
    return user_or_identifier if user_or_identifier.is_a?(User)

    find_by_login_or_email(user_or_identifier)
  end

  has_many :staff_notes,     as: :notable
  has_many :own_staff_notes, class_name: "StaffNote"

  attr_accessor :password, :old_password, :destroying
  alias :being_destroyed? :destroying

  attr_writer :persistent_client_id

  # Public: Get a user-friendly error message about what's wrong with this User's login.
  #
  # Returns a String.
  def login_error_message
    login_errors = errors[:login].map do |error|
      if error == NOT_UNIQUE_LOGIN_MESSAGE
        "#{login.strip} #{error}" # repeat the duplicate login when saying it's already taken
      else
        error
      end
    end
    field_name = self.class.human_attribute_name(:login)
    "#{field_name} #{login_errors.join(". #{field_name} ")}."
  end

  # Public: Clear any AuthenticationLimits associated with this user's login.
  def clear_auth_limit
    AuthenticationLimit.clear_data(AuthenticationLimit.all_data_for_login(login))
  end

  # Public: Checks the login against:
  #
  # - A known list of reserved login keywords
  # - A known list of hardcoded logins we want to reserve, such as /blog or
  #   /explore (see config/initializers/denylist.rb)
  # - Other logins reserved by staff via https://admin.github.com/stafftools/reserved_logins
  # - Recently deleted accounts
  #
  # Returns boolean.
  def login_reserved?
    login_reserved_with_reason?[:reserved]
  end

  # Does the same check as login_reserved? but also returns the reason why the login is
  # reserved.
  #
  # Returns a hash with values:
  #
  # - :reserved true if the login is reserved, otherwise false
  # - :reason a symbol for why the login is or is not reserved
  def login_reserved_with_reason?
    ReservedLogin.reserved_with_reason?(
      login.downcase,
      persistent_client_id: @persistent_client_id,
      skip_keyword_check: (bot? || is_enterprise_managed? || (organization? && actor.present? && actor.employee?)),
    )
  end

  def to_param
    GitHub::CurrentTenant.stafftools_tenant? ? login : display_login
  end

  def to_s
    login
  end

  def to_i
    id
  end

  # This method exists so we could re-implement display_login with new behavior
  # and so all prior uses of display_login were ported over to call this method instead.
  #
  # See User subclasses for overrides of behavior.
  #
  # This method should not be used by new callers and should be eventually removed.
  # other options to use include: `user.login`, `user.display_login` or `bot.slug`
  def display_login_legacy
    display_login
  end

  def name
    login
  end

  # Validation: Ensures the login is not reserved.
  #
  # Returns nothing.
  def ensure_login_not_reserved
    return if login.blank?
    login_reserved = login_reserved_with_reason?

    if login_reserved[:reserved]
      if login_reserved[:reason] == :reserved_login_keyword
        errors.add(:login, :restricted_login_keyword, message: "'#{display_login}' contains a reserved keyword")
      else
        errors.add(:login, :login_unavailable, message: "'#{display_login}' is unavailable")
      end

      false
    end
  end

  # Validation: Ensures the uniqueness of the login with a faster query than
  # validates_uniqueness_of :login. It doesn't use LOWER(user.login).
  #
  # Returns nothing.
  def uniqueness_of_login
    return true unless will_save_change_to_login?

    if user = User.find_by_login(login)
      return if user == self
      errors.add(:login, NOT_UNIQUE_LOGIN_MESSAGE)
    end
  end

  # Validation: Ensures the uniqueness of the email by just trying to find a
  # user that loads with it.
  #
  # Returns nothing.
  def uniqueness_of_email
    if user = User.find_by_email(email)
      return if user == self
      errors.add(:email, :taken, message: "#{email} is already taken")
    end
  end

  # Validation: Ensures the domain of the email is not sanctioned
  #
  # Returns nothing.
  def email_not_sanctioned
    if ::TradeControls::Domains.sanctioned_email?(email)
      errors.add(:email, :sanctioned_email, message: ::TradeControls::Notices.notice_as_plaintext(:sanctioned_domain_warning))
    end
  end

  def email_not_disposable
    if UserEmail::DisposableEmailsDependency.disposable_email?(email)
      errors.add(:email, :disposable_email, message: UserEmail::VALIDATION_ERRORS[:generic_domain])
    end
  end

  # Validation: Prevents users from creating emails on reserved domains
  #
  # This is to support https://github.com/github/search-and-flywheel/issues/193
  #
  # Returns nothing.
  def email_domain_not_reserved
    if self.feature_flag_enabled?(:reserved_domain, default: false) && UserEmail::ReservedEmailDomainDependency.is_reserved_domain?(email)
      errors.add(:email,
        :reserved_domain,
        message: UserEmail::VALIDATION_ERRORS[:reserved_domain]
      )
    end
  end

  # Validation: Prevents users from being created for Enterprise installs
  # when there are no available seats.
  #
  # This is shown to the user, not the administrator. Direct users to contact
  # support.
  #
  # Returns nothing.
  def enforce_seat_limit(message = nil)
    return if !GitHub.enterprise? || !user? || login == GitHub.ghost_user_login
    if GitHub::Enterprise.license.reached_seat_limit?
      errors.add :base,
        message ? message : "Could not create your account. Contact your system administrator."
    end
  end

  def self.with_oauth_token(token)
    return if token.blank?
    with_oauth_hashed_token(OauthAccessTokens::Domain.hash_token(token))
  end

  def self.with_oauth_hashed_token(hashed_token)
    return if hashed_token.blank?

    if (access = OauthAccessTokens.domain.active(hashed_token, hashed: true))
      return if !access.personal_access_token? && access.application.nil?

      if (user = access.user) && user.can_authenticate_via_oauth?
        access.bump
        user.oauth_access = access
        user.set_scopes(access)
        user.oauth_application_id = access.application_id
        user
      end
    end
  end

  # Internal: set the current oauth access scopes on the User
  # for cases when oauth scopes will be used for permission checks.
  #
  # access - An OauthAccess
  def set_scopes(access)
    unless access.application.is_a? Integration
      self.scopes = access.access_level
    end
  end

  # Attempts to fetch a group of logins in a single query round trip.
  #
  # logins - An Array of String logins.
  #
  # Returns an Array of User objects.
  def self.with_logins(*logins)
    valid_logins = logins.flatten.filter_map do |login|
      login = login.to_s
      # login.present? will throw if login is not valid UTF-8, so use login.empty? here instead.
      login if !login.empty? && GitHub::UTF8.valid_unicode3?(login)
    end

    if FeatureFlag.vexi.enabled?(:owner_scoped_github_apps, default: false)
      slugs, logins = valid_logins.partition { |login| login.ends_with?(Bot::LOGIN_SUFFIX) }

      # default scope on User appends `business_id: tenant_id`
      query_scope = where(login: logins)
      return query_scope if slugs.empty?

      # Bot.ids_for_slugs queries the `integrations` table to find the
      # appropriate bot ids for the given slugs.
      bot_ids = Bot.ids_for_slugs(slugs)
      return query_scope if bot_ids.empty?

      query_scope.or(User.where(id: bot_ids))
    else
      where(login: valid_logins)
    end
  end

  # Public: Retrieve this User's popular repositories, based on
  # stargazer count.
  #
  # Returns an Array of Repositories
  def popular_repositories
    PopularRepositories.new(self).repositories
  end

  def repository_counts_class
    UserRepositoryCounts
  end

  batch_method(:public_repository_count) do |users|
    user_ids = users.map(&:id)

    public_repositories_hash = users.first.public_repositories.where_values_hash.merge(owner_id: user_ids)
    public_repositories_count = Repository.where(public_repositories_hash).limit(MEGA_USER_REPOS_THRESHOLD).group(:owner_id).count

    users.index_with { |user| public_repositories_count[user.id] || 0 }
  end

  batch_method(:repository_counts) do |users|
    # If there is only one user being returned, prefilling the associations
    # will result in more queries than it would take to determine the counts
    # through normal means.
    if users.one?
      user = users.first
      next({ user => user.repository_counts_class.new(user) })
    end

    user_ids = users.map(&:id)

    public_repositories_hash = users.first.public_repositories.where_values_hash.merge(owner_id: user_ids)
    public_repositories_count = Repository.where(public_repositories_hash).group(:owner_id).count

    private_repositories_hash = users.first.private_repositories.where_values_hash.merge(owner_id: user_ids)
    private_repositories_count = if users.first.organization?
      # Internal and advisory workspace repos will be counted among an org's private repos unless we explicitly exclude them.
      biz_ids = Business::OrganizationMembership.where("organization_id IN (?)", user_ids).pluck(:business_id)
      workspace_repo_ids = RepositoryAdvisory.where(owner_id: user_ids).where.not(workspace_repository_id: nil).pluck(:workspace_repository_id)
      private_repositories = Repository.where(private_repositories_hash).without_ids(InternalRepository.select(:repository_id).where(business_id: biz_ids))
      private_repositories = private_repositories.without_ids(workspace_repo_ids) if workspace_repo_ids.any?
      private_repositories.group(:owner_id).count
    else
      # Individuals cannot own internal or advisory workspace repos so we need not exclude them from user counts.
      Repository.where(private_repositories_hash).group(:owner_id).count
    end

    owned_private_repositories_hash = users.first.owned_private_repositories.where_values_hash.merge(owner_id: user_ids)
    owned_private_repositories_count = Repository.where(owned_private_repositories_hash).group(:owner_id).count

    public_gists_count = Gist.where(public: true, user_id: user_ids).active.group(:user_id).count
    private_gists_count = Gist.where(public: false, user_id: user_ids).active.group(:user_id).count

    users.index_with do |user|
      user.repository_counts_class.new(
        user,
        public_repositories: public_repositories_count[user.id] || 0,
        private_repositories: private_repositories_count[user.id] || 0,
        owned_private_repositories: owned_private_repositories_count[user.id] || 0,
        public_gists: public_gists_count[user.id] || 0,
        private_gists: private_gists_count[user.id] || 0,
      )
    end
  end

  # Unpublishes Pages on any private repos the user owns
  def unpublish_private_pages
    owned_private_repositories.each(&:unpublish_page)
  end

  # Does the user have more collaborators on private repos than allowed on free
  def over_repo_seat_limit?
    return false if organization?
    owned_private_repositories.any? do |repo|
      repo.filled_seats >
        GitHub::Plan.free.limit(:collaborators, visibility: :private, feature_flag: plan_override_feature_flag)
    end
  end

  def reset_private_protected_branches
    if !plan_supports?(:protected_branches, visibility: :private)
      owned_private_repositories.map(&:destroy_protected_branches)
    end
  end

  def reset_private_protected_tags
    if !plan_supports?(:protected_tags, visibility: :private)
      owned_private_repositories.map { |repo| repo.tag_protection_states.destroy_all }
    end
  end

  def valid_login?(username)
    if username["@"]
      emails.find_by_email(username).present?
    else
      standardized = User.standardize_login(username)
      standardized.downcase == login.downcase
    end
  end

  # Convert an invalid login to a valid login. This is used to handle OmniAuth
  # logins, which can be a variety of Strings: things with special characters,
  # email addresses, and so on. Email addresses get their domain chopped off
  # the end.
  #
  # login - the possibly-invalid String login
  #
  # Returns a valid String.
  def self.standardize_login(login, suffix: nil)
    login = login.split("\\").last # Windows Domains
    login = login.split("@").first # email addresses
    login = login.gsub(/[^a-z0-9-]/i, "-")

    login = login + ENTERPRISE_MANAGED_USER_LOGIN_SEPARATOR + suffix if suffix.present?

    login
  end

  # Returns a new unpersisted User object with a random password.
  #
  # login - String representing the login for the new user
  # site_admin - Boolean indicating whether the new user should be a site admin
  # default_opts - Hash of params to provide when creating the User object
  #
  # Returns User.
  def self.new_with_random_password(login, site_admin = GitHub.enterprise_first_run?, default_opts = {})
    suffix = default_opts["login_suffix"] if default_opts["force_enterprise_managed"]
    clean_login = standardize_login(login, suffix: suffix) unless login.blank?

    password = SecureRandom.hex(32)

    options = {
      raw_login: login,
      login: clean_login,
      password: password,
      password_confirmation: password,
    }

    options.merge!(default_opts)
    options[:gh_role] = "staff" if site_admin

    new(options)
  end

  # Creates a new User with a random password. Used by external authentication
  # to create users that do not use the github password field.
  #
  # login - String representing the login for the new user
  # site_admin - Boolean indicating whether the new user should be a site admin
  # default_opts - Hash of params to provide when creating the User object
  #
  # Returns a User object whether or not the user was successfully created.
  # Callers should check #valid? on the returned object.
  def self.create_with_random_password(login, site_admin = GitHub.enterprise_first_run?, default_opts = {})
    new_with_random_password(login, site_admin, default_opts).tap(&:save)
  end

  # Public: Log out all of the users sessions, including the current one.
  #
  # Do this when the user changes their password.
  #
  # reason - Why user is being logged out.
  #          See UserSession:VALID_REVOKE_REASONS for valid keys.
  #
  # Returns Array of revoked UserSessions.
  def revoke_active_sessions(reason)
    self.sessions.unrevoked.active.map do |session|
      # if necessary, devices will already be unverified prior to session
      # revocation.
      session.revoke(reason, unverify_device: false)
    end
  end

  # Public: Determine if the user has exceeded the active session limit.
  #
  # Returns true if the active session count exceeds the limit.
  def over_active_session_limit?
    sessions.user_facing.count > UserSession::LIMIT
  end

  # Public: Determine if the user has exceeded the active session limit.
  #
  # Returns true if the active session count exceeds the limit.
  def enforce_active_session_limit?
    return false unless GitHub.active_session_limit_enabled?
    sessions.user_facing.count > UserSession::LIMIT_ENFORCEMENT_THRESHOLD
  end

  # Public: Sets the protocol preference for this user.
  #
  # type     - String protocol name.
  # protocol - String protocol type.
  #
  #   user.set_protocol_preference "push", "ssh"
  #
  # Returns nothing.
  def set_protocol_preference(type, protocol)
    if !(protocols && protocols[type] == protocol)
      self.protocols = (protocols || {}).update(type => protocol)
    end
  end

  # Checks if any of the paid Organizations this user owns have been locked
  #
  # Returns a Boolean
  def disabled_orgs?
    disabled_orgs.present?
  end

  def disabled_org?(org:)
    disabled_orgs.where(id: org).any?
  end

  def set_disabled_personal_billing_notice
    return unless disabled? && paid_plan?

    Billing::DisabledPersonalBillingCheckJob.perform_later(self)
  end

  # Does this User own an Organization that is missing a billing_email?
  # Returns a Boolean.
  def owns_billingless_org?
    !!billingless_org
  end

  # Organization#billing_email is required, but some orgs don't have one.
  #
  # This method finds Organizations that are:
  #  1. on a paid plan
  #  2. blank billing_email
  #  3. owned by this User
  #
  # Returns the Organization if one is found, or nil if not.
  def billingless_org
    return @billingless_org if defined?(@billingless_org)
    @billingless_org = if billingless_org_id.present?
      org = Organization.find_by_id(billingless_org_id)

      # check that it's still missing the email
      org if org && org.billing_email.blank?
    end
  end

  # Cached version of `billingless_org_id!`
  def billingless_org_id
    GitHub.cache.fetch("#{cache_key}:billingless_org_id", stats_key: "user.caching.ns-billingless-org-id") do
      billingless_org_id!
    end
  end

  # Caches an Organization ID for the `billingless_org` method.
  # Returns an Integer ID of an Organization if we found one.
  # Returns nil otherwise.
  def billingless_org_id!
    org = owned_organizations.without_billing_email.on_paid_plan.first
    if org
      @billingless_org = org
      org.id
    end
  end

  # Organization#billing_email is required, but some orgs don't have one.
  #
  # Returns the Boolean if org is billingless
  def billingless_org?(org:)
    org.billing_email.blank? && org.paid_plan?
  end

  # User has no external billing emails, overridden in Organization.
  def billing_external_emails
    BillingExternalEmail.none
  end

  def path
    to_s
  end

  # The full author name used in git operations.
  #
  # First we attempt to use the safe profile name, and if
  # that does not have a value after stripping illegal
  # characters we use the login.
  #
  # Returns an author name String.
  def git_author_name
    author_name = strip_illegal_git_chars(safe_profile_name)
    author_name.blank? ? login : author_name
  end

  # Public: Returns true if the user has a primary email set.
  def has_primary_email?
    !!primary_user_email
  end

  # Public: Returns true if the user has a backup email set.
  def has_backup_email?
    !!backup_user_email
  end

  # Public: Determines if the user has disabled backup emails.
  #
  # Note: This is implemented by setting the backup email to the user's
  # primary email address. This is kind of quirky, but it dramatically
  # simplifies the state necessary to implement such a feature without adding
  # additional state to the DB.
  #
  # Returns true if the user has backup emails disabled.
  def password_reset_with_primary_email_only?
    has_backup_email? && backup_user_email == primary_user_email
  end

  # Public: The email address to attribute in git operations performed by this user.
  #
  # Returns a String e-mail address
  def git_author_email
    author_email = strip_illegal_git_chars(outbound_email)
    author_email.blank? ? anonymous_user_email : author_email
  end

  # Public: A fully anonymous email for the user with a noreply mask
  # on the current GitHub domain
  #
  # Returns a String e-mail address
  def anonymous_user_email
    (stealth_email || StealthEmail.new(self)).email
  end
  alias stealth_email_string anonymous_user_email

  # Internal: strip illegal git-author characters,
  # ensuring that the username contains at least one
  # printable character
  #
  # Angle brackets and LF are invalid as part of git author info. CR
  # might be tolerated, but why play with fire?
  #
  # Returns a String or nil
  def strip_illegal_git_chars(author)
    author && author.match(/[[:word:]]/) && author.tr("<>\n\r", "")
  end

  # Public: The URL for this user on thehub org chart, if this user is a GitHub
  #         employee.
  #
  # Returns a String|nil.
  def thehub_url
    "https://thehub.github.com/org?login=#{login}" if employee?
  end

  # Public: Does this user want to use their stealth user email
  # for stuff done via the web UI?
  # Returns Boolean
  def use_stealth_email?
    primary_private_user_email.present?
  end

  # Internal: return user's stealth email
  #
  # Returns a UserEmail
  def stealth_email
    stealth_user_email
  end
  private :stealth_email

  # Internal: is the user's profile_email "trusted" ?
  #  We defined 'trusted' as an email that the User **also** added to their list of
  #  "private" emails associated with their accounts (i.e. UserEmail)
  #
  # Returns Boolean
  def trusted_profile_email?
    profile_email.present? && emails.exists?(email: profile_email)
  end

  # Should pages owned by this user be regarded as "Official GitHub properties" ?
  def github_owned_pages?
    GitHub.github_owned_pages.include?(login)
  end

  # Public: Returns the GitHub pages hostname for this user
  #
  # For v2 users, this is github.io.  For everyone else, it is github.com.
  # Other models, like Page and Repository, should go through this method
  # for their Pages host name to ensure things work right depending on the feature
  # flag for the Pages migration.
  def pages_host_name
    if github_owned_pages?
      GitHub.pages_host_name_v1
    else
      GitHub.pages_host_name_v2
    end
  end

  # This user's "user pages repo", e.g. defunkt/defunkt.github.com
  # Returns a Repository if one is found, nil otherwise.
  def user_pages_repo
    async_user_pages_repo.sync
  end

  def async_user_pages_repo
    return @async_user_pages_repo if defined?(@async_user_pages_repo)

    @async_user_pages_repo = Platform::Loaders::RepositoryByName.load_all(id, [
      "#{login}.#{GitHub.pages_host_name_v2}",
      "#{login}.#{GitHub.pages_host_name_v1}",
    ]).then do |repo_v2, repo_v1|
      Promise.all([
        repo_v2&.async_is_user_pages_repo?,
        repo_v1&.async_is_user_pages_repo?,
      ]).then do |v2_is_user_page, v1_is_user_page|
        next repo_v2 if v2_is_user_page
        next repo_v1 if v1_is_user_page
        nil
      end
    end
  end

  # Destroy the User asynchronously.
  #
  # actor - User attempting the deletion.
  # skip_permitted_check - Boolean indicating whether to skip the check
  #   as to whether the deletion is permitted. Defaults to false.
  # site_admin_deletion - Boolean indicating whether the deletion was
  #   performed by a site admin. Defaults to false.
  #
  # Returns nothing.
  def async_destroy(actor = nil, skip_permitted_check: false, site_admin_deletion: false)
    return if !skip_permitted_check && !permit_deletion?(actor)

    # Set the "staff_delete" role when we don't want to send an email notification
    update_attribute :gh_role, "staff_delete" if site_admin_deletion

    self.deleted_at = Time.now
    self.deleted_by = actor.display_login if actor
    self.deleted = true
    self.skip_sanctioned_billing_emails_validation = true

    save!

    instrument :async_delete if instrument_async_delete?

    if delay_deletion_for_spam_checks?
      UserDeleteJob.set(wait: User::SpamDependency::DELETION_DELAY).perform_later(id, login)
    else
      UserDeleteJob.perform_later(id, login)
    end

    delete_type = if actor.nil?
      :UNKNOWN
    else
      actor == self ? :SELF : :OTHER
    end

    GlobalInstrumenter.instrument "user.destroy", {
      user: self,
      actor: actor,
      delete_type: delete_type,
      actor_was_staff: actor&.site_admin?,
      email: primary_user_email,
    }

    # Non-User subclasses call this method. Only count real User deletes.
    GitHub.dogstats.increment("user", tags: ["action:destroy"]) if user?
  end

  # Public: Mark a "deleted" user as "not deleted".
  #
  # To be used when deletion fails and a user is left in a "deleted" state
  # and should be marked as "not deleted" to allow deletion to occur again.
  #
  # Returns Boolean.
  def mark_not_deleted(actor: nil)
    return unless deleted?

    self.deleted_at = nil
    self.deleted_by = nil
    self.deleted = false

    saved = save(validate: false)

    if saved
      if status = UserDeleteJob.status(self.id)
        status.destroy
      end

      GitHub.instrument "staff.mark_user_not_deleted", user: self
    end

    saved
  end

  # Special ghost user used as a fallback for various issues-related records.
  #
  # Returns a User.
  def self.ghost
    return @ghost if @ghost
    # There is only one ghost created
    @ghost = User.unscoped.find_by_login(GitHub.ghost_user_login)
  end

  # Is this the ghost user?
  #
  # Returns a Boolean.
  def ghost?
    login == GitHub.ghost_user_login
  end

  # Users can't use organization secrets.
  def can_use_org_secrets?
    false
  end

  # Users are users.
  def organization?
    false
  end

  # Users are users.
  def user?
    true
  end

  def business?
    false
  end

  # Users are users.
  def mannequin?
    false
  end

  # Users are users.
  def bot?
    false
  end

  # Users cannot be archived
  def archived?
    false
  end

  # Special staff user used as an actor for staff actions
  # so we can use this for the actor and move the staff
  # user into a new special field to help prevent staff
  # identities from becoming public
  #
  # Returns github staff account
  def self.staff_user
    return @staff_user if @staff_user
    @staff_user = User.unscoped.find_by_login(GitHub.staff_user_login) || User.create_staff_user
  end

  def staff_user?
    login == GitHub.staff_user_login
  end

  # Is this a system account that is important for the application to function
  # properly?
  #
  # System users include the @ghost and @github-staff users, as well as the
  # "trusted_oauth_apps_owner" organization (@github on .com and
  # @github-enterprise on Enterprise).
  #
  # Returns a Boolean.
  def system_account?
    ghost? || staff_user? || (organization? && trusted_oauth_apps_owner?)
  end

  # Creates the ghost user if it doesn't already exist.
  def self.create_ghost
    password = SecureRandom.hex

    @ghost = User.where(login: GitHub.ghost_user_login).first_or_initialize(
      login: GitHub.ghost_user_login,
      email: "ghost@github.com",
      plan: GitHub::Plan.find("free").name,
      password: password,
      password_confirmation: password,
    )

    @ghost.save!
    @ghost.disable_all_notifications
    @ghost
  rescue Exception => e # rubocop:todo Lint/RescueException
    warn "failed to create ghost user: #{e.class.inspect}: #{e.message.inspect}"
  end

  # Creates the staff user if it doesn't already exist.
  def self.create_staff_user
    unless GitHub.guard_audit_log_staff_actor?
      raise "staff actor should not be created if not used for auditing"
    end

    @staff_user = User.unscoped.find_by_login(GitHub.staff_user_login)

    password = SecureRandom.hex

    ActiveRecord::Base.connected_to(role: :writing) do
      @staff_user ||= User.create(
        login: GitHub.staff_user_login,
        email: "#{GitHub.staff_user_login}@github.com",
        plan: GitHub::Plan.find("free").name,
        password: password,
        password_confirmation: password,
      )

      @staff_user.save!
      @staff_user.disable_all_notifications
      @staff_user
    end
  end

  # Find the deploy keys for repositories this user is an admin of.
  # That'll be any repos the user owns and any repos in teams the user
  # has "Admin" access to.
  #
  # Returns an Array of PublicKey instances.
  def deploy_keys
    @deploy_keys ||= deploy_keys!
  end

  def deploy_keys!
    # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
    adminable_repo_ids = associated_repository_ids(min_action: :admin)
    # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
    PublicKey.where("repository_id IN (?)", adminable_repo_ids)
  end

  def public_keys=(new_keys)
    new_keys = [new_keys].flatten.reject(&:blank?)

    public_keys.to_a.dup.each do |key|
      public_keys.delete(key) unless new_keys.include? key.to_s
      new_keys.delete(key.to_s)
    end

    new_keys.each do |key|
      add_public_key(key)
    end
  end

  def add_public_key(key, title = nil)
    pub_key = PublicKey.new key: key.to_s
    pub_key.user = self
    public_keys << pub_key
  end

  # Public: can the actor view the user?
  def readable_by?(actor)
    return super if self.organization?
    self == actor
  end

  # Checks to see if the actor has the appropriate permissions
  # to restore a deleted repository
  def can_restore_repository?(actor)
    organization? ? adminable_by?(actor) : actor == self
  end

  # language - the Linguist::Language to find the top repo in that language.
  def most_popular_repository_for(language)
    default_alias = language.default_alias unless language.is_a?(String)
    language_id = nil

    if default_alias && language_name = LanguageName.find_by_alias(default_alias)
      language_id = language_name.id
    end

    public_repos_scope = public_repositories
    if language_id || language == "Unknown"
      public_repos_scope = public_repos_scope.where(primary_language_name_id: language_id)
    end

    public_repos_scope.limit(1).order("#{Repository.stargazer_count_column} DESC").first
  end

  # Find users with logins matching a specific term.
  #
  # Params:
  #
  #    term - The string to search for
  #    options - Options Hash with Symbol keys:
  #    :limit - Max # of results
  #    :friends - Array of users to prefer in the results.
  #    :prepend_friends - Place preferred friends in the front or the back of the results. Defaults to true.
  #    :org - Organization to prefer members from in the results.
  #           If supplied with :org and the org is enterprise managed, filters users to return only users in the scope of the org.business.
  #    :with_orgs - Whether to include orgs. Default: false
  #    :org_member_scope - If supplied with :org, filters users to return only public or all members of an organization, Default: nil
  #    :include_business_orgs - If supplied with :org and :org_member_scope, filters users to return only members of the business, Default: false
  #    :exclude_suspended - Whether to exclude suspended users. Default: false
  #    :business - If supplied with :business and the business is enterprise managed, filters users to return only users in the same business.
  #
  # Returns an Array of Users.
  def self.search(term, options = {})
    limit = (options[:limit] || 30).to_i
    friends = options[:friends] || []
    prepend_friends = options[:prepend_friends].nil? ? true : options[:prepend_friends]
    org = options[:org]
    org_member_scope = options[:org_member_scope]
    include_business_orgs = options[:include_business_orgs]
    with_orgs = options[:with_orgs].nil? ? false : options[:with_orgs]
    exclude_suspended = options[:exclude_suspended].nil? ? false : options[:exclude_suspended]
    business = options[:business]

    if term.to_s.index("@")
      users = User.includes(:profile)
                  .where(spammy: false)
                  .with_prefix("profiles.email", term)
                  .references(:profile)
                  .limit(limit)
      users = users.where(suspended_at: nil) if exclude_suspended

      # check both the business and the org since they're both optional parameters
      if business&.enterprise_managed_user_enabled? || org&.enterprise_managed_user_enabled?
        business_id = business&.id || org&.business.id

        users = users.select do |user|
          if user.is_a?(Organization)
            user.business&.id == business_id
          else
            enterprise_managed_business = user.enterprise_managed_business
            !enterprise_managed_business.nil? && enterprise_managed_business.id == business_id
          end
        end
      else
        users = users.select do |user|
          if user.is_a?(Organization)
            !user.enterprise_managed_user_enabled?
          else
            !user.is_enterprise_managed?
          end
        end
      end

      users = users.to_a
    elsif term.present? # query is invalid if no term to search
      users = if org.present?
        user_query(term, limit: limit, org: org, org_member_scope: org_member_scope, include_business_orgs: include_business_orgs, exclude_suspended: exclude_suspended, business: business)
      else
        user_query(term, limit: limit, friends: friends, exclude_suspended: exclude_suspended, business: business)
      end
    else
      users = []
    end

    if prepend_friends
      users.unshift(*Array(friends).
        select { |friend| friend.login =~ /\A#{Regexp.quote(term.to_s)}/ })
    else
      users.append(*Array(friends).
        select { |friend| friend.login =~ /\A#{Regexp.quote(term.to_s)}/ })
    end

    users.uniq!
    users.compact!

    # Only want real users, unless including organizations
    if with_orgs
      users.select! { |u| u.user? || (u.organization? && u.active?) }
    else
      users.select!(&:user?)
    end

    users.first(limit)
  end

  # Search for users in ES directly. No search by email or
  # other features of `User.search.`
  #
  #  term - String term to search for.
  #  limit - Integer limit.
  #  friends - Array of users to prefer in the results.
  #  org - Organization to give preference to members.
  #  org_member_scope - If supplied with org, filters users to return public or all members of an organization
  #  include_business_orgs - If supplied with org and org_member_scope, filters users to return only members of the business
  #
  # Returns an Array of Users.
  def self.user_query(term, friends: [], limit: 30, org: nil, org_member_scope: nil, include_business_orgs: false, exclude_suspended: false, business: nil)
    query = Search::Queries::UserLoginQuery.new(
      phrase: term,
      per_page: limit,
      source_fields: false,
      friends: friends,
      org: org,
      org_member_scope: org_member_scope,
      include_business_orgs: include_business_orgs,
      exclude_suspended: exclude_suspended,
      business: business,
    )
    query.execute.results.map { |h| h["_model"] }
  end

  def valid_rename?(new_login, actor:)
    return false if renaming?

    if archived?
      errors.add(:base, "This organization cannot be renamed because it is archived.")
      return false
    end

    old_login = login.dup

    self.login = new_login
    new_login_valid = valid?
    self.login = old_login
    return false unless new_login_valid

    if system_account?
      errors.add(:base, "System accounts cannot be renamed.")
      return false
    end

    if new_login == old_login
      errors.add(:login, "must be different.")
      return false
    end

    if self.spammy?
      GitHub::SpamChecker.notify("Spammy user #{id} renaming from #{old_login} to #{new_login}. https://admin.github.com/stafftools/audit_log?query=webevents+%7C+where+user_id+%3D%3D+#{id}")
      mark_login_as_used
    end

    repos = repositories.pluck(:name).map(&:to_s)
    clashing_namespaces = RetiredNamespace.where(
      owner_login: new_login,
      name: repos
    ).where("owner_id IS NULL OR owner_id != ?", id)

    if clashing_namespaces.any?
      errors.add(:login, "change was not successful. The repository name #{new_login}/#{clashing_namespaces.first.name} has been retired and cannot be reused")
      return false
    end

    packages_clash_resp = clashing_packages_namespace(new_login)

    if packages_clash_resp[:error] != nil
      errors.add(:login, "change was not successful.")
      return false
    end
    if packages_clash_resp[:clashing_packages_namespace] != nil
      errors.add(:login, "change was not successful. The package name #{new_login}/#{packages_clash_resp[:clashing_packages_namespace]} has been retired and cannot be reused")
      return false
    end

    if Repositories::RepositoryOwnerLock.locked_for_rename?(owner_id: self.id)
      # There is another change happening concurrently, either to a repo owned by this user or the username itself,
      # so we should set an error message to display.
      errors.add(:login, "change was not successful. Please try again later.")
      return false
    end

    new_login_valid
  end

  # Destructive! Renames a user asynchronously.
  # Check `renaming?` to see if a rename is in progress.
  #
  # new_login - String new login for the user.
  # actor - The user account making the change.
  #         Spammy users can rename their accounts only if staff allows it.
  # allow_rename - if present it will override the blocking of the updates to user_login for EMU
  #
  # Returns a Boolean indicating whether the rename started or not.
  #   If false there was either a Validation error or
  #   a rename is already in progress.
  def rename(new_login, actor: self, allow_rename: false, rename_reason: nil, rename_notes: nil)
    return false if spammy? && !spammy_renaming_overridden? && !actor.site_admin?
    return false if !allow_rename && scim_managed_user?

    if valid_rename?(new_login, actor: actor)
      update_attribute(:renaming, true)
      serialized_request_context = Hydro::EntitySerializer.request_context(GitHub.context.to_hash)
      serialized_spamurai_form_signals = Hydro::EntitySerializer.spamurai_form_signals(GitHub.context[:spamurai_form_signals])
      UserRenameJob.perform_later(
        self,
        new_login,
        actor,
        serialized_request_context,
        serialized_spamurai_form_signals,
        rename_reason,
        rename_notes
      )
      true
    else
      false
    end
  end

  # Destructive! Renames a user synchronously.
  # Call it from a background job.
  #
  # new_login - String new login for the user.
  # actor - The user account making the change.
  # Spammy users can rename their accounts only if staff allows it.
  #
  # Returns nothing.
  def rename!(new_login, actor: self, serialized_request_context: nil, serialized_spamurai_form_signals: nil, rename_reason: nil, rename_notes: nil)
    # Note that RepositoryOwnerLock.with_rename_lock will _not_ run the given block
    # if the lock is already set for the given user. It'll just return `false` without
    # raising an error of any kind.
    Repositories::RepositoryOwnerLock.with_rename_lock!(owner_id: self.id) do
      return false if spammy? && !spammy_renaming_overridden? && !actor.site_admin?
      return false if archived?

      # check clashing namespace again in case of race condition
      repos = repositories.pluck(:name).map(&:to_s)
      clashing_namespaces = RetiredNamespace.where(
        owner_login: new_login,
        name: repos
      ).where("owner_id IS NULL OR owner_id != ?", id)

      if clashing_namespaces.any?
        return false
      end

      old_login = login.dup
      old_display_login = display_login.dup

      self.login = new_login
      new_display_login = display_login.dup

      # Test that changing the login works.
      if !valid?
        self.login = old_login
        update_attribute(:renaming, nil)
        instrument :rename_failed, old_login: old_display_login, new_login: new_display_login
        return false
      end

      StealthEmail.new(self).rename!(new_login) if stealth_email

      # Do it.
      update! \
        login: new_login,
        renamed_at: Time.now

      GlobalInstrumenter.instrument "account.rename", {
        actor: actor,
        account: self,
        previous_login: old_login,
        current_login: new_login,
        serialized_request_context: serialized_request_context,
        serialized_spamurai_form_signals: serialized_spamurai_form_signals,
        rename_reason: rename_reason,
        rename_notes: rename_notes,
      }

      # The rename method is shared between User and Org. Sometimes User relies
      # on the actor being the user that is being renamed.
      if self.organization?
        instrument :rename, old_login: old_display_login, actor: actor, rename_reason: rename_reason, rename_notes: rename_notes
      else
        instrument :rename, old_login: old_display_login, rename_reason: rename_reason, rename_notes: rename_notes
      end

      # Update associated records.
      public_keys.reload.each(&:save)
      update_repos_after_rename(old_login, new_login)
      update_sponsors_listing_slug(new_login)
    end
  ensure
    # Unlock rename.
    update_attribute(:renaming, nil)
  end

  def disk_usage
    repositories.where(parent_id: nil).sum(:disk_usage) || 0
  end

  # Destructive! Destroys all reactions associated with this user.
  def destroy_reactions
    # first destroys legacy reactions
    Reaction.where(user_id: id).destroy_all
    # then destroys reactions that have been extracted into specific reaction tables
    commit_comment_reactions.destroy_all
    discussion_reactions.destroy_all
    discussion_comment_reactions.destroy_all
    issue_comment_reactions.destroy_all
    issue_reactions.destroy_all
    pull_request_review_comment_reactions.destroy_all
    pull_request_review_reactions.destroy_all
  end

  # Public: Find a repository owned by this user
  #
  # name - the repo name
  # strict_loading - whether to use strict loading for associations
  # includes - an array of symbols corresponding to model associations in the repositories cluster e.g. [:network, :mirror]
  #
  # Returns a Repository or nil
  def find_repo_by_name(name, strict_loading: false, includes: nil)
    return nil unless name && GitHub::UTF8.valid_unicode3?(name.to_s)

    repos = repositories
    repos = repos.includes(*includes) if includes&.any?
    repos = repos.strict_loading      if strict_loading

    repos.where(name: name.to_s).first.tap do |repo|
      if repo && organization? && repo.organization_id == id
        GitHub::PrefillAssociations.prefill_associations(repo, :organization, available_records: [self])
      end
    end
  end

  def notifications?
    wants_email?
  end

  def collaborators_count
    repo_ids = Repository.private_scope.active.unlocked_repos.network_roots.where(owner_id: id).pluck(:id)

    # We force the index here because the optimizer can choose a full index scan to handle the COUNT(DISTINCT) query
    # See https://github.com/github/authorization/issues/3418 for background
    Ability.from("abilities FORCE INDEX(subject_and_actor_and_priority_and_action)").batched_scope(:subject_id, values: repo_ids) do |scope|
      scope
        .where(subject_type: "Repository", actor_type: "User", priority: Ability.priorities[:direct])
        .distinct
    end.pluck(:actor_id).uniq.size
  end

  def owned_advisory_workspace_repositories
    workspace_repo_ids = RepositoryAdvisory.where(owner_id: id).where.not(workspace_repository_id: nil).pluck(:workspace_repository_id)
    owned_private_repositories.where(id: workspace_repo_ids).from("`#{Repository.table_name}` FORCE INDEX (PRIMARY)")
  end

  def private_repo_count_for_limit_check
    return @private_repo_count_for_limit_check if defined?(@private_repo_count_for_limit_check)
    count = owned_private_repositories.size
    if count == 0
      @private_repo_count_for_limit_check = count
    else
      @private_repo_count_for_limit_check = count - owned_advisory_workspace_repositories.size
    end
  end

  def at_private_repo_limit?
    return false if has_unlimited_private_repositories?
    private_repo_count_for_limit_check >= plan_limit(:repos, visibility: :private)
  end

  def can_add_private_repo?
    plan_supports?(:repos, visibility: :private) && !at_private_repo_limit?
  end

  # Check if the user is on a plan with private repositories and if they're on
  # a plan with private repositories, check if they've reached the limit
  #
  # Returns a Boolean.
  def at_plan_repo_limit?
    plan_supports?(:repos, visibility: :private) && at_private_repo_limit?
  end

  # Is the default visibility for repositories owned by users private?
  #
  # On Enterprise Server, honor the default repository visibility setting
  # for the installation. Otherwise, check if the user has any active
  # external identity sessions and default to private if yes, in order to
  # lower the risk of IP code leakage.
  # See https://github.com/github/github/issues/144149 for more info.
  #
  # This method is overridden in Organization.
  #
  # Returns a Boolean.
  def private_repo_by_default?
    return %w[internal private].include?(GitHub.default_repo_visibility) if GitHub.enterprise?
    external_identity_sessions.active.any?
  end

  def default_repo_visibility
    return "private" if private_repo_by_default?
    "public"
  end

  def over_plan_limit?
    return false if has_unlimited_private_repositories?
    private_repo_count_for_limit_check > plan_limit(:repos, visibility: :private)
  end

  def over_plan_limit_orgs
    @over_plan_limit_orgs ||=
      owned_organizations.paying.select(&:over_plan_limit?)
  end

  def org_over_plan_limit?
    over_plan_limit_orgs.present?
  end

  def self.with_profile_email(email)
    Profile.find_by_email(email).try(:user)
  end

  def self.all_with_profile_email(email)
    User.joins(:profile).where(profile: { email: }).to_a
  end

  PROFILE_ATTRIBUTES = %w(
    bio
    blog
    company
    display_staff_badge
    email
    hireable
    location
    name
    local_time_zone_name
    readme_opt_in
    spoken_language_preference_code
    twitter_url
    twitter_username
    social_accounts
    pronouns
  ).freeze

  PROFILE_ATTRIBUTES.each do |attribute|
    define_method "profile_#{attribute}" do
      profile.try(attribute)
    end

    define_method "profile_#{attribute}=" do |value|
      @profile_updated = true
      find_or_create_profile
      if profile.send(attribute) != value # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
        profile.send("#{attribute}=", value)
        touch
      end
    end
  end

  PROFILE_HTML_ATTRIBUTES = {
    bio: GitHub::Goomba::ProfileBioPipeline,
    company: GitHub::Goomba::ProfileCompanyPipeline,
  }.freeze

  PROFILE_HTML_ATTRIBUTES.each do |attribute, goomba_pipeline|
    define_method "profile_#{attribute}_html" do
      value = profile.try(attribute)
      if value.present?
        goomba_pipeline.to_html(value, {})
      else
        GitHub::HTMLSafeString::EMPTY
      end
    end

    define_method "async_profile_#{attribute}_html" do
      async_profile.then do |profile|
        value = profile.try(attribute)
        if value.present?
          goomba_pipeline.to_html(value, {})
        else
          GitHub::HTMLSafeString::EMPTY
        end
      end
    end
  end

  def profile_readme_opt_in?
    profile_readme_opt_in == true
  end

  def profile_email_is_known
    return if organization?
    return if profile.email.blank?
    if profile.email_changed? && possible_profile_emails.exclude?(profile.email)
      email_type = GitHub.email_verification_enabled? ? "verified" : "known"
      errors.add(:profile_email, "must be one of the user's #{email_type} email addresses")
    end
  end

  def profile_social_accounts_are_valid
    Profile.social_account_validation(self, profile_social_accounts, :profile_social_accounts)
  end

  def ignored_upgrade?
    self.upgrade_ignore && (self.upgrade_ignore == plan.name)
  end

  # Is deletion of this user permitted?
  #
  # actor - User attempting the deletion.
  #
  # Returns Boolean.
  def permit_deletion?(actor = nil)
    actor ||= self
    cannot_delete_reason(actor).blank?
  end

  # Public: Get the reason that deletion is not permitted.
  #
  # actor - User attempting the deletion.
  #
  # Returns Symbol or nil.
  def cannot_delete_reason(actor = nil)
    actor ||= self
    return :legal_hold if legal_hold?
    return :system_account if system_account?
    return :trade_restrictions if trade_compliance_account_delete_restriction?
    return :sponsorable if sponsorable?
    listing = sponsors_listing
    return :sponsors_listing_not_deletable if listing.present? && !listing.deletable?
    return nil if actor.site_admin?
    return :trade_restrictions if has_any_trade_restrictions?
    return :spammy if spammy? && !self.spammy_deleting_overridden?
    return :managed_user if managed_user_deletion_disabled?
    nil
  end

  def rate_limit_exempt_user?
    GitHub.rate_limiting_exempt_users.include?(login) && persisted?
  end

  def find_logins
    find_audit_events("user.login")
  end

  def find_login_ip_addresses
    find_logins.collect { |t| t["actor_ip"] }
  end

  # NOTE: Deprecate ip_neighbors eventually in favor of User.by_ip_with_prefix.
  # Public: Returns users that share the same last ip address.
  #   Used by spam/platform-health team.
  #
  # prefix - network address prefix to filter users by (default 24)
  #
  # Returns User Scope
  def ip_neighbors(prefix: 24)
    ip = if prefix == 24 && last_ip =~ /\d+\.\d+\.\d+/
      $~[0] + ".%" # $~[0] grabs the last matched item. ex "1.2.3.%"
    elsif last_ip =~ /\d+\.\d+\.\d+.\d+/
      $~[0] # ex "1.2.3.4"
    else
      nil
    end

    ip ? User.where(["last_ip like ?", ip]) : User.none
  end

  # Public: Returns users at an ip address by direct match (prefix: 32) or class C (prefix: 24).
  # Used by @github/platform-health in spam fighting efforts.
  #
  # ip - String IPv4 address.
  #
  # Returns an ActiveRecord::Relation.
  def self.by_ip_with_prefix(ip, prefix: NETWORK_ADDRESS_PREFIX_32)
    return User.none unless ip.present?
    return by_ip(ip) if prefix == NETWORK_ADDRESS_PREFIX_32
    return User.none if prefix != NETWORK_ADDRESS_PREFIX_24
    ip_parts = ip.match(NETWORK_ADDRESS_PARTS_REGEX)
    return User.none if ip_parts.nil?
    ip_like = "#{ip_parts[1]}.#{ip_parts[2]}.#{ip_parts[3]}.%" # "1.2.3.%"
    from("users USE INDEX (index_users_on_last_ip)").where(["last_ip like ?", ip_like])
  end

  NETWORK_ADDRESS_PREFIX_32 = 32
  NETWORK_ADDRESS_PREFIX_24 = 24
  NETWORK_ADDRESS_PARTS_REGEX = /(\d+)\.(\d+)\.(\d+)\.(\d+)/

  def find_audit_events(event)
    find_audit_events_for_actions([event])
  end

  def find_audit_events_for_actions(actions)
    options = {
      user_id: id,
      allowlist: actions,
      raw: true,
    }
    Audit::Driftwood::Query.new_user_query(options).execute.results
  end

  # Public: Returns an elasticsearch query string that will find all of this
  # user's audit log events
  #
  # Returns a String which can be passed to elasticsearch as a `query_string`
  def audit_log_query
    "(user_id:#{id} OR actor_id:#{id})"
  end

  def audit_log_kql_query
    "webevents | where (user_id == #{id} or actor_id == #{id})"
  end

  # Public: Returns an elasticsearch query string that will find all of this
  # user's recent abuse reports
  #
  # Returns a String which can be passed to elasticsearch as a `query_string`
  def recent_abuse_reports_query
    "data.reported_user_id:#{id} action:user.report_abuse created_at:>#{(Time.now - 2.weeks).to_i}"
  end

  def recent_abuse_reports_kql_query
    <<~KQL
        webevents
        | where data.reported_user_id == "#{id}"
        | where action == "user.report_abuse"
        | where _timestamp > now() - 14d
      KQL
  end

  # Internal: do any Orgs on this User have a private plan?
  def orgs_with_private_plan?
    organizations.on_paid_plan.not_disabled.any?
  end

  # Absolute permalink URL for this user.
  #
  # include_host - Turn off the `GitHub.url` host in the url. (default true)
  #                user.permalink(include_host: false) => `/jonrohan`
  #
  def permalink(include_host: true)
    if include_host
      "#{GitHub.url}/#{to_param}"
    else
      "/#{to_param}"
    end
  end

  # Private: Was the associated Profile updated?
  def profile_updated?
    @profile_updated
  end
  private :profile_updated?

  def find_or_create_profile
    Profile.retry_on_find_or_create_error do
      profile ||
        ActiveRecord::Base.connected_to(role: :writing) { create_profile }
    end
  end

  # Internal: save Profile if the user has changed their profile fields
  def update_profile
    if profile_updated?
      was_bio_set = profile.bio_changed? && profile.bio_was.nil?
      profile.save
      accept_tos
      @profile_updated = false
      if was_bio_set
        user_type = organization? ? "organization" : "user"
        GitHub.dogstats.increment("user", tags: ["type:#{user_type}", "action:profile_bio_set"])
      end
    end
  end

  def find_or_create_dashboard
    UserDashboard.retry_on_find_or_create_error do
      dashboard ||
        ActiveRecord::Base.connected_to(role: :writing) { create_dashboard }
    end
  end

  # Internal: Sync the site admin status of the user with the global business
  # admin status.
  def sync_site_admin_and_global_business_admin
    return unless GitHub.single_business_environment? && GitHub.global_business
    return unless user?
    return unless saved_change_to_attribute? :gh_role

    if self.reload.site_admin?
      GitHub.global_business.add_owner(self, actor: nil)
    else
      GitHub.global_business.remove_owner(self, actor: nil, send_notification: false)
    end
  end

  def update_business_user_account_login
    return if GitHub.single_business_environment?
    return unless saved_change_to_login?
    # the login name is not updated when emu users is being provisioned
    return if provisioning_an_emu_user

    BusinessUserAccount.where(user_id: self.id).update_all(login: self.login)
  end

  def update_business_user_account_spammy
    return if GitHub.single_business_environment?
    return unless saved_change_to_spammy?

    BusinessUserAccount.where(user_id: self.id).update_all(spammy: self.spammy?)
  end

  # Internal: Does this user's login need to satisfy the standard formatting
  # rules for a user login?
  #
  # Returns a Boolean.
  def validates_login_format?
    true
  end

  def email_address_required?
    # Don't require email addresses when authentication is done
    # using an external source (SAML, LDAP, etc.), since we may
    # not have an email addresses available when creating accounts.
    return false if GitHub.auth.external?
    return false if deprovisioned?
    true
  end

  # Get user's time zone or return default zone.
  #
  # Returns ActiveSupport::TimeZone.
  def time_zone
    ActiveSupport::TimeZone[time_zone_name.to_s] || Time.zone
  end

  # Set user's time zone.
  #
  # zone - ActiveSupport::TimeZone
  #
  # Returns nothing.
  def time_zone=(zone)
    self.time_zone_name = zone.name
  end

  # Get user's mobile time zone or return default zone.
  #
  # Returns ActiveSupport::TimeZone.
  def mobile_time_zone
    async_mobile_time_zone.sync
  end

  def async_mobile_time_zone
    async_profile.then do |profile|
      ActiveSupport::TimeZone[profile&.mobile_time_zone_name || Time.zone]
    end
  end

  # Public: Disables a user's account and removes all access to GitHub -
  # intended for GitHub staff only when a laptop or other device is lost.
  #
  # Returns Boolean
  def staff_revoke(actor = nil, reason = "Staff revocation")
    return false unless id && (site_admin? || employee?)

    payload = {
      prefix: :staff,
      reason: reason,
    }

    if actor.present?
      payload[:actor] = actor
    end

    instrument :revoke, payload

    suspend(reason)
    public_keys.destroy_all
    oauth_accesses.destroy_all
  end

  # Public: Persist metadata associated with the last user login.
  def save_login_metadata(options = {})
    self.last_ip = options[:ip]
    ActiveRecord::Base.connected_to(role: :writing) do
      save if changed?
    end
  end

  def event_prefix
    :user
  end

  def event_key
    :user
  end

  def event_payload
    {
      event_prefix => self,
    }
  end

  def event_context(prefix: event_prefix)
    {
      prefix => display_login,
      "#{prefix}_id".to_sym => id,
    }
  end

  # Track which versions of the Terms of Service the user has accepted
  def accept_tos
    TosAcceptance.connection.insert(Arel.sql(<<-SQL, user_id: id, sha: TosAcceptance.current_sha, now: Time.now))
      INSERT INTO tos_acceptances (user_id, sha, created_at, updated_at)
      VALUES (:user_id, :sha, :now, :now)
      ON DUPLICATE KEY UPDATE updated_at = :now
    SQL
  end

  # Public: Get an instance for modifying settings on this user's profile page.
  #
  # Returns a User::ProfileSettings.
  def profile_settings
    @profile_settings ||= User::ProfileSettings.new(self)
  end

  # Public: Instrument new user creation.
  #
  # Returns nothing.
  def instrument_creation
    instrument :create, {
      actor: self,
      email: email,
      plan: plan.try(:name),
      solved_interactive_captcha: !!solved_interactive_captcha,
    }

    instrument_user_signup
  end

  # Private: Instrument user signup.
  #
  # Returns nothing.
  def instrument_user_signup
    GlobalInstrumenter.instrument "user.signup", {
      actor: self,
      signup_email: emails.first,
    }
  end

  attr_accessor :solved_interactive_captcha

  # Public: Instrument last_ip update.
  def instrument_last_ip_update
    previous_ip, current_ip = saved_changes["last_ip"]

    GlobalInstrumenter.instrument "user.last_ip_update", {
      actor: self,
      previous_ip: previous_ip,
      current_ip: current_ip,
    }
  end

  # By the time we instrument the deletion, the user has already been deleted
  # so we won't be able to look at its email unless we memoize it here
  def memoize_email_for_instrument_deletion
    @email_for_instrument_deletion = email || billing_email
  end

  # Public: Instrument user deletion.
  #
  # payload - Hash of custom payload data.
  #
  # Returns nothing.
  def instrument_deletion
    instrument :delete, {
      email: @email_for_instrument_deletion,
      plan: GitHub.enterprise? ? "enterprise" : "free",
    }
  end

  # Public: Instrument successful user login.
  #
  # Returns nothing.
  def instrument_login(payload)
    instrument :login, payload.merge(
      user: self,
      actor: self,
      two_factor: !!two_factor_authentication_enabled?,
    )
  end

  # Private: Instrument authenticated device status
  #
  # Returns nothing.
  # Public: Instrument the status change of an authenticated device
  # authenticated device approval status.
  #
  # action - The action being performed by the user
  # device - The device the action was performed on
  # actor - The staff user verifying the device on behalf of the user
  # reason - The method by which the device became verified (if applicable)
  #
  # Returns nothing.
  def instrument_unverified_device(action, device, actor: nil, reason: nil, method: nil)
    payload = {
      actor: actor || self,
      device_id: device.id,
      device_cookie: device.device_id,
      display_name: device.display_name,
      approved_at: device.approved_at,
    }

    payload[:reason] = reason if reason
    payload[:delivery_method] = method if method

    instrument action, payload

    tags = ["action:#{action}"]
    tags << "reason:#{reason}" if reason
    GitHub.dogstats.increment("authenticated_device", tags: tags)
  end

  # Public: Instrument successful unexpected user login. This occurs when a web
  # login comes from a country or device (or both) the user has not previously
  # logged in from.
  #
  # authentication_record: An AuthenticationRecord
  #
  # Returns nothing.
  def instrument_unexpected_login(authentication_record)
    reason = authentication_record.flagged_reason
    unless AuthenticationRecord::UNEXPECTED_SIGN_IN_REASONS.include?(reason.to_s)
      raise ArgumentError, "Unrecognized reason: #{reason}"
    end

    payload = {
      country: authentication_record.country_code || "Unknown",
      user_session_id: authentication_record.user_session_id,
    }

    event = if authentication_record.two_factor_partial_sign_in?
      :correct_password
    else
      :sign_in
    end

    instrument "#{event}_from_#{reason}", payload
  end

  # Public: Instrument failed user logins for users that do not exist.  This
  # is a class method since there is no instance of User that corresponds
  # to the associated login attempt.
  #
  # Returns nothing.
  def self.instrument_failed_login(payload = {})
    GitHub.instrument "user.failed_login", payload
  end

  # Public: Instrument failed user login.
  #
  # Returns nothing.
  def instrument_failed_login(payload = {})
    instrument :failed_login, payload.merge(
      user: login,
      actor: login,
      actor_id: id,
      user_id: id,
    )
  end

  # Public: Instrument a partial two factor email followup
  # This occurs when a user has begun the two factor process but
  # never completes the sign in. This is a sign of suspicious behavior
  # and is useful for staff to have access to this information
  #
  # Returns nothing.
  def instrument_partial_two_factor_email_followup(record)
    instrument :partial_two_factor_email_followup, {
      authentication_record_id: record.id,
      flagged_reason: record[:flagged_reason],
      time_of_sign_in: record[:created_at],
    }
  end

  # Public: Instrument disabling/enabling a User for billing
  #
  # Returns nothing
  def instrument_disabled(payload = nil)
    payload = (payload || {}).merge(
      user_id: id,
      login: login,
      plan: plan.try(:name),
    )

    instrument (disabled? ? :disabled : :enabled), payload
  end

  # Public: Instrument enabling/disabling User preference for
  # showing private contributions.
  #
  # enabled - Accepts a Boolean
  #
  # Returns nothing.
  def instrument_private_contributions(enabled:, payload: {})
    payload = payload.merge(
      actor: self,
    )

    if enabled
      GitHub.dogstats.increment "user", tags: ["action:show_private_contributions_count"]
      instrument :show_private_contributions_count, payload
    else
      GitHub.dogstats.increment "user", tags: ["action:hide_private_contributions_count"]
      instrument :hide_private_contributions_count, payload
    end
  end

  def record_plan_change_transaction
    transactions.create!(action: disabled? ? "disabled" : "enabled")
  end

  class MissingUserWhenAddingToSearch < RuntimeError; end

  # Public: Determine if this user should be added to the search index. Spammy
  # users are excluded from the search index.
  #
  # Returns true or false.
  def searchable?
    return false if spammy?                 # is this user spammy
    return false if GitHub.enterprise? && system_account?
    true
  end

  # Public: Synchronize this user with its representation in the search
  # index. If the user is newly created or modified in some fashion, then it
  # will be updated in the search index. If the user has been destroyed, then
  # it will be removed from the search index. This method handles both cases.
  #
  # *args - Anything. Accepted so method can be used as an association callback.
  #
  # Returns this User instance.
  #
  def synchronize_search_index(*args)
    return self unless self.searchable?

    raise MissingUserWhenAddingToSearch unless self.id

    if self.destroyed?
      RemoveFromSearchIndexJob.perform_later("user", self.id)
    else
      Search.add_to_search_index("user", self.id)
    end

    self
  end

  # Internal: queue a job to do tasks needed after signup
  #
  #
  # Returns nothing.
  def queue_signup_tasks(invitation_token: nil, repo_invitation_token: nil)
    if GitHub.signup_enabled?
      UserSignupJob.perform_later(id, invitation_token: invitation_token, repo_invitation_token: repo_invitation_token)
    else
      UserSignupJob.perform_later(id)
    end
  end

  # Public: The last time the user was active. Fit for human consumption.
  #
  # Returns a timestamp or "No activity".
  def last_active
    last_active_timestamp || "No activity"
  end

  # Public: The last time the user had an active session.
  #
  # Returns ActiveSupport::TimeWithZone
  def last_active_session_at
    if session = most_recent_session
      session.accessed_at.in_time_zone
    end
  end

  # Public - Should we be hiding ourselves from this viewing user?
  # If we are spammy, and the user trying to view us is not self,
  # nor is it a staff member, then run and hide.  This is primarily
  # for use in the Users controller to 404 spammy accounts.
  #
  # viewer - a User object
  #
  # Returns a Boolean
  def hide_from_user?(viewer)
    # If we're not spammy or suspended, stand up proud
    return false unless spammy? || suspended?

    # Can't hide from dotcom staff & Enterprise admins
    return false if viewer && viewer.site_admin?

    # If you belong to a spammy organization, should still be able to see
    # that organization.
    if organization?
      return false if adminable_by?(viewer) ||
                      direct_or_team_member?(viewer) ||
                      billing_manager?(viewer)
    end

    # Always hide if spammy users are hidden and the user is spammy
    return true if spammy? && viewer != self

    # Can't hide when suspended users are visible
    return false if GitHub.suspended_users_visible? && suspended?

    # Hide from anonymous users
    return true if viewer.nil?

    # Don't hide from yourself
    viewer != self
  end

  # Public - Can the given actor create a repository for this user (self)?
  #
  # A user can create repositories for itself, cannot for other users,
  # and uses Organization logic otherwise.
  #
  # actor - The User or Organization wanting to create a repository.
  #
  # Returns Boolean
  def can_create_repository?(actor, visibility: nil)
    return false if emu_creating_public_repo?(visibility)

    # visibility is here to make it easier to call this whether Organization or User.
    authorization = ContentAuthorizer.authorize(actor, :repo, :create, owner: self)
    authorization.authorized?
  end

  def can_own_repositories?
    true
  end

  def async_url(suffix = "")
    template = Addressable::Template.new("/{login}#{suffix}")
    template.expand login: login
  end

  # Checks if the given user should use transfer requests when moving a
  # repository to this user
  #
  # Returns a boolean
  def requires_transfer_requests_from?(user, repository_visibility = nil)
    # repository_visibility is here to match signature of Organization#requires_transfer_requests_from?
    self != user
  end

  # Public: Does the user receive an email when the user's account is destroyed?
  #
  # Returns a Boolean.
  def receives_confirmation_when_destroyed?
    return false if GitHub.enterprise?
    # Emails are sent on Organization soft-deletion instead.
    return false if organization?
    # If a user has to be deleted because something went wrong during the social sign up flow
    # Do not send the user an email.
    return false if gh_role == "social_signup_delete"

    !suspended? && gh_role != "staff_delete" && !spammy?
  end

  # Whether to show the staff badge on the profile. We show the staff badge
  # if the viewer is an employee OR if the user has opted to display the badge
  # publicly
  #
  # Returns true if we should show the staff badge
  def show_staff_badge_to?(viewer)
    return true if login == GitHub.staff_user_login
    return false unless metadata.is_staff?

    employee? && (profile_display_staff_badge || viewer&.employee?)
  end

  # Public: Check if current user account is created within 7 days ago.
  #
  # user: User object to check for
  #
  # Returns a Boolean.
  def is_new?
    created_at >= 7.days.ago
  end

  def keep_old_avatar?
    false
  end

  def avatar_editable_by?(user)
    user == self
  end

  # Public - Check whether or not the user's login can be changed.
  #
  # Returns false if authentication doesn't allow renaming.
  # Returns false if authentication is ldap and there is no user mapping.
  # Checks if spammy users are allowed to rename
  # Returns true otherwise.
  def renaming_enabled?
    return if spammy? && !spammy_renaming_overridden?
    return false if self.is_enterprise_managed?
    GitHub.auth.user_renaming_enabled?(self)
  end

  # Public - Check whether or not the user can change their own display name.
  #
  # Returns false if authentication doesn't allow a user changing their own display name.
  #  - authentication is ldap and user is authenticated via the directory (LDAP mapped).
  # Returns true otherwise.
  def change_profile_name_enabled?
    return false if self.is_enterprise_managed?
    GitHub.auth.user_change_profile_name_enabled?(self)
  end

  # Public - Check whether or not the user can change their own email addresses.
  #
  # Returns false if authentication doesn't allow a user changing their own email addresses.
  #  - authentication is ldap, ldap sync of emails is enabled and user is authenticated via the directory (LDAP mapped).
  # Returns true otherwise.
  def change_email_enabled?
    return false if self.is_emu_and_not_first_owner?
    return false if self.enterprise_server_scim_managed_user?
    GitHub.auth.user_change_email_enabled?(self)
  end

  # Public - Check whether or not the user can change their company
  #
  # Returns false if authentication doesn't allow a user changing their company.
  # Returns true otherwise.
  def change_company_enabled?
    return false if self.is_enterprise_managed?
    true
  end

  # Public - Check whether or not the user can change their own SSH keys.
  #
  # Returns false if authentication doesn't allow a user changing their own ssh keys.
  #  - authentication is ldap, ldap sync of ssh keys is enabled and user is authenticated via the directory (LDAP mapped).
  # Returns true otherwise.
  def change_ssh_key_enabled?
    GitHub.auth.user_change_ssh_key_enabled?(self)
  end

  # Public - Check whether or not the user can change their own GPG keys.
  #
  # Returns false if authentication doesn't allow a user changing their own GPG keys.
  #  - authentication is ldap, ldap sync of GPG keys is enabled and user is authenticated via the directory (LDAP mapped).
  # Returns true otherwise.
  def change_gpg_key_enabled?
    GitHub.auth.user_change_gpg_key_enabled?(self)
  end

  # Public - determine if the user has ANY unverified public keys.
  #
  # Returns true if any key is unverified
  # Returns false if all keys are verified or there are no keys to verify.
  def unverified_public_keys?
    public_keys.any? { |key| !key.verified? }
  end

  # Public - Which layouts should be used when viewing this in site admin
  #
  # Returns "user" for users, and "organization" for orgs
  def site_admin_context
    "user"
  end

  def devtools_scope?
    site_admin? || github_developer?
  end

  def biztools_scope?
    site_admin? || biztools_user?
  end

  def show_blocked_contributors_warning?
    return false if organization?
    return true unless self.interaction_setting
    self.interaction_setting.show_blocked_contributors_warning
  end

  def rebuild_asset_status(notify: true, manual: false)
    RebuildStorageUsageJob.perform_later(id, { "notify" => notify, "manual" => manual })
  end

  def build_asset_status!
    return if asset_status
    Asset::Status.build_for_owner(:lfs, id)
    association(:asset_status).reset
  end

  # Internal: can the user be subscribed to notifications
  #
  # Returns true
  def newsies_enabled?
    true
  end

  # Internal: If the current user is being destroyed, we need to assemble various
  # payloads. The user is going to go away, and we need to make sure they are
  # still represented in hooks being fired, either as the actor or the subject.
  #
  # event - Required kwarg indicating which event is being delivered later
  #
  # Returns the current user.
  def construct_future_event(&block)
    raise "Erroneous call to `construct_future_events': User.#{self.id} is not being destroyed" unless self.being_destroyed?
    @delivery_system ||= []
    @delivery_system << Hook::DeliverySystem.new(yield)
    @delivery_system.last.generate_hookshot_payloads
  end

  # Internal: Does this account have any IntegrationInstallations on all repositories
  #
  # Returns an Array
  def installations_on_all_repositories
    actor_ids = Permission.where(
      actor_type: "IntegrationInstallation",
      subject_id: self.id,
      subject_type: "#{Repository::Resources::ALL_ABILITY_TYPE_PREFIX}/metadata"
    ).distinct.pluck(:actor_id)

    IntegrationInstallation.where(id: actor_ids)
  end

  # Public: Has the user signed the pre-release agreement.
  #
  # Returns a Boolean.
  def prerelease_agreement_signed?
    async_prerelease_agreement_signed?.sync
  end

  def async_prerelease_agreement_signed?
    Platform::Loaders::ActiveRecordAssociation.load(self, :prerelease_agreement).then do |agreement|
      !!agreement
    end
  end

  # Public: have any Orgs on this User signed the prerelease agreement?
  def async_org_prerelease_agreement_signed?
    Promise.all(organizations.map(&:async_prerelease_agreement)).then do |agreements|
      agreements.any? { |x| !x.nil? }
    end
  end

  # Public: Returns true if we have placed a hold on this user so we don't purge
  # their deleted repositories.
  def legal_hold?
    legal_hold.present?
  end

  def self.account_deletion_phrase
    "delete my account"
  end

  # Public: Returns a list of a user's repositories visible to the actor
  #
  # actor - The User trying to view repositories.
  #
  def visible_repositories_for(actor)
    if actor != self
      repositories.public_or_accessible_by(actor)
    else
      repositories
    end
  end

  # Public: Can the specified actor view projects owned by this user?
  #
  # actor - The User trying to view projects.
  #
  # Returns a boolean.
  def projects_readable_by?(actor)
    # For now, integrations cannot view user projects.
    actor.nil? || !actor.can_have_granular_permissions?
  end

  # Public: Can the specified actor view projects owned by this user?
  #
  # actor - The User trying to view projects.
  #
  # Returns Promise<bool>
  def async_projects_readable_by?(actor)
    Promise.resolve(projects_readable_by?(actor))
  end

  # Public: Can the specified actor create/edit projects on this user?
  #
  # actor - The User trying to create/edit projects.
  #
  # Returns a boolean.
  def projects_writable_by?(actor)
    # For now, only the user can create projects belonging to them.
    actor == self
  end

  # Public: Can the specified actor create/edit projects on this user?
  #
  # actor - The User trying to create/edit projects.
  #
  # Returns Promise<bool>
  def async_projects_writable_by?(actor)
    Promise.resolve(projects_writable_by?(actor))
  end

  # Public: Can this user display the Pro badge on their profile?
  #
  # Returns a boolean
  def can_have_pro_badge?
    !employee? && plan.pro_badge?
  end

  # Public: Get verified email addresses that this user has that match the
  #         verified or approved domains available to a specified organization.
  #         Can be filtered to return only verified or approved domain emails.
  #
  # Note: When GitHub.email_verification_enabled? returns false, user emails
  # cannot be verified in the current environment. So the check for whether a
  # user email is verified is bypassed.
  #
  # organization      - The Organization to check verified domains from.
  # include_verified  -   include verified domains
  # include_approved  -   include approved domains
  #
  # Returns a Promise<[UserEmail]>.
  def async_eligible_emails_for(organization, include_verified: true, include_approved: true)
    return Promise.resolve([]) unless include_verified || include_approved

    organization.async_member?(self).then do |is_member|
      next [] unless is_member

      organization.async_email_eligible_domains(
        include_verified: include_verified, include_approved: include_approved
      ).then do |domains|
        UserEmail.email_addresses_from_domains(domains.map(&:domain), [id])[id]
      end
    end
  end

  # Public: sync version of async_eligible_emails_for
  #
  # Note: When GitHub.email_verification_enabled? returns false, user emails
  # cannot be verified in the current environment. So the check for whether a
  # user email is verified is bypassed.
  #
  # organization      -   The Organization to check verified domains from.
  # include_verified  -   include verified domains
  # include_approved  -   include approved domains
  #
  # Returns: Array[UserEmail]
  def eligible_emails_for(organization, include_verified: true, include_approved: true)
    return [] unless organization.verified_domain_restriction_should_check_user?(self)

    if organization.business.nil?
      domains = organization.email_eligible_domain_urls(
        include_verified: include_verified, include_approved: include_approved
      )
      UserEmail.email_addresses_from_domains(domains, [id])[id]
    else
      organization.business.email_eligible_domain_user_emails_for(
        organization, self, include_verified: include_verified, include_approved: include_approved
      )
    end
  end

  def global_health_files_repository
    repositories.with_global_health_files_name.public_scope.first
  end

  def async_global_health_files_repository
    Platform::Loaders::GlobalHealthFilesRepository.load(id)
  end

  # target for conditional access is the entity governing resources that are subject to conditional access policies.
  # Since Users can own resources like repositories, they could define conditional access policies.
  #
  # Returns the self User instance
  def target_for_conditional_access
    self
  end

  def async_target_for_conditional_access
    Promise.resolve(self)
  end

  def private_config_as_code_repo
    @private_config_as_code_repo ||= repositories.find_by(name: Organization::PRIVATE_CONFIG_AS_CODE_REPO_NAME)
  end

  # Determines the target for for conditional access for multiple User instances
  #
  # users - an enumerable of User
  #
  # returns Hash[User] => target for conditional access
  def self.multiple_target_for_conditional_access(users)
    ConditionalAccess::Filter.ensure_with_class(users, User)
    users.each_with_object({}) { |v, h| h[v] = v }
  end

  def global_notice
    super || GlobalNotice.new(user: self)
  end

  def self.user_role_target_type
    "User"
  end

  # The class name persisted as `target_type` when a UserRole is created
  # with this object as target.
  #
  # Returns: String
  def user_role_target_type
    self.class.user_role_target_type
  end

  # Returns user's pull request preferences
  def pull_request_user_preferences
    Platform::Models::PullRequestUserPreferences.new(user: self)
  end

  # Public: Check if user can be contacted
  # https://github.com/github/sponsors/issues/3520
  #
  # Returns a Boolean
  def can_be_contacted?
    return false if spammy?
    return false if disabled?
    return false unless wants_email?

    !has_any_trade_restrictions?
  end

  # Public: returns an instance of Copilot::User::CopilotApi
  def copilot_api(integration_id:, session: nil, real_ip: nil, token: nil, request_id: nil)
    unless request_id
      if defined?(GitHub) && GitHub.respond_to?(:context)
        request_id = GitHub.context[:request_id]
      end
    end

    Copilot::User::CopilotApi.new(
      self,
      integration_id:,
      session:,
      real_ip:,
      token:,
      api_version: copilot_api_version,
      request_id: request_id,
    )
  end

  sig { returns(String) }
  def copilot_api_version
    if feature_flag_enabled?(:copilot_api_version_20250501, default: true)
      CopilotAPI::VERSION_2025_05_01
    else
      CopilotAPI::VERSION_DEFAULT
    end
  end

  # Number of days to keep nudge interaction records before cleanup
  # Needs to be below 30 to abide by GDPR
  NUDGE_INTERACTION_RETENTION_DAYS = 29

  # Public: Check if the user is subscribed to in-product messages
  #
  # Returns boolean
  def subscribed_to_in_product_messages?
    # This only returns false if a user is explicitly unsubscribed
    # and intentionally returns true if a users preference is nil
    # meaning they have never opted out
    return false if in_product_messaging_subscription&.subscribed? == false
    true
  end

  # Public: Check if user has clicked a nudge relative to a specified time
  #
  # id     - String or Symbol representing the nudge ID (default: nil)
  # before - ActiveSupport::Duration time period to check before now (default: nil)
  # after  - ActiveSupport::Duration time period to check after now (default: nil)
  # on     - Date or Time to check for interactions occurring on that day (default: nil)
  # group  - Symbol specifying the group nudge (default: nil)
  # type   - Symbol specifying the type of interaction (:impression, :click, :dismissal) (default: nil)
  # excluded_ids - Array of Strings or Symbols representing nudge IDs to exclude from the check (default: [])
  # all_ids - Array of Strings or Symbols where all IDs must have been interacted with (default: nil)
  # any_ids - Array of Strings or Symbols where at least one ID must have been interacted with (default: nil)
  # enterprise_id - String representing the enterprise ID (optional)
  # org_id - String representing the organization ID (optional)
  #
  # Examples:
  #   interacted_with_a_nudge(before: 2.days) # checks if interaction was within last 2 days
  #   interacted_with_a_nudge(after: 1.week)  # checks if interaction was more than 1 week ago
  #   interacted_with_a_nudge(on: Date.today)  # checks if interaction occurred today
  #   interacted_with_a_nudge(group: :connect, excluded_ids: [:hello_world]) # checks group but excludes specific ID
  #   interacted_with_a_nudge(all_ids: [:nudge1, :nudge2], before: 1.day) # checks if ALL nudges were interacted with
  #   interacted_with_a_nudge(any_ids: [:nudge1, :nudge2], before: 1.day) # checks if ANY nudge was interacted with
  #
  # Returns Boolean indicating if user interacted with a nudge within the specified time criteria
  def interacted_with_a_nudge(id: nil, before: nil, after: nil, on: nil, group: nil, type: nil, excluded_ids: [], all_ids: nil, any_ids: nil, enterprise_id: nil, org_id: nil)
    # Validate time parameters
    time_params = [before, after, on].compact
    raise ArgumentError, "Must provide either before:, after:, or on: parameter" if time_params.empty?
    raise ArgumentError, "Can only provide one of before:, after:, or on: parameters" if time_params.length > 1

    # Validate ID parameters - ensure only one ID-related parameter is provided
    id_params = [id, group, all_ids, any_ids].compact
    raise ArgumentError, "Must provide one of id:, group:, all_ids:, or any_ids: parameter" if id_params.empty?
    raise ArgumentError, "Can only provide one of id:, group:, all_ids:, or any_ids: parameters" if id_params.length > 1

    namespace_params = [enterprise_id, org_id].compact
    raise ArgumentError, "Can only provide one of enterprise_id: or org_id: parameters" if namespace_params.length > 1

    subscription = in_product_messaging_subscription
    return false unless subscription
    return false unless subscription.metadata

    type_key =
      case type
      when :impression then "impressions"
      when :click then "clicks"
      when :dismissal then "dismissals"
      else return false
      end

    return false unless subscription.metadata[type_key]

    if group
      # Convert excluded_ids to strings for comparison
      excluded_ids = Array(excluded_ids).map(&:to_s)

      # Search through all entries in the interaction type for matching group
      # excluding any IDs that are in the excluded_ids list
      matching_interactions = subscription.metadata[type_key].reject do |key, _|
        excluded_ids.include?(key)
      end.find do |_, data|
        data["group"]&.to_sym == group.to_sym
      end

      return false unless matching_interactions
      interaction_data = matching_interactions[1] # [1] gets the value from the key-value pair
      check_interaction_time(interaction_data, before, after, on, enterprise_id: enterprise_id, org_id: org_id)
    elsif all_ids || any_ids
      ids_to_check = (all_ids || any_ids).map(&:to_s)
      results = ids_to_check.map do |check_id|
        next false unless interaction_data = subscription.metadata[type_key][check_id]
        check_interaction_time(interaction_data, before, after, on, enterprise_id: enterprise_id, org_id: org_id)
      end

      all_ids ? results.all? : results.any?
    else
      # If not searching by group or multiple IDs, then search by the single ID
      interaction_data = subscription.metadata[type_key][id.to_s]
      check_interaction_time(interaction_data, before, after, on, enterprise_id: enterprise_id, org_id: org_id)
    end
  end

  # Helper method to check if an interaction occurred within the specified time criteria
  def check_interaction_time(interaction_data, before, after, on, enterprise_id: nil, org_id: nil)
    namespace_params = [enterprise_id, org_id].compact
    raise ArgumentError, "Can only provide one of enterprise_id: or org_id: parameters" if namespace_params.length > 1

    return false unless interaction_data && interaction_data["updated_at"]

    interaction_time = Time.parse(interaction_data["updated_at"])
    return false unless interaction_time

    return false if enterprise_id && interaction_data["enterprise"] != enterprise_id.to_s

    return false if org_id && interaction_data["org"] != org_id.to_s

    if on
      # Convert both times to dates for comparison if checking on a specific day
      on_date = on.respond_to?(:to_date) ? on.to_date : Date.parse(on.to_s)
      interaction_date = interaction_time.to_date
      return interaction_date == on_date
    else
      return false if before && interaction_time > before
      return false if after && interaction_time < after
    end

    true
  end

  # Public: Check if a nudge has exceeded the maximum number of impressions
  # and automatically dismiss it if so
  #
  # impressions - Integer maximum number of impressions allowed
  # id - Symbol or String representing the unique identifier for the nudge
  # enterprise_id - String representing the enterprise ID (optional)
  # org_id - String representing the organization ID (optional)
  #
  # Returns Boolean indicating if impressions were exceeded
  def nudge_exceeds(impressions:, id:, enterprise_id: nil, org_id: nil)
    ActiveRecord::Base.connected_to(role: :writing) do
      subscription = in_product_messaging_subscription
      nudge_id = id.to_s
      return false unless subscription

      current_metadata = subscription.metadata || {}
      current_metadata["impressions"] ||= {}
      current_metadata["impressions"][nudge_id] ||= {
        "count" => 0,
        "updated_at" => nil
      }

      if enterprise_id && current_metadata["impressions"][nudge_id]["enterprise"] != enterprise_id.to_s
        # no match
        return false
      end

      if org_id && current_metadata["impressions"][nudge_id]["org"] != org_id.to_s
        # no match
        return false
      end

      if current_metadata["impressions"][nudge_id]["count"] >= impressions
        dismiss_notice(nudge_id)
        true
      else
        false
      end
    end
  end

  # Public: Increment the impression count for a specific nudge ID
  # and update the last impression timestamp
  #
  # id - Symbol or String representing the unique identifier for the nudge
  # group - Symbol representing the group of the nudge
  #
  # Returns the updated count
  def track_nudge_impression(id: nil, group: nil, enterprise_id: nil, org_id: nil)
    namespace_params = [enterprise_id, org_id].compact
    raise ArgumentError, "Can only provide one of enterprise_id: or org_id: parameters" if namespace_params.length > 1

    ActiveRecord::Base.connected_to(role: :writing) do
      subscription = in_product_messaging_subscription || create_in_product_messaging_subscription

      current_metadata = subscription.metadata || {}
      current_metadata["impressions"] ||= {}

      # Clean up old impressions
      cutoff_time = NUDGE_INTERACTION_RETENTION_DAYS.days.ago
      current_metadata["impressions"].delete_if do |_, data|
        updated_at = data["updated_at"]
        next false unless updated_at
        Time.parse(updated_at) < cutoff_time
      end

      # Add/update current impression
      current_metadata["impressions"][id.to_s] ||= {
        "count" => 0,
        "updated_at" => nil
      }

      if group
        current_metadata["impressions"][id.to_s]["group"] = group.to_s
      end

      if enterprise_id
        current_metadata["impressions"][id.to_s]["enterprise"] = enterprise_id.to_s
      end

      if org_id
        current_metadata["impressions"][id.to_s]["org"] = org_id.to_s
      end

      # Increment the impression count but don't allow it to get infinitely high
      current_metadata["impressions"][id.to_s]["count"] = [current_metadata["impressions"][id.to_s]["count"] + 1, 9999].min
      current_metadata["impressions"][id.to_s]["updated_at"] = Time.current.iso8601

      subscription.metadata = current_metadata
      subscription.save!
      current_metadata["impressions"][id.to_s]["count"]
    end
  end

  # Public: Record a click for a specific nudge ID and clean up old click records
  #
  # id - Symbol or String representing the unique identifier for the nudge
  # group - Symbol representing the group of the nudge
  # enterprise_id - String representing the enterprise ID (optional)
  # org_id - String representing the organization ID (optional)
  #
  # Returns nothing
  def track_nudge_click(id: nil, group: nil, enterprise_id: nil, org_id: nil)
    ActiveRecord::Base.connected_to(role: :writing) do
      subscription = in_product_messaging_subscription || create_in_product_messaging_subscription
      current_metadata = subscription.metadata || {}
      current_metadata["clicks"] ||= {}

      # Add the new click
      current_metadata["clicks"][id.to_s] = {
        "updated_at" => Time.current.iso8601
      }

      if group
        current_metadata["clicks"][id.to_s]["group"] = group.to_s
      end

      if enterprise_id
        current_metadata["clicks"][id.to_s]["enterprise"] = enterprise_id.to_s
      end

      if org_id
        current_metadata["clicks"][id.to_s]["org"] = org_id.to_s
      end

      # Remove old clicks
      cutoff_time = NUDGE_INTERACTION_RETENTION_DAYS.days.ago
      current_metadata["clicks"].delete_if do |_, data|
        updated_at = data["updated_at"]
        next false unless updated_at
        Time.parse(updated_at) < cutoff_time
      end

      subscription.metadata = current_metadata
      subscription.save!
    end
  end

  def track_nudge_dismissal(id: nil, group: nil, enterprise_id: nil, org_id: nil)
    ActiveRecord::Base.connected_to(role: :writing) do
      subscription = in_product_messaging_subscription || create_in_product_messaging_subscription
      current_metadata = subscription.metadata || {}
      current_metadata["dismissals"] ||= {}

      # Add the new dismissal
      current_metadata["dismissals"][id.to_s] = {
        "updated_at" => Time.current.iso8601
      }

      if group
        current_metadata["dismissals"][id.to_s]["group"] = group.to_s
      end

      if enterprise_id
        current_metadata["dismissals"][id.to_s]["enterprise"] = enterprise_id.to_s
      end

      if org_id
        current_metadata["dismissals"][id.to_s]["org"] = org_id.to_s
      end

      # Remove dismissals older than retention period
      cutoff_time = NUDGE_INTERACTION_RETENTION_DAYS.days.ago
      current_metadata["dismissals"].delete_if do |_, data|
        updated_at = data["updated_at"]
        next false unless updated_at
        Time.parse(updated_at) < cutoff_time
      end

      subscription.metadata = current_metadata
      subscription.save!
    end
  end

  def invalidate_cache(event = nil)
    return unless FeatureFlag.vexi.enabled?(:users_cache_invalidation_enabled, default: false)
    if event.nil?
      event = parsed_event_type
    end
    Users::Cache::InvalidationJob.perform_later(id, event)
  rescue => e
    GitHub.dogstats.increment("users.cache.invalidation.queue_error", tags: { error: e.class.name })
  end

  private

  def update_repos_after_rename(old_login, new_login)
    # Keep the owner_login up to date with the new name
    repositories.update_all(owner_login:  new_login)

    # Route all repos to new login.
    repositories.reload.each do |repo|
      GitHub::Spokes.client.write_nwo_file(repo, repo.name_with_owner)

      # Page builds must be triggered by a human. Fetch the last human pusher, if possible.
      builder = repo.gh_pages_rebuilder(self)

      # by this point, the username has renamed, so is_user_pages_repo? is always false
      repo.page&.set_subdomain_to_match_nwo
      repo.rebuild_pages(builder) if builder && repo.page && repo.name.downcase != "#{old_login.to_s.downcase}.#{pages_host_name}"
      repo.redirect_from_previous_location("#{old_login}/#{repo.name}")

      repo.delete_shadowed_redirects

      repo.public_keys.each(&:save)

      if !old_login.casecmp?(login) && RetiredNamespace.should_retire?(repo)
        RetiredNamespace.retire_redirects!(repo)
      end

      Search.add_to_search_index("repository", repo.id) if repo.repo_is_searchable?
      Search.add_to_search_index("bulk_issues", repo.id, "purge" => true)
      GlobalInstrumenter.instrument("search_indexing.repository_changed", { change: :OWNER_CHANGED, repository: repo })
    end
  end

  # Private: returns true if the user can't read the entity.
  def unreadable?(entity)
    if entity.respond_to?(:readable_by?)
      !entity.readable_by?(self)
    end
  end

  # Private: returns true if the entity's owner is ignoring the user.
  def being_ignored?(entity)
    entity.try(:owner)&.ignore?(self)
  end

  def clear_spam_flag_if_allowlisted
    if spammy && never_spammy?
      self.spammy = false
    end
    true
  end

  # Public - Verify a browser session for an application given a key from the OAuth handshake
  #
  # Returns true if found, false otherwise
  def active_browser_session_for_application?(application, browser_session_value)
    return false unless browser_session_value.present?

    sessions.active.any? do |session|
      session.valid_for_oauth_application?(application, browser_session_value)
    end
  end
  public :active_browser_session_for_application?

  # Helper method for transferring all gists to another user. Only for console
  # use until we have time to build out Stafftools interface for transferring.
  def transfer_gists_to(new_owner, verbose = $console)
    gists.each do |gist|
      puts "transferring #{gist.nwo} to #{new_owner}" if verbose
      gist.transfer_to(new_owner)
    end
  end
  public :transfer_gists_to

  # Public - Get the possible email addresses that a user can select from to use
  # as their public profile email address.
  #
  # Returns an Array of Strings representing the email addresses
  def possible_profile_emails
    if GitHub.email_verification_enabled?
      emails.user_entered_emails.verified.map(&:to_s)
    else
      emails.user_entered_emails.map(&:to_s)
    end
  end
  public :possible_profile_emails

  # Internal: Should seat limit enforcement be skipped? Currently used to skip
  # seat limit enforcement during the import process of a migration.
  #
  # Returns false unless importing? is true.
  def skip_seat_limit_enforcement?
    importing?
  end

  # Public: toggle the rejection of pushes with private email addresses
  def toggle_warn_private_email
    if !self.warn_private_email?
      GitHub.dogstats.increment "user.email.privacy.warning_toggle.on"
    else
      GitHub.dogstats.increment "user.email.privacy.warning_toggle.off"
    end

    instrument :toggle_warn_private_email, warn_private_email: !self.warn_private_email? ? "enabled" : "disabled"
    update!(warn_private_email: !self.warn_private_email?)
  end
  public :toggle_warn_private_email

  # Always reuse the same destroy user callback because we have state that
  # is shared across the callback chain. This is bad, but can't be avoided without
  # serious refactoring.
  def destroy_user_callbacks
    @destroy_callback ||= DestroyUserCallbacks.new
  end

  def destroy_user_callbacks_before_destroy
    self.destroying = true
    destroy_user_callbacks.before_destroy(self)
  end

  def destroy_user_callbacks_after_commit
    destroy_user_callbacks.after_commit(self)
    @delivery_system.map(&:deliver_later) if @delivery_system.present?
  end

  def limit_bio_length?
    user? && profile_updated?
  end

  def reset_memoized_attributes
    remove_instance_variable(:@must_verify_email) if defined?(@must_verify_email)
    remove_instance_variable(:@should_verify_email) if defined?(@should_verify_email)
    remove_instance_variable(:@has_verified_emails) if defined?(@has_verified_emails)
    remove_instance_variable(:@async_has_unlocked_repository) if defined?(@async_has_unlocked_repository)
    remove_instance_variable(:@dormant) if defined?(@dormant)
    remove_instance_variable(:@private_repo_count_for_limit_check) if defined?(@private_repo_count_for_limit_check)
    remove_instance_variable(:@default_associated_repository_ids) if defined?(@default_associated_repository_ids)
    remove_instance_variable(:@business_admin_ability_ids) if defined?(@business_admin_ability_ids)
    remove_instance_variable(:@business_billing_management_ability_ids) if defined?(@business_billing_management_ability_ids)
    remove_instance_variable(:@async_membership_via_org_ids) if defined?(@async_membership_via_org_ids)
    remove_instance_variable(:@starred_repos_count) if defined?(@starred_repos_count)
    remove_instance_variable(:@following_users_count) if defined?(@following_users_count)
    remove_instance_variable(:@user_organization_filter) if defined?(@user_organization_filter)
    remove_instance_variable(:@newsies_settings_response) if defined?(@newsies_settings_response)
    remove_instance_variable(:@plans_by_name) if defined?(@plans_by_name)
    remove_instance_variable(:@sponsors_invoiced) if defined?(@sponsors_invoiced)
    remove_instance_variable(:@live_sdn_screening_enabled) if defined?(@live_sdn_screening_enabled)
    if defined?(@has_commercial_interaction_restriction)
      remove_instance_variable(:@has_commercial_interaction_restriction)
    end
    remove_instance_variable(:@insights_accessible_by_user_id) if defined?(@insights_accessible_by_user_id)
    if defined?(@sponsorship_amounts_as_sponsor_readable_by_viewer_id)
      remove_instance_variable(:@sponsorship_amounts_as_sponsor_readable_by_viewer_id)
    end
    if defined?(@fees_enabled_for_existing_sponsorships)
      remove_instance_variable(:@fees_enabled_for_existing_sponsorships)
    end
    if defined?(@fees_enabled_for_new_sponsorships)
      remove_instance_variable(:@fees_enabled_for_new_sponsorships)
    end
    if defined?(@public_contribution_count_for_sponsors)
      remove_instance_variable(:@public_contribution_count_for_sponsors)
    end
    remove_instance_variable(:@pending_cycle_change) if defined?(@pending_cycle_change)
    remove_instance_variable(:@enterprise_cloud_trial) if defined?(@enterprise_cloud_trial)
    remove_instance_variable(:@is_actively_sponsoring) if defined?(@is_actively_sponsoring)
  end

  # Public: Used to update Global Notices based on a site admin's 2fa configuration
  # This is public so that TwoFactorCredential can just delegate to it when a credential's state is updated.
  public def set_or_unset_staff_without_two_factor_notice
    # Avoid looking up if the user is an employee unless gh_role == staff.
    return unless has_staff_role?

    # Would they be a site_admin if we ignore the 2fa check?
    return unless site_admin_without_two_factor_check?

    # Are they a actually a site_admin? (This checks that 2fa is enabled)
    return if site_admin?

    GlobalNoticeNext.new(viewer: self).set_notice(:check_staff_has_two_factor_enabled)
  end

  def same_business?(other_user)
    false
  end

  def set_display_login
    return unless login?
    self.display_login = User.to_display_login(login)
  end

  def display_login_based_on_login
    return unless login?
    if self.read_attribute(:display_login) != User.to_display_login(login)
      errors.add :display_login, message: "cannot change display_login to value that doesn't correspond to login"
      false
    end
  end

  # Private: Remove null byte from profile name https://github.com/github/github/issues/135163
  def sanitize_profile_name
    return unless profile_name
    self.profile_name = profile_name.delete("\u0000")
  end

  MAX_THROTTLE_RETRIES = 5

  private def destroy_has_many_association(association_name)
    GitHub.logger.info("Started destroying association", {
      "code.namespace" => "User",
      "code.function" => "destroy_has_many_association",
      "gh.request_id" => GitHub.context[:request_id],
      "gh.active_record_association" => association_name.to_s,
      "gh.user.id" => id,
    })
    reflection = self.class.reflect_on_association(association_name)
    klass = reflection.klass

    association = self.send(association_name) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod

    if association.loaded?
      # If the association was loaded already, destroy records in small batches
      association.each_slice(BATCH_SIZE) do |records|
        klass.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
          association.destroy(records)
        end
      end
    else
      # If the association is not loaded, load and destroy records in small batches
      relation = association.limit(BATCH_SIZE)

      loop do
        records = relation.each { |r| r.destroyed_by_association = reflection } # domain-isolation-query-violation:ignore:packages/issues (SELECT)

        destroyed_count = klass.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
          association.destroy(records).count # domain-isolation-query-violation:ignore:packages/issues (DELETE)
        end

        relation.reset

        break if destroyed_count < BATCH_SIZE
      end
    end
    GitHub.logger.info("Finished destroying association", {
      "code.namespace" => "User",
      "code.function" => "destroy_has_many_association",
      "gh.request_id" => GitHub.context[:request_id],
      "gh.active_record_association" => association_name.to_s,
      "gh.user.id" => id,
    })
  end

  private def delete_has_many_association(association)
    reflection = self.class.reflect_on_association(association)
    klass = reflection.klass

    relation = self.send(association).limit(BATCH_SIZE) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
    loop do
      deleted_count = klass.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
        # Specific workaround for vitess-backed records. Vitess doesn't support delete_all with limits for sharded tables.
        # So this will be done with two queries for each batch - get ids -> delete where [ids]
        if klass.ancestors.include?(ApplicationRecord::Domain::IssuesPullRequests)
          ids = relation.pluck(:id)
          self.send(association).where(id: ids).delete_all # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
        else
          relation.delete_all
        end
      end

      break if deleted_count < BATCH_SIZE
    end
  end

  def parsed_event_type
    if destroyed?
      "destroy"
    elsif previous_changes["id"].present? && previous_changes["id"].first.nil?
      "create"
    else
      "update"
    end
  end
end
