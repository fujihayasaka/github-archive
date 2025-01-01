# typed: true
# frozen_string_literal: true

# An Organization is a special type of User. You cannot log into the
# site as an Organization. Instead, an organization can be fully
# administrated by any number of admins.
#
# We subclass User because they play such similar roles on the site:
# they own repositories, they follow users, they have a news feed. The
# main difference is as noted above: you can't log in as an
# organization.

class Organization < User
  include Orgs::IOrganization

  include GitHub::RateLimitable
  include Configurable::DefaultWorkflowPermissions

  include Organization::ActionsDependency
  include Organization::ArchivedDependency
  include Organization::TokenScanningDependency
  include Organization::CodeScanningDependency
  include Organization::OrganizationRolesDependency
  include MailchimpTeamListHelper
  include HydroEventHelper
  include OnboardingTasks::Taskable
  include Coders::CodableColumn
  include Business::TenantContext

  include Permissions::Attributes::Wrapper
  self.permissions_wrapper_class = Permissions::Attributes::Organization

  BATCH_SIZE = 100
  MEGA_ORG_MEMBER_THRESHOLD = 50_000
  MEGA_ORG_REPOS_THRESHOLD = MEGA_ORG_MEMBER_THRESHOLD
  REPO_INTERSECTION_THRESHOLD = Repositories::AssociatedRepositoriesDependency::AssociatedRepositories::RUBY_INTERSECTION_THRESHOLD * 2

  PRIVATE_CONFIG_AS_CODE_REPO_NAME = ".github-private"

  # Value for user-into-org transformation flag.
  TRANSFORM_FLAG = "1".freeze
  # Keep transform flags around this long if the cleanup didn't work to allow
  # time for debugging.
  TRANSFORM_FLAG_EXPIRY = 14.days

  RESTORABLE_PERIOD = 90.days

  include Instrumentation::Model
  include Organization::AbilityDependency
  include Organization::ActionsMetricsDependency
  include Organization::ApiInsightsDependency
  include Organization::ArchivedDependency
  include Organization::BetaFeaturesDependency
  include Organization::BillingManagementDependency
  include Organization::ConfigurationDependency
  include Organization::DependabotDependency
  include Organization::DependencyInsightsDependency
  include Organization::DiscussionsDependency
  include Organization::DormancyDependency
  include Organization::EnterpriseDependency
  include Organization::HovercardDependency
  include Organization::InteractionLimitsDependency
  include Organization::InvitationsDependency
  include Organization::IpAllowlistEnforcementDependency
  include Organization::ModerationDependency
  include Organization::NotificationRestrictionsDependency
  include Organization::OauthApplicationPolicyDependency
  include User::OnboardingDependency
  include Organization::PermissionsDependency
  include Organization::ProjectsDependency
  include Organization::SecurityCenterDependency
  include Organization::SecurityProductsDependency
  include Organization::UserRankedDependency
  include Organization::UserStatusDependency
  include Organization::SamlSsoEnforcementDependency
  include Organization::SponsorsDependency
  include Organization::TeamSyncDependency
  include Organization::TradeControlsDependency
  include Organization::TradeScreeningDependency
  include Organization::TwoFactorRequirementDependency
  include Organization::MemexProjectsDependency
  include Organization::PublisherVerificationDependency
  include Organization::ProfileDependency
  include Organization::ConfigRepoDependency
  include Organization::TopicsDependency
  include Organization::ProgrammaticAccessGrantDependency
  include Organization::InsightsOnboardingDependency
  include OrganizationOnboard::DemoRepositoryDependency
  include RuleEngine::RuleSettingsDependency
  include Organization::CustomerCategoryDependency
  include Organization::FeatureFlagDependency
  include Organization::IssueTypesDependency
  include Organization::LicensedCustomerDependency
  include Organization::TeamRepositoryDependency
  include Organization::DeployKeyPolicyDependency
  include KillSwitch

  serialize_with_coder :raw_data, Coders::OrganizationCoder

  alias_attribute :billing_email, :organization_billing_email

  def description
    T.unsafe(self).profile_bio
  end

  def description=(value)
    T.unsafe(self).profile_bio = value
  end

  # Thrown when someone attempts to demote the last admin to a direct member.
  class NoAdminsError < StandardError; end

  # Thrown when someone attempts to remove an emu with membership
  # that prevents the user from being removed
  class UnableToRemoveEmuError < StandardError; end

  # Thrown when someone attempts to remove an user with ET membership
  # that prevents the user from being removed
  class UnableToRemoveEnterpriseTeamMemberError < StandardError; end

  # Thrown when an attempt to transform a user into an organization
  # has failed.
  class TransformationFailed < RuntimeError; end

  # Thrown when an attempt to update the privacy of all teams is made while an
  # update is already in progress.
  class AlreadyUpdatingTeamPrivacy < StandardError
  end

  # Thrown when an attempt to suspend/unsuspend an organization fails
  class OrganizationSuspensionError < StandardError; end

  # Thrown when adding an organization member fails because the user is being added in a different transaction
  class OrganizationAddMemberNotUniqueError < StandardError; end

  # Raised when attempting to convert a non-member to a collaborator
  class CannotConvertNonMemberToCollaboratorError < StandardError; end

  # Raised when an org requires 2FA, but the member doesn't have 2FA (OK for members, but not for collaborators, so member cannot convert)
  class CannotConvertMemberToCollaboratorWithout2faError < StandardError; end

  delegate :metered_via_azure,
  :metered_via_azure?,
  to: :customer, allow_nil: true

  has_one :saml_provider,
    class_name: "Organization::SamlProvider",
    inverse_of: :target,
    dependent: :destroy

  has_one :team_sync_tenant,
    class_name: "TeamSync::Tenant",
    inverse_of: :organization,
    dependent: :destroy

  has_many :enterprise_installations, as: :owner, dependent: :delete_all

  has_many :discussion_posts, class_name: "OrganizationDiscussionPost"
  destroy_dependents_in_background :discussion_posts

  # rubocop:todo Rails/InverseOf
  has_many :org_repositories,
    -> { where(active: true) },
    class_name: "Repository",
    foreign_key: :organization_id
  # rubocop:enable Rails/InverseOf

  has_and_belongs_to_many :public_members,
    -> { distinct },
    class_name: "User",
    join_table: "public_org_members"

  has_many :migrations, foreign_key: :owner_id # rubocop:todo Rails/InverseOf
  has_many :mannequin_ownerships, foreign_key: :owner_id # rubocop:todo Rails/InverseOf
  has_many :mannequins, -> { distinct }, through: :mannequin_ownerships
  has_many :octoshift_migration_archives, inverse_of: :organization
  has_many :member_feature_requests, dependent: :delete_all
  has_many :attribution_invitations, foreign_key: :owner_id # rubocop:todo Rails/InverseOf

  has_many :enterprise_team_organization_mappings, foreign_key: :organization_id, inverse_of: :organization

  # rubocop:todo Rails/InverseOf
  has_many :teams,
    -> { where(deleted: false).order(Arel.sql("CASE WHEN teams.name = 'Owners' THEN 1 ELSE 2 END")).order("name ASC") },
    foreign_key: :organization_id,
    dependent: :destroy
  # rubocop:enable Rails/InverseOf

  # Association relationship for OauthApplicationApprovals.
  has_many :oauth_application_approvals,
    class_name: "OauthApplicationApproval",
    dependent: :delete_all

  # rubocop:todo Rails/InverseOf
  has_many :projects, -> { where(owner_type: "Organization") }, foreign_key: :owner_id
  # rubocop:enable Rails/InverseOf
  destroy_dependents_in_background :projects

  # rubocop:todo Rails/InverseOf
  has_many :memex_projects, -> { where(owner_type: "Organization") }, foreign_key: :owner_id
  # rubocop:enable Rails/InverseOf
  destroy_dependents_in_background :memex_projects

  has_many :memex_templates, through: :memex_projects

  has_many :pending_team_membership_requests, through: :teams

  private :pending_team_membership_requests

  has_many :verifiable_domains, as: :owner, dependent: :destroy

  has_many :invitations, class_name: "OrganizationInvitation", dependent: :destroy
  has_many :invitation_opt_outs, class_name: "OrganizationInvitation::OptOut", dependent: :destroy

  private :invitations

  has_many :pending_invitations,
    -> { where(OrganizationInvitation.pending.where_values_hash) },
    class_name: "OrganizationInvitation"

  has_many :repository_invitations,
    through: :org_repositories,
    class_name: "RepositoryInvitation",
    source: :repository_invitations

  has_many :pending_collaborators, through: :repository_invitations, class_name: "User", source: :invitee, disable_joins: true

  has_many :hooks, as: :installation_target, dependent: :destroy

  has_one :business_membership, class_name: "Business::OrganizationMembership"
  has_one :business, through: :business_membership
  # rubocop:todo Rails/InverseOf
  has_many :business_invitations,
    class_name: "BusinessOrganizationInvitation",
    foreign_key: :invitee_id,
    dependent: :destroy
  # rubocop:enable Rails/InverseOf

  has_many :organization_profile_emails
  destroy_dependents_in_background :organization_profile_emails

  has_many :organization_membership_entries
  destroy_dependents_in_background :organization_membership_entries

  # rubocop:todo Rails/InverseOf
  has_many :marketplace_order_previews, class_name: "Marketplace::OrderPreview", dependent: :destroy, foreign_key: :account_id
  # rubocop:enable Rails/InverseOf

  has_many :credential_authorizations, class_name: "Organization::CredentialAuthorization"
  destroy_dependents_in_background :credential_authorizations

  has_many :roles, as: :owner, class_name: "::Role", dependent: :destroy

  has_many :ssh_certificate_authorities, as: :owner, dependent: :destroy

  has_many :ip_allowlist_entries, as: :owner, dependent: :destroy

  has_many :billing_external_emails, as: :owner, dependent: :delete_all

  has_many :policy_groups, as: :owner, class_name: "Codespaces::PolicyGroup", dependent: :destroy
  has_many :policy_group_memberships, as: :target, class_name: "Codespaces::PolicyGroupMembership", dependent: :destroy

  has_many :rulesets, as: :source, class_name: "RepositoryRuleset"
  destroy_dependents_in_background :rulesets

  has_many :private_registry_configurations, as: :owner, class_name: "PrivateRegistry::Configuration", dependent: :destroy

  # Only organizations can have user_labels, so it's defined in this class
  # rather than being defined on `User`
  has_many :user_labels, foreign_key: :user_id # rubocop:todo Rails/InverseOf
  destroy_dependents_in_background :user_labels

  has_one :soft_deleted_organization, dependent: :destroy
  has_one :terms_of_service_acceptance, class_name: "Organization::TermsOfServiceAcceptance"
  has_one :terms_of_service_corporate_upgrade_prompt,
    -> { where(upgraded_terms_type: :corporate) },
    class_name: "Organization::TermsOfServiceUpgradePrompt"
  has_one :terms_of_service_esa_education_upgrade_prompt,
    -> { where(upgraded_terms_type: :esa_education) },
    class_name: "Organization::TermsOfServiceUpgradePrompt"

  scope :excluding_github_enterprise_org, -> do
    where.not(login: Business::EXCLUDE_FROM_SINGLE_BUSINESS_ORGS)
  end

  scope :active, -> { where.missing(:soft_deleted_organization) }
  scope :soft_deleted, -> { joins(:soft_deleted_organization) }
  scope :purgeable, -> { soft_deleted.where("soft_deleted_organizations.created_at < ?", RESTORABLE_PERIOD.ago) }

  # Internal: an abstract collection, for the sub-resources of an Organization available for abilities
  def resources
    Organization::Resources.new(self)
  end

  # Organizations whose OAuth application policy allows the given application
  # to access the organization's resources.
  def self.oauth_app_policy_met_by(app)
    raise ArgumentError, "OAuth app required" if app.nil?

    if GitHub.flipper[:orgs_oap_met_by_first_party].enabled? && app.blockable_client_app?
      first_party_oap_met_by(app)
    else
      third_party_oap_met_by(app)
    end
  end

  def self.third_party_oap_met_by(app)
    raise ArgumentError, "OAuth app required" if app.nil?

    return scoped if app.third_party_oap_exempt?

    join_sql = "LEFT OUTER JOIN oauth_application_approvals
                 ON oauth_application_approvals.organization_id = users.id
                 AND oauth_application_approvals.state = 1"

    conditions = "(users.restrict_oauth_applications IS NULL OR users.restrict_oauth_applications = 0)
                  OR (users.id = ?)
                  OR (oauth_application_approvals.application_id = ?)"

    results = joins(join_sql).where([conditions, app.user_id, app.id]).distinct

    if GitHub.flipper[:instrument_oap_met_by].enabled?
      GitHub.dogstats.distribution("organizations.third_party_oap_met_by", results.size)
    end

    results
  end

  def self.first_party_oap_met_by(app)
    raise ArgumentError, "OAuth app required" if app.nil?
    return scoped if !app.blockable_client_app?

    feature = FlipperFeature.where(name: "first_party_oauth_app_restrictions").first
    return scoped unless feature

    if GitHub.flipper[:consider_business_oap_ff].enabled?
      business_ids_enabled = feature.actor_ids_by_class.to_h[Business]
      business_org_ids_enabled = Business.where(id: business_ids_enabled).joins(:organization_memberships).pluck(:organization_id)

      org_ids_enabled = feature.actor_ids_by_class.to_h[Organization] || []

      org_ids_enabled = org_ids_enabled.concat(business_org_ids_enabled).uniq
    else
      org_ids_enabled = feature.actor_ids_by_class.to_h[Organization]
    end

    return scoped if org_ids_enabled.blank?

    join_sql = "LEFT OUTER JOIN oauth_application_approvals
                 ON oauth_application_approvals.organization_id = users.id
                 AND oauth_application_approvals.application_id != ?
                 AND users.id IN (?)"

    conditions = "(users.restrict_oauth_applications IS NULL OR users.restrict_oauth_applications = 0)
                  OR (users.id = ?)
                  OR (users.restrict_oauth_applications = 1 AND NOT EXISTS
                        (SELECT id FROM oauth_application_approvals
                          WHERE organization_id = users.id
                          AND state = 3
                          AND application_id = ?
                          LIMIT 1
                        )
                      )"

    joins(sanitize_sql_array([join_sql, app.id, org_ids_enabled])).where([conditions, app.user_id, app.id]).distinct
  end

  def change_owner_of!(project:, creator:, old_owner:)
    # Set up abilities as if this were a newly-created org project
    project.owner_dependent_added
    project.grant_write_to_owning_org_after_commit
    project.update_user_permission(creator, :admin) if member?(creator)
  end

  # Organizations whose OAuth application policy expressly denies the given
  # application access to the organization's resources.
  scope :oauth_app_policy_denies, lambda { |app|
    raise ArgumentError, "OAuth app required" if app.nil?

    # organization restricts OAuth applications
    # AND organization has denied the app

    joins = "INNER JOIN oauth_application_approvals
               ON oauth_application_approvals.organization_id = users.id
               AND oauth_application_approvals.state = 2"

    conditions = "(users.restrict_oauth_applications = 1)
                  AND (oauth_application_approvals.application_id = ?)"

    joins(joins).where(conditions, app.id)
  }

  # Organizations whose OAuth application policy expressly blocks the given
  # application access to the organization's resources.
  scope :oauth_app_policy_blocks, lambda { |app|
    raise ArgumentError, "OAuth app required" if app.nil?

    # FF is enabled for organization (or their business)
    # AND organization has blocked the app
    # AND organization restricts OAuth applications

    feature = FlipperFeature.find_by(name: "first_party_oauth_app_restrictions")
    return scoped.none unless feature

    if GitHub.flipper[:consider_business_oap_ff].enabled?
      business_ids_enabled = feature.actor_ids_by_class.to_h[Business]
      business_org_ids_enabled = Business.where(id: business_ids_enabled).joins(:organization_memberships).pluck(:organization_id)

      org_ids_enabled = feature.actor_ids_by_class.to_h[Organization] || []

      org_ids_enabled = org_ids_enabled.concat(business_org_ids_enabled).uniq
    else
      org_ids_enabled = feature.actor_ids_by_class.to_h[Organization]
    end

    return scoped.none if org_ids_enabled.blank?

    join_sql = "INNER JOIN oauth_application_approvals
      ON oauth_application_approvals.organization_id = users.id
      AND oauth_application_approvals.state = 3
      AND users.id IN (?)"

    conditions = "(users.restrict_oauth_applications = 1)
      AND (oauth_application_approvals.application_id = ?)"

    joins(sanitize_sql_array([join_sql, org_ids_enabled])).where([conditions, app.id]).distinct
  }

  scope :business_plus, -> {
    where(plan: GitHub::Plan::BUSINESS_PLUS)
  }

  scope :failed_billing_transition, -> {
    active.
    joins(:business_membership).
    joins(:business).
    where("business_organization_memberships.created_at < ?", 90.minutes.ago).
    merge(::Business.where("downgraded_at IS NULL")).
    merge(::Business.not_staff_owned).
    merge(::Business.not_trial).
    where("plan != 'business_plus' OR plan IS NULL")
  }

  before_validation :initialize_application_policy, on: :create

  validates_presence_of :admins, unless: -> do
    T.bind(self, Organization)
    !!skip_admins_presence_validation
  end
  validates_presence_of :billing_email, if: :billing_email_required?
  validate :must_be_org_plan, :gravatar_email_must_be_an_email
  validates :billing_email, unicode3: true
  validate :billing_email_is_unique
  validate :cannot_add_sanctioned_billing_emails
  validate :cannot_add_disposable_billing_emails, on: :create
  validate :cannot_add_disposable_billing_emails, on: :update, if: :organization_billing_email_changed?
  validates :description, length: { maximum: Profile::BIO_MAX_LENGTH }, allow_blank: true, on: :update

  after_commit :add_initial_admins, on: :create

  after_commit :delist_marketplace_apps, on: [:create, :update], if: -> do
    T.bind(self, Organization)
    previous_changes[:spammy]
  end
  after_commit :set_spammy_notice, on: [:create, :update], if: -> do
    T.bind(self, Organization)
    previous_changes[:spammy]
  end

  after_commit :set_billingless_org_notice, on: [:create, :update]
  after_commit :set_disabled_org_billing_notice, on: [:create, :update]
  after_commit :set_disabled_org_repos_notice, on: [:create, :update]

  after_update_commit :instrument_billing_email_change, if: :saved_change_to_organization_billing_email?

  after_commit :populate_initial_user_labels, on: :create

  after_create :set_display_commenter_full_name_for_enterprise

  after_commit :update_repository_projects_setting, if: :repository_projects_setting_changed?
  after_commit :update_organization_projects_setting, if: :organization_projects_setting_changed?

  after_commit :remove_user_moderators, on: :destroy

  after_commit  :insights_publish_plan_change, if: :saved_change_to_plan?, on: [:create, :update]
  after_destroy :insights_publish_user_destroy

  before_save :update_company

  before_destroy :check_trusted_oauth_apps_owner
  before_destroy :add_admins_to_instrumentation
  # This is a before_destroy callback because we want to ensure that the
  # the customer object or business object is available on the organization at the time of
  # instrumentation. By the time an after commit hook is called the customer object
  # has already been ready destroyed by dependent destroy calls this is also why we prepend this call.
  before_destroy :instrument_before_destroy, prepend: true # rubocop:disable GitHub/AfterCommitCallbackInstrumentation
  after_destroy :remove_business_user_accounts_for_members, if: :remove_business_user_accounts_for_members?

  before_destroy :remove_custom_property_definitions

  after_create :initialize_workflow_permissions
  after_create :initialize_deploy_key_policy

  before_destroy :cancel_enterprise_subscription_items!

  # Naturally.
  def organization?
    true
  end

  # Users are users, Orgs are orgs, Mannequins are mannequins
  def user?
    false
  end

  # Organizations on the legacy plan cannot use organization secrets.
  def can_use_org_secrets?
    Billing::ActionsPermission.new(self).status[:error][:reason] != "PLAN_INELIGIBLE" || GitHub.enterprise?
  end

  # Users are users, Orgs are orgs, Mannequins are mannequins
  def mannequin?
    false
  end

  # For routing and whatnot.
  def user
    self
  end

  def email_address_required?
    false
  end

  # Public: Should the Organization Orchestrator be used when adding/removing Org members?
  def use_organization_orchestrator?
    feature_enabled?(:organization_add_remove_orchestrator) || business&.feature_enabled?(:organization_add_remove_orchestrator)
  end

  def remove_business_user_accounts_for_members?
    return false if GitHub.single_business_environment? || enterprise_managed_user_enabled? || business&.supports_unaffiliated_user_accounts?
    true
  end

  # Public: Determine if the billing email is required to create the Organization.
  #
  # Returns true if required, false otherwise.
  def billing_email_required?
    GitHub.billing_enabled?
  end

  def password_required?
    # Organizations don't have passwords - you can't log in as them.
    false
  end

  def avatar_editable_by?(user)
    adminable_by?(user)
  end

  # Public: An Organization can never be authenticated by a password.
  #
  # Returns false
  def authenticated_by_password?(password = nil)
    GitHub.dogstats.increment("user", tags: ["action:org_login_attempt"])
    false
  end

  # Public: can this Organization be orphaned (can last admin be removed)?
  #         We [currently] only allow Organizations to be orphaned via a SAML or SCIM operation,
  #         and only if the Organization belongs to an Enterprise account, where the Enterprise
  #         owners will have UI to reclaim ownership of any orphaned organizations.
  # Return true if: - Organization is owned by a Business
  #                 - Business has the :enterprise_idp_provisioning feature flag turned on
  #                 - Business has SAML enabled
  # Also returns true if the organization is present inside a cancelled enterprise trial, since we
  # need to ensure that all members are removed from the organization.
  def can_be_orphaned?
    return false if business.nil?
    return true if T.must(business).trial_cancelled?
    return false unless T.must(business).feature_enabled?(:enterprise_idp_provisioning)
    # If SAML is enabled on the Enterprise, SCIM de-provisioning is automatically enabled
    # (SAML deprovisioning is a configurable option)
    T.must(business).saml_sso_enabled?
  end

  # Public: Is user the last remaining admin of this organization?
  def last_admin?(user)
    adminable_by?(user) && members_count(action: :admin) == 1
  end

  # Public: If the given user is the last admin of the org, then raise an error
  # and log pertinent info
  #
  # Returns NoAdminsError or nil
  def prevent_removal_of_last_admin!(user, error_message)
    return unless last_admin?(user)

    GitHub.logger.info(
      "code.namespace": "Organization#prevent_removal_of_last_admin!",
      "code.function": "prevent_removal_of_last_admin!",
      "gh.org": self,
      "gh.org.id": id,
      "gh.thisuser": user,
      "gh.thisuser.id": user.id,
    )
    raise NoAdminsError.new(error_message)
  end

  # Public: find a member of any of this organization's teams given their login.
  def find_team_member_by_login(login)
    all_team_members.find_by_login(login)
  end

  # Public: find a direct member or a member of any of this organization's teams given their login.
  def find_direct_or_team_member_by_login(login)
    members.find_by_login(login)
  end

  # Public: Add the specified user as an admin of this org.
  #
  # user        - The user to make an admin.
  # adder       - The user doing the adding.
  # invitation  - The optional OrganizationInvitation inviting the user
  # skip_notifications - Skip sending notifications
  #
  # Returns nothing.
  def add_admin(user, adder: nil, invitation: nil, skip_notifications: false)
    add_member(user, action: :admin, adder: adder, invitation: invitation, skip_notifications:)
  end

  # Public: Add a member to this organization
  #
  # user        - the user to add as a member
  # action:     - action to update to. A symbol, :read, :write, or :admin. Defaults
  #               to :read
  # adder       - the entity adding the user to the team, i.e. team, user, etc
  # invitation  - The optional OrganizationInvitation inviting the user
  # team        - The optional team parameter is an external_group backed team that grants user org membership
  # rescue_not_unique        - The optional rescue_not_unique parameter determines whether we want to throw OrganizationAddMemberNotUniqueError
  #                            upon ActiveRecord::RecordNotUnique when granting an ability to the user. Defaults to false.
  # skip_license_usage_update - A boolean indicating whether to skip the license usage update
  #                             becasue it will be triggered elsewhere
  # skip_notifications - Skip sending notifications
  #
  # Returns nothing.
  def add_member(user, action: :read, adder: nil, perform_instrumentation: true, invitation: nil, team: nil, rescue_not_unique: false, skip_license_usage_update: false, skip_notifications: false, caller_type: nil)
    return if direct_member?(user)

    return unless (two_factor_requirement_enabled? && members_without_2fa_allowed?) || two_factor_requirement_met_by?(user)
    return unless meets_sso_requirements?(user: user)

    if use_organization_orchestrator?
      return unless persisted? && user.persisted?
      return OrganizationOrchestration.add_users(actor: adder, action: action.to_s, business_id: business&.id, organizations: [self], teams: [team].compact, users: [user], caller_type: caller_type, invitation_id: invitation&.id, perform_instrumentation: perform_instrumentation, skip_license_usage_update:, skip_notifications:).execute(synchronous: true)
    end

    grant(user, action)

    OrganizationCollaborator.where(organization_id: id, user_id: user.id).destroy_all if organization_collaborator_cache_write?

    if perform_instrumentation
      instrument_add_members([user], action, adder, invitation, caller_type)
    end

    publicize_member(user) if GitHub.default_org_membership_visibility_public?
    add_user_to_business(user) if business.present?

    # If the organization is being created, the Organization::Creator will send the email after
    # billing has succeeded.
    OrganizationMailer.admin_added(user, self, adder).deliver_later if action == :admin && !being_created?

    if !being_created?
      IntegrationInstallation.where(target: self).pluck(:id).each do |installation_id|
        UpdateIntegrationInstallationRateLimitJob.perform_later(installation_id)
      end
    end

    Contribution.clear_caches_for_user(user, context: "add_org_member")
    business&.update_license_usage unless skip_license_usage_update
    user.synchronize_search_index

    # When a user is added to an org, check if we need to subscribe them to the mailchimp team list
    MailchimpTeamListJob.perform_later(user: user, org: self) if GitHub.mailchimp_enabled?

    begin
      add_organization_membership_entry(user: user, team: team, adder: adder, caller_type: caller_type)
    rescue ActiveRecord::RecordNotUnique => e
      # no-op for now
    end

    EnterpriseCloudTrialNoticeForNewMembersJob.perform_later([user]) if business_plus?

    nil
  end

  # Public: Add a member to this organization
  #
  # user        - the user to add as a member
  # adder       - the entity adding the user to the team, i.e. team, user, etc
  # team        - The optional team parameter is an external_group backed team that grants user org membership
  # skip_license_usage_update - A boolean indicating whether to skip the license usage update
  #                             becasue it will be triggered elsewhere
  #
  # Returns nothing.
  def add_member_with_failover(user, adder: nil, team: nil, skip_license_usage_update: false)
    begin
      add_member(user, adder: adder, team: team, rescue_not_unique: true, skip_license_usage_update: skip_license_usage_update)
    rescue OrganizationAddMemberNotUniqueError => e
      entry = add_organization_membership_entry(user: user, team: team, adder: adder)

      GitHub.logger.info({
        "code.namespace" => self.class.name,
        "code.function" => "add_member_with_failover",
        "info.message" => "organization.add_member record not unique",
        "gh.team.name" => team&.name,
        "gh.team.id" => team&.id,
        "gh.organization.name" => display_login,
        "gh.organization.id" => id,
        "gh.user.id" => user&.id,
        "gh.organization_membership_entry.id" => entry&.id,
        "gh.backtrace" => T.must(e.backtrace).join("\n"),
      })
    end
  end

  # Public: Bulk add members to this organization via a team.
  #
  # This is currently only used by the Team#add_member_bulk method during EMU team link events.
  #
  # users       - an array of users to add as a member
  # action:     - action to update to. A symbol, :read, :write, or :admin. Defaults
  #               to :read
  # invitation  - The optional OrganizationInvitation inviting the user
  # team        - The optional team parameter is an external_group backed team that grants user org membership
  # skip_license_usage_update - A boolean indicating whether to skip the license usage update
  #   becasue it will be triggered elsewhere
  # skip_user_synchronize_index - A boolean indicating whether to skip synchronize_search_index calls
  # synchronous_orchestration - Perform orchestration synchronously instead of through a background job
  #
  # Returns nothing.
  def bulk_add_members(users, action: :read, adder: nil, perform_instrumentation: true, invitation: nil, team: nil, skip_license_usage_update: false, caller_type: nil, skip_user_synchronize_index: false, synchronous_orchestration: false)
    return unless users.is_a?(Array)
    return if users.empty?

    # Get all direct members of the organization
    user_ids = users.map(&:id).sort

    if use_organization_orchestrator?
      return OrganizationOrchestration.add_users(actor: adder, action: action.to_s, business_id: business&.id, organizations: [self], teams: [team].compact, users: users, caller_type: caller_type, invitation_id: invitation&.id, perform_instrumentation: perform_instrumentation, skip_license_usage_update:).execute(synchronous: synchronous_orchestration)
    end

    direct_member_ids = ActiveRecord::Base.connected_to(role: :reading) { member_ids(actor_ids: user_ids) }.sort

    # get the new members that need to be added
    unafilliated_user_ids = user_ids - direct_member_ids

    # no new users just return
    return if unafilliated_user_ids.empty?

    unafilliated_users = users.select { |user| unafilliated_user_ids.include?(user.id) }

    # 2FA is not required for EMU users
    unless scim_managed_enterprise?
      return unless unafilliated_users.all? { |user| two_factor_requirement_met_by?(user) }
    end

    return unless meets_sso_requirements_for_users?(user_ids: unafilliated_user_ids)

    if GitHub.flipper["authz_no_bulk_grant_transaction"].enabled?
      bulk_grant_unafilliated(unafilliated_users, action)
    else
      Ability.transaction do
        bulk_grant(unafilliated_users, action)
      end
    end

    OrganizationCollaborator.where(organization_id: id, user_id: user_ids).destroy_all if organization_collaborator_cache_write?

    if perform_instrumentation
      instrument_add_members(unafilliated_users, action, adder, invitation, caller_type)
    end

    bulk_publicize_members(unafilliated_users) if GitHub.default_org_membership_visibility_public?
    bulk_add_users_to_business(unafilliated_user_ids) if business.present?

    if !being_created?
      IntegrationInstallation.where(target: self).pluck(:id).each do |installation_id|
        # performed in the background
        UpdateIntegrationInstallationRateLimitJob.perform_later(installation_id)
      end
    end

    Contribution.bulk_clear_caches_for_users(unafilliated_users, context: "bulk_add_org_members")
    business&.update_license_usage unless skip_license_usage_update

    # the following operations are performed in the background, or do not need to be done in bulk
    perform_user_operations_single_mode(unafilliated_users, adder, action, skip_user_synchronize_index:)

    # the team passed in knows if it is ET managed or not, can figure entry adder itself
    bulk_add_organization_membership_entry(user_ids: unafilliated_user_ids, team: team, adder: adder, caller_type: caller_type)

    nil
  end

  # Public: Called after members were bulk added.
  # users       - an array of users to add as a member
  # action:     - action to update to. A symbol, :read, :write, or :admin. Defaults
  #               to :read
  # actor       - the entity adding the user to the team, i.e. team, user, etc
  # team        - The optional team parameter is an external_group backed team that grants user org membership
  # caller_type - The optional caller_type parameter is the type of the entity adding the user to the team
  sig { params(users: T::Array[User], action: Symbol, actor: User, team: T.nilable(Team), caller_type: T.nilable(Symbol)).void }
  def bulk_added_members(users:, action:, actor:, team: nil, caller_type: nil)
    instrument_add_members(users, action, actor, nil, caller_type)
    bulk_publicize_members(users) if GitHub.default_org_membership_visibility_public?
    if action == :admin
      users.each do |user|
        OrganizationMailer.admin_added(user, self, actor).deliver_later
      end
    end
  end

  # Protected: Called from bulk_add_members operations that are performed in a single mode
  #
  # Returns: nothing
  def perform_user_operations_single_mode(unaffiliated_users, adder, action, skip_user_synchronize_index: false)
    unaffiliated_users.each do |user|
      # If the organization is being created, the Organization::Creator will send the email after
      # billing has succeeded.
      OrganizationMailer.admin_added(user, self, adder).deliver_later if action == :admin && !being_created?

      user.synchronize_search_index unless skip_user_synchronize_index

      # When a user is added to an org, check if we need to subscribe them to the mailchimp team list
      MailchimpTeamListJob.perform_later(user: user, org: self) if GitHub.mailchimp_enabled?
    end

    EnterpriseCloudTrialNoticeForNewMembersJob.perform_later(unaffiliated_users) if business_plus?
  end

  # Public: adds organization membership entry for the given user if the user is a member of the organization
  #
  # user - the user who is being added to the organization
  # team - the team that the user is being added to
  # adder - the user who is adding the user to the organization explicitly
  #
  # Returns nothing
  def add_organization_membership_entry(user:, team: nil, adder: nil, caller_type: nil)
    ability = user.get_organization_ability(id)
    return if ability.nil?

    # OME are added for ETs whether it is EMU enabled or not
    if EnterpriseTeam.enabled_for_organizations?(business: business) && team.present?
      if caller_type == :enterprise_team
        # derived parameter is unused here and will be deleted with FF
        OrganizationMembershipEntry.create_entry(user: user, organization_id: id, adder_id: team.id, ability_id: ability.id, derived: true, adder_type: :enterprise_team)
        return
      end
    end

    # organization membership entries are added only for EMU enabled enterprises or
    # the user is the creator of the organization and enterprise managed.
    return unless enabled_for_emu?(user: user) || enterprise_server_scim_enabled?

    via_external_team = team.present? && team.externally_managed?
    if via_external_team
      adder_id = team.id
    else
      adder_id = adder.present? ? adder.id : admins.first.id
    end

    if EnterpriseTeam.enabled_for_organizations?(business: business)
      adder_type = via_external_team ? :external_team : :admin
      OrganizationMembershipEntry.create_entry(user: user, organization_id: id, adder_id: adder_id, ability_id: ability.id, derived: via_external_team, adder_type: adder_type)
    else
      OrganizationMembershipEntry.create_entry(user: user, organization_id: id, adder_id: adder_id, ability_id: ability.id, derived: via_external_team)
    end
  end

  # Public: adds organization membership entries for a set of users if the users are members of the organization
  #
  # user_ids - the user ids for users who are being added to the organization
  # team - the team that the users are being added to
  # adder - the user who is adding the user to the organization explicitly
  #
  # Returns nothing
  def bulk_add_organization_membership_entry(user_ids:, team: nil, adder: nil, process_users_no_ability: false, adder_type: nil, caller_type: nil)
    abilities = Ability.user_direct_read_on_organization(
      actor_id: user_ids,
      subject_id: id,
    )
    return unless abilities.any?

    # OME are added for ETs whether it is EMU enabled or not
    if EnterpriseTeam.enabled_for_organizations?(business: business) && team.present?
      if caller_type == :enterprise_team
        # derived parameter is unused here and will be deleted with FF
        OrganizationMembershipEntry.bulk_create_entry(abilities: abilities, organization_id: id, adder_id: team.id, derived: true, adder_type: :enterprise_team)
        if adder_type == :admin
          OrganizationMembershipEntry.bulk_create_entry(abilities: abilities, organization_id: id, adder_id: team.id, derived: true, adder_type: :admin)
        end
        return
      end
    end

    # organization membership entries are added only for EMU enabled enterprises or
    # the user is the creator of the organization and enterprise managed.
    return unless scim_managed_enterprise?

    via_external_team = team.present? && team.externally_managed?

    if via_external_team
      adder_id = team.id
    else
      adder_id = adder.present? ? adder.id : admins.first&.id
    end

    return if adder_id.blank?
    if EnterpriseTeam.enabled_for_organizations?(business: business)
      adder_type = via_external_team ? :external_team : :admin
      OrganizationMembershipEntry.bulk_create_entry(abilities: abilities, organization_id: id, adder_id: adder_id, derived: via_external_team, adder_type: adder_type)
    else
      OrganizationMembershipEntry.bulk_create_entry(abilities: abilities, organization_id: id, adder_id: adder_id, derived: via_external_team)
    end
  end

  # Public: Determine whether the user is the creator of the organization
  #
  # Returns boolean
  def creator_of_organization?(user:)
    return false unless user.user?
    user.id == creator&.id
  end

  def enabled_for_emu?(user:)
    enterprise_managed_user_enabled? || (creator_of_organization?(user: user) && user.is_enterprise_managed?)
  end

  def invitation_rate_limit_exceeded?
    # Don't rate limit org invites if they aren't enabled
    return false if bypass_org_invitations?

    limit_policy = OrganizationInvitation::RateLimitPolicy.new(self)
    limit_key = "orgs/invitations.new:org-#{id}"
    max_tries = limit_policy.limit
    rate_limit_increment(limit_key, { max_tries: max_tries, ttl: limit_policy.ttl }).at_limit?
  end

  def invitation_rate_limit_error_message
    limit_policy = OrganizationInvitation::RateLimitPolicy.new(self)
    max_tries = limit_policy.limit
    "You have exceeded the organization invitation rate limit of #{max_tries} per 24 hours."
  end

  # Public: Update a member's permission on this organization.
  #
  # user    - the user whose membership is being modified
  # action: - action to update to. A symbol, :read, :write, or :admin.
  # updater: - this ends up as the actor if it's not nil
  #
  # Returns nothing.
  def update_member(user, action:, updater: nil)
    return unless direct_member?(user)

    unless action == :admin
      prevent_removal_of_last_admin!(user, "You can't demote the last admin")
    end

    previous_action = Authorization.service.most_capable_action_between(actor: user, subject: self).to_sym

    if action != previous_action
      update_member_without_callbacks_and_notifications(user, action: action)

      instrument_options = { user: user, permission: action, old_permission: previous_action }
      instrument_options[:actor] = updater if updater.present?
      if GitHub.context[:hide_staff_user] && GitHub.guard_audit_log_staff_actor?
        instrument_options.merge!(GitHub.guarded_audit_log_staff_actor_entry(updater))
      end

      instrument(:update_member, instrument_options)

      if action == :admin
        CancelTeamMembershipRequestsJob.perform_later(id, user.id)
        OrganizationMailer.admin_added(user, self).deliver_later
      else
        # Clean up notifications and forks for repos that the user no longer has access to
        repository_ids = Array(repositories.pluck(:id))
        CleanupListNotificationsJob.perform_later(user.id, "Repository", repository_ids)
        RemoveForksForInaccessibleRepositoriesJob.perform_later(repository_ids, Array(user.id))

        if user.has_trade_screening_record_linked_to_org?(organization: self)
          user.unlink_trade_screening_record_from_org(organization: self)
        end
      end

      revoke_org_programmatic_access_grants_if_demoted_from_admin(user, previous_action)

      if (action == :admin) || (previous_action == :admin)
        # Enroll or unenroll team admin campaign when admin status changes
        MailchimpTeamListJob.perform_later(user: user, org: self) if GitHub.mailchimp_enabled?
      end
    end

    cancel_all_invitations_involving(user)

    nil
  end

  # Public: update a member directly skipping callbacks and other checks.
  def update_member_without_callbacks_and_notifications(user, action:)
    grant(user, action)
  end

  # Public: retrieve all failed organization invitations
  def failed_invitations
    invitations.failed
  end

  # Public: retrieve all failed repository invitations (i.e. outside collaborators)
  def failed_repo_invitations
    repository_invitations.all_expired
  end

  def active_failed_invitations
    failed_invitations.where(cancelled_at: nil) + failed_repo_invitations
  end

  # Public: count of active failed organization invitations. This avoids getting all failed invitation and
  # failed repo invitations records.
  def active_failed_invitations_count
    failed_invitations.where(cancelled_at: nil).count + failed_repo_invitations.count
  end

  # Public: Queues job to restore membership with user's previous settings.
  def restore_membership(restorable_organization_user, actor:)
    return if restorable_organization_user.blank?
    return if restorable_organization_user.is_a?(Restorable::NullOrganizationUser)

    status = JobStatus.create(id: "restorable_#{restorable_organization_user.id}")
    RestoreOrganizationUserJob.enqueue(
      restorable_organization_user: restorable_organization_user,
      actor: actor,
    )
  end

  # Public: Asynchronous version of convert_to_outside_collaborator!
  #
  # see: Organization#convert_to_outside_collaborator!
  #
  # Raises CannotConvertNonMemberToCollaboratorError.
  #
  # Returns nothing.
  def convert_to_outside_collaborator(member, save_settings: true)
    unless direct_or_team_member?(member)
      raise CannotConvertNonMemberToCollaboratorError, "Can only be called on an org member"
    end

    ConvertToOutsideCollaboratorJob.perform_later(id, member.id, { save_settings: save_settings })
  end

  # Public: Remove an org member from the org and all their teams, then use
  # direct abilities to replicate the permissions they once had from those
  # teams.
  #
  # member - org member to migrate.
  #
  # Raises CannotConvertNonMemberToCollaboratorError or CannotConvertMemberToCollaboratorWithout2faError.
  #
  # Returns nothing.
  def convert_to_outside_collaborator!(member, save_settings: true)
    unless direct_or_team_member?(member)
      raise CannotConvertNonMemberToCollaboratorError, "Can only be called on an org member"
    end

    # remove after https://github.com/github/authorization/issues/4526
    if two_factor_requirement_enabled? && !member.two_factor_authentication_enabled?
      raise CannotConvertMemberToCollaboratorWithout2faError, "Cannot convert member without 2FA to outside collaborator, 2FA required for outside collaborators"
    end

    if save_settings
      save_organization_settings_for_user(member)
    end

    convert_team_permissions_to_direct_abilities(member)

    remove_member(member,
      remove_direct_repo_access: false,
      send_notification:         false,
      save_settings:             false,
    )

    GitHub.dogstats.increment("organization", tags: ["action:convert_to_outside_collaborator"])
  end

  # Public: Asynchronous version of remove_outside_collaborator!
  #
  # see: Organization#remove_outside_collaborator!
  #
  # Returns nothing.
  def remove_outside_collaborator(user, save_settings: true, reason: nil, send_notification: true)
    # If SAML SSO is used and this is not a result of 2FA enforcement, we don't want to save a restorable when
    # removing the outside collaborator as doing so would allow the user who has a valid SSO login to reinstate
    # themselves an outside collaborator instead of member. This is not what customers expect as this would allow
    # the user to continue to access the organization repo without using SSO.
    save_settings = saml_sso_enabled? && reason != Organization::RemovedMemberNotification::TWO_FACTOR_REQUIREMENT_NON_COMPLIANCE ? false : save_settings

    RemoveOutsideCollaboratorFromOrganizationJob.perform_later(user.id, id, { save_settings: save_settings, reason: reason, send_notification: send_notification })
  end

  # Public: Remove an outside collaborator from the organization.
  #
  # Since outside collaborators are only associated with an organization by
  # being a member of some of its repositories, this method works by removing
  # the user as a collaborator from all of the organization's repositories.
  #
  # NOTE: It is STRONGLY recommended that you only call this from a background job.
  #
  # user - User to remove as an outside collaborator.
  #
  # save_settings - Boolean indicating whether a Restorable record should be saved
  #
  # reason - reason the collaborator was removed.
  #          (e.g. :two_factor_requirement_non_compliance)
  #
  # send_notification - Boolean indicating whether an email notification should
  #                     be delivered
  #
  # Returns nothing.
  def remove_outside_collaborator!(user, save_settings: true, reason: nil, send_notification: true)
    # we must find all the repos that a user might be collaborating on, so we cannot have a limit
    collab_repos = collaborating_repositories_for_user(user, limit: nil)

    return unless user_is_outside_collaborator?(user.id, collab_repos.pluck(:id))

    if save_settings
      save_organization_settings_for_user(user)
    end

    membership_types = role_of(user).types

    remove_direct_repo_access(user, collab_repos)
    remove_user_email_setting_for_org(user)

    if send_notification && !user.suspended?
      repo_names = collab_repos.map(&:name_with_owner)
      OrganizationMailer.remove_outside_collaborator(user, self, repo_names, reason.to_s).deliver_later
    end

    RemoveOrgMemberForksJob.enqueue(self, user)
    RemoveOrgMemberWatchedRepositoriesJob.enqueue(self, user)
    RemoveOrgMemberRepositoryStarsJob.enqueue(self, user)
    RemoveOrgMemberIssueAssignmentsJob.perform_later(self, user)
    RemoveOrgMemberProjectsNextAccessJob.perform_later(self, user)

    Licensing::SnapshotLicensesJob.perform_later(business) if delegate_billing_to_business?
    business&.update_license_usage

    instrument :remove_outside_collaborator,
      user: user,
      reason: reason,
      membership_types: membership_types

  end

  # Public: Asynchronous version of Organization#remove_member.
  #
  # This is the one you want to call as it performs the removal in a background job, avoiding timeouts.
  #
  # See: Organization#remove_member!
  #
  # user - User whose membership is being revoked.
  # remove_direct_repo_access - Boolean indicating whether or not the user should
  #   also be removed from all the repos they have direct access to.
  # send_notification - Boolean indicating whether or not the user should be sent
  #   a notification about being removed from the org.
  # reason - String representing the reason for removal.
  # background_team_remove_member - Boolean indicating whether calls to
  #   Team#remove_member should be queued for deletion in the background.
  # allow_last_admin_removal - Boolean indicating whether to allow removing the last
  #   admin. Only applicable to organizations that are owned by a Business and whose
  #   membership is managed by an external Identity Provider.
  # caller_type - Symbol indicating the type of caller. Used to allow/disallow removal
  #
  # Returns nothing.
  def remove_member(
    user,
    remove_direct_repo_access: true,
    send_notification: true,
    save_settings: true,
    reason: nil,
    background_team_remove_member: false,
    allow_last_admin_removal: false
  )
    return if user.nil?

    unless allow_last_admin_removal && can_be_orphaned?
      # this raises an error if there is an attempt to remove the last admin
      # we need to do this before initiating the background job
      prevent_removal_of_last_admin!(user, "You can't remove the last admin")
    end

    if prevent_removal_of_scim_managed_user?(user: user, reason: :enterprise_team, db_connection: :writing)
      # if the user has ET membership, then the user cannot be removed
      raise UnableToRemoveEnterpriseTeamMemberError.new("Unable to remove enterprise team member #{user.display_login} from the organization")
    end

    if prevent_removal_of_scim_managed_user?(user: user, reason: :derived, db_connection: :writing)
      # if the user has derived membership, then the user cannot be removed
      raise UnableToRemoveEmuError.new("Unable to remove enterprise managed user #{user.display_login} from the organization who belongs to an external group")
    end

    conceal_member user

    job_class = adminable_by?(user) ? RemoveOrgAdminJob : RemoveOrgMemberJob
    job_class.perform_later \
      id,
      user.id,
      remove_direct_repo_access: remove_direct_repo_access,
      send_notification: send_notification,
      save_settings: save_settings,
      reason: reason,
      background_team_remove_member: background_team_remove_member,
      allow_last_admin_removal: allow_last_admin_removal
  end

  # Public: Remove a member from this organization.
  #
  # user - User whose membership is being revoked.
  # remove_direct_repo_access - Boolean indicating whether or not the user should
  #   also be removed from all the repos they have direct access to.
  # send_notification - Boolean indicating whether or not the user should be sent
  #   a notification about being removed from the org.
  # reason - String representing the reason for removal.
  # background_team_remove_member - Boolean indicating whether calls to
  #   Team#remove_member should be queued for deletion in the background.
  # allow_last_admin_removal - Boolean indicating whether to allow removing the last
  #   admin. Only applicable to organizations that are owned by a Business and whose
  #   membership is managed by an external Identity Provider.
  #
  # Returns nothing.
  def remove_member!(
    user,
    remove_direct_repo_access: true,
    send_notification: true,
    save_settings: true,
    reason: nil,
    background_team_remove_member: false,
    allow_last_admin_removal: false
  )
    return if self.kill_switch_enabled?("org.remove_member", log_fields: { "gh.user.id": user&.id })

    # This is not used in production. This is to ensure that the bulk implementation has the same features as this method.
    if self.feature_enabled?(:org_remove_member_cleanup_in_bulk_test_only)
      return false unless Rails.env.test? && TestEnv.test_all_features? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
      return false if user.nil?

      # This feature is testing if the cleanup job after removing abilities is working correctly. Since this job
      # does not remove abilities directly, we need to remove them here.
      Ability.throttle do
        with_write { remove_member_without_callbacks_and_notifications(user, background: false) }
      end

      RevokeOrgMemberProgrammaticAccessGrantsJob.perform_later(self, user)

      # Internal apps (only visible within the owning enterprise) should not be
      # authorized by non-members of an enterprise-owned organization. Performing
      # this work in the background to prevent timeouts from members that have
      # authorized many internal apps.
      #
      # Only enqueue this job if the org is owned by a business and the user is
      # not a member of any other enterprise-owned organization.
      if removing_last_organization_membership_in_business_for?(user)
        RevokeInternalAppAuthorizationsJob.perform_later(organization_id: self.id, user_ids: [user.id])
      end

      if admins.include?(user)
        with_write { Ability.revoke(user, self, background: false) }
        admins.reload
      end

      # This is called by business.remove_abilities_from_business when done in bulk
      if business && !GitHub.single_business_environment?
        BusinessMembershipCleanupJob.perform_later(business, user_ids: [user.id]) if !T.must(business).enterprise_managed_user_enabled?
      end

      # This is the cleanup job that is being tested
      OrganizationBulkRemoveMembersCleanupJob.perform_now(
        organization_ids: self.id ? [self.id] : [],
        user_ids: [user&.id],
        remove_direct_repo_access: remove_direct_repo_access,
        reason: reason,
        actor: actor,
        remove_team_membership: true,
      )

      # This is called by business.remove_abilities_from_business when done in bulk
      if business.present?
        business&.update_license_usage unless background_team_remove_member
        Licensing::SnapshotLicensesJob.perform_later(business)
      end

      return
    end

    return unless direct_or_team_member?(user) || pending_members.include?(user)

    unless allow_last_admin_removal && can_be_orphaned?
      prevent_removal_of_last_admin!(user, "You can't remove the last admin")
    end

    if prevent_removal_of_scim_managed_user?(user: user, reason: :enterprise_team, db_connection: :writing)
      # if the user has ET membership, then the user cannot be removed
      raise UnableToRemoveEnterpriseTeamMemberError.new("Unable to remove enterprise team member #{user.display_login} from the organization")
    end

    # when the removal is executed from external_group_team this check is performed there
    # and we can safely skip it here
    if prevent_removal_of_scim_managed_user?(user: user, reason: :derived, db_connection: :writing)
      # if the user has derived membership, then the user cannot be removed
      raise UnableToRemoveEmuError.new("Unable to remove enterprise managed user #{user.display_login} from the organization who belongs to an external group")
    end

    if use_organization_orchestrator?
      return OrganizationOrchestration.remove_users(
        actor: actor,
        organizations: [self],
        teams: [],
        users: [user],
        business_id: business&.id,
        save_settings: save_settings,
        reason: reason,
        remove_direct_repo_access: remove_direct_repo_access,
        background_team_remove_member: background_team_remove_member,
        send_notification: send_notification,
      ).execute(synchronous: true)
    end

    if EnterpriseTeam.enabled_for_organizations?(business: business)
      remove_organization_membership_entry_with_adder_type(user: user, derived: false, adder_type: :admin)
    else
      remove_organization_membership_entry(user: user, derived: false)
    end

    conceal_member user
    MemberFeatureRequest.remove_all_member_requests(user, self)

    # Force cancel all invitations involving this user, including:
    # - Pending organization invitations involving this user
    # - Pending org-owned repository invitations involving this user
    cancel_all_invitations_involving(user, force: true)

    if save_settings
      save_organization_settings_for_user(user)
    end

    membership_types = role_of(user).types

    CancelTeamMembershipRequestsJob.perform_later(id, user.id)

    if user.has_trade_screening_record_linked_to_org?(organization: self)
      user.unlink_trade_screening_record_from_org(organization: self)
    end

    with_write { billing.remove_manager(user, actor: nil, reason: reason) } if billing_manager?(user)
    with_write { moderation.remove_moderator(user, actor: nil, force: true) }
    remove_direct_repo_access(user) if remove_direct_repo_access
    remove_direct_project_access(user)
    becomes_outside_collaborator = !remove_direct_repo_access && user_collaborates_on_any_repositories?(user.id)
    remove_direct_project_next_access(user) unless becomes_outside_collaborator
    if business.present? &&
      !T.must(business).enterprise_managed_user_enabled? &&
      !T.must(business).supports_unaffiliated_user_accounts?
      remove_user_from_business(user)
    elsif business.present?
      Licensing::SnapshotLicensesJob.perform_later(business)
    end

    # Revoking programmatic access grants for members with too many PAT V2s
    # on this org could could lead to request timeouts.
    RevokeOrgMemberProgrammaticAccessGrantsJob.perform_later(self, user)

    # Internal apps (only visible within the owning enterprise) should not be
    # authorized by non-members of an enterprise-owned organization. Performing
    # this work in the background to prevent timeouts from members that have
    # authorized many internal apps.
    #
    # Only enqueue this job if the org is owned by a business and the user is
    # not a member of any other enterprise-owned organization.
    if removing_last_organization_membership_in_business_for?(user)
      RevokeInternalAppAuthorizationsJob.perform_later(organization_id: self.id, user_ids: [user.id])
    end

    # Revoking abilities on organizations with many teams/repos can cause
    # request timeouts. Perform the work in the background:
    RevokeOrgMembershipAbilitiesJob.perform_later(self, user, background_team_remove_member)

    DenyForkCollabStateForUserPullRequestsJob.perform_later(user_id: user.id, resource_id: self.id, resource_class: self.class.name)

    with_write { remove_user_email_setting_for_org(user) }

    if saml_sso_enabled?
      ExternalIdentity.unlink_saml_identities(provider: saml_provider, user_ids: [user.id])
    end

    # Remove user from this org's Sponsors listing featured users
    if sponsors_listing.present?
      sponsors_listing_featured_item = T.must(sponsors_listing).featured_users.find_by(featureable_id: user.id)
      with_write { sponsors_listing_featured_item&.destroy }
    end

    if send_notification && !user.suspended?
      OrganizationMailer.removed_from_org(user, self, reason&.to_s).deliver_later
    end

    instrument_options = {
      user: user,
      reason: reason,
      membership_types: membership_types.map(&:to_s),
      actor: actor,
    }

    if GitHub.context[:hide_staff_user] && GitHub.guard_audit_log_staff_actor?
      instrument_options.merge!(GitHub.guarded_audit_log_staff_actor_entry(actor))
      # GlobalInstrumenter requires a real user
      instrument_options[:actor] = User.staff_user
    end

    instrument :remove_member, instrument_options
    options = instrument_options.merge(org: self, action: :remove)
    GlobalInstrumenter.instrument "org.remove_member", options
    with_write { Contribution.clear_caches_for_user(user, context: "remove_org_member") }
    business&.update_license_usage unless background_team_remove_member
    user.destroy_org_restricted_user_status(self)

    if admins.include?(user)
      # This is important! If the user is an admin, then we need to synchronously
      # make them not an admin, otherwise prevent_removal_of_last_admin! does not work correctly.
      # see https://github.com/github/teams_and_orgs/issues/64
      with_write { Ability.revoke(user, self, background: false) }

      admins.reload
    end

    # Update user in mailchimp
    MailchimpTeamListJob.perform_later(user: user, org: self) if GitHub.mailchimp_enabled?

    nil
  end

  # Public: Would removing the given user from this organization also mean their losing
  # access to the parent enterprise via membership in any of its other owned
  # organizations?
  #
  # user  - User: A member of this organization who's memberships to
  #         organizations inside the parent enterprise we should check.
  #
  # Returns a boolean.
  def removing_last_organization_membership_in_business_for?(user)
    return false unless self.business.present?
    return true if only_org_in_business? # This is the only org in the enterprise so, by definition, it's the "last".

    # This user is not a member of any other orgs in the owning enterprise.
    T.must(self.business).organization_member_ids(
      org_ids: all_business_org_ids_excluding_this_org,
      actor_ids: [user.id]
    ).none?
  end

  private def only_org_in_business?
    all_business_org_ids_excluding_this_org.none?
  end

  private def all_business_org_ids_excluding_this_org
    return [] if self.business.nil?
    T.must(self.business).organization_ids - [self.id]
  end

  # Public: Does the user have team membership that prevents the user from being removed from the organization?
  #
  # user - the user who is being removed from the organization
  # reason - the reason which prevents the user from being removed, only :derived, :any, and :explicit for now
  #
  # Valid reason:
  # - :derived => if you want to check can the removal of user from organization prevented due to existing derived organization membership
  # - :any => if you want to check can the removal of user from organization prevented due to existing any organization membership
  # - :enterprise_team => if you want to check if removal of user from organization is prevented due to existing enterprise team membership
  #
  # Returns boolean
  def prevent_removal_of_scim_managed_user?(user:, reason:, db_connection: :reading)
    ability = Ability.user_direct_read_on_organization(actor_id: user.id, subject_id: id).pluck(:id)
    return false unless ability.any?

    if reason == :enterprise_team && EnterpriseTeam.enabled_for_organizations?(business: business)
      return OrganizationMembershipEntry.enterprise_team_managed?(user: user, organization_id: id, ability_id: ability.first, db_connection: db_connection)
    end

    if reason == :derived
      return OrganizationMembershipEntry.derived?(user: user, organization_id: id, ability_id: ability.first, db_connection: db_connection)
    elsif reason == :any
      return OrganizationMembershipEntry.any?(user: user, organization_id: id, ability_id: ability.first, db_connection: db_connection)
    end

    # return false by default if the team_membership is invalid
    false
  end

  # Public: Removes organization membership entry for the given user if the user is a member of the organization
  #
  # user - the user who is being removed from the organization
  # adder_id - the entity that created organization membership, it would team_id for derived membership and user_id for explicit membership
  # derived - true, if you want to remove derived organization membership and false if you want to remove explicit membership
  #
  # Returns nothing
  # TODO we should remove this when we adopt the feature flag from `EnterpriseTeam.enabled_for_organizations?``
  def remove_organization_membership_entry(user:, derived:, adder_id: nil)
    return unless scim_managed_enterprise?

    ability = Ability.user_direct_read_on_organization(actor_id: user.id, subject_id: id).pluck(:id)
    return unless ability.any?

    OrganizationMembershipEntry.remove_entry(user: user, organization_id: id, ability_id: ability.first, derived: derived, adder_id: adder_id)
  end

  # Public: Removes organization membership entry for the given user if the user is a member of the organization
  #
  # user - the user who is being removed from the organization
  # adder_id - the entity that created organization membership, it would team_id for derived membership and user_id for explicit membership
  # derived - true, if you want to remove derived organization membership and false if you want to remove explicit membership
  # adder_type - the type of the entity that created organization membership, it would be :external_team for derived membership,
  #              :enterprise_team for an ET, and :admin for explicit membership
  #
  # Returns nothing
  def remove_organization_membership_entry_with_adder_type(user:, derived:, adder_type:, adder_id: nil)
    # We allow removal of ET whether scim_managed or not
    return unless scim_managed_enterprise? || adder_type == :enterprise_team

    ability = Ability.user_direct_read_on_organization(actor_id: user.id, subject_id: id).pluck(:id)
    return unless ability.any?

    OrganizationMembershipEntry.remove_entry(user: user, organization_id: id, ability_id: ability.first, derived: derived, adder_id: adder_id, adder_type: adder_type)
  end

  # Public: Remove a user from an organization, irrespective of how the user is
  #         affiliated with the organization
  #
  # user - the User whose links to the Organization are being severed
  # actor - the User triggering the removal.
  #
  # Returns nothing.
  def remove_any_affiliation(user, actor:)
    return unless user.affiliated_with_organization?(self)

    reason = if GitHub.context[:from] == "two_factor_recovery_request#confirm_continue"
      Organization::RemovedMemberNotification::TWO_FACTOR_ACCOUNT_RECOVERY
    end

    save_organization_settings_for_user(user)
    remove_member(user, save_settings: false, reason: reason)
    billing.remove_manager(user, actor: actor)
    moderation.remove_moderator(user, actor: actor, force: true)
    remove_outside_collaborator(user, save_settings: false)
  end

  def save_organization_settings_for_user(user)
    restorable = with_write { Restorable::OrganizationUser.start(self, user) }

    # Start with memberships before they are removed.
    memberships = user_direct_abilities_for_organization_teams_and_repositories(user)

    with_write do
      restorable.save_memberships(memberships)
      restorable.save_memberships_complete
    end
  end

  # Public: remove a member directly, skipping callbacks and other checks.
  #
  # user       - The user to remove from this organization
  # background - Optional. Delete dependent abilities in a background job unless false.
  def remove_member_without_callbacks_and_notifications(user, background: true)
    revoke(user, background: background)
  end

  def remove_member_with_instrumentation(user, background: true, actor: nil, reason: nil)
    remove_member_without_callbacks_and_notifications(user, background: background)

    membership_types = role_of(user).types
    instrument_options = {
      user: user,
      reason: reason,
      membership_types: membership_types.map(&:to_s),
      actor: actor,
      spammy: user.spammy?,
    }
    instrument :remove_member, instrument_options
  end

  def remove_user_email_setting_for_org(user)
    restorable = Restorable::OrganizationUser.continue(self, user)
    GitHub.newsies.get_and_update_settings(user) do |settings|
      default_email = settings.default_email.address
      email = settings.email(self).address
      if email != default_email
        restorable.save_custom_email_routings(email)
      end
      settings.email(self, nil)
    end
    restorable.save_custom_email_routings_complete
  end

  # Public: Remove a user's direct access to all of this organization's
  # repositories.
  #
  # user - User to remove direct access from.
  # repositories (optional) - a list of repositories from which to remove USER's
  #                           access
  # Returns nothing.
  def remove_direct_repo_access(user, repositories = nil)
    if organization_collaborator_cache_write?
      if repositories.nil? || repositories.pluck(:id).to_set == collaborating_repositories_for_user(user, limit: nil).pluck(:id).to_set
        with_write { OrganizationCollaborator.where(organization_id: id, user_id: user.id).destroy_all }
      end
    end
    # we must find all the repos that a user might have access to, so we cannot have a limit
    # this will likely timeout for orgs with lots of repos.
    repositories ||= collaborating_repositories_for_user(user, limit: nil)

    repositories.each do |repo|
      repo.disassociate_member(user, repo.owner)
    end
  end

  # Public: Remove a user's direct access to all of this organization's
  # projects.
  #
  # user - User to remove direct access from.
  #
  # Returns nothing.
  def remove_direct_project_access(user)
    project_ids = Ability.distinct.where(
      actor_type: "User",
      actor_id: user.id,
      subject_type: "Project",
      subject_id: projects.pluck(:id),
      priority: Ability.priorities[:direct],
    ).pluck(:subject_id)

    Project.where(id: project_ids).each do |project|
      with_write { project.update_user_permission(user, nil) }
    end
  end

  # Public: Schedules a Job that will remove user's direct access to all of this organization's
  # memex projects.
  #
  # user - User to remove direct access from.
  # background - Optional. Delete dependent abilities in a background job unless false.
  #
  # Returns nothing.
  def remove_direct_project_next_access(user, background: true)
    if background
      RemoveOrgMemberProjectsNextAccessJob.perform_later(self, user)
    else
      RemoveOrgMemberProjectsNextAccessJob.perform_now(self, user)
    end
  end

  # Public: All of this organization's repositories to which User USER has
  #         direct access.
  #
  # limit - limit the number of repos queried
  #
  # Returns an Array of Repositories.
  def collaborating_repositories_for_user(user, limit: MEGA_ORG_REPOS_THRESHOLD)
    id_and_repos = collaborating_repositories_for(user.id, limit: limit) || []
    id_and_repos.flat_map(&:last)
  end

  # Public: Scope of Users associated with this org, limited by user's ability
  # to see their association with the org.
  #
  # viewer - The User viewing the org.
  # type   - What types of users do we want to see?
  #          :all                  - Show all visible org users. Does not
  #                                  include direct org members if direct org
  #                                  membership isn't enabled.
  #          :admin                - Only show users who are admins of the org.
  #          :direct_member        - Only show users who are direct members of
  #                                  the org.
  #          :member_without_admin - Only show users who are direct members of
  #                                  the org but NOT admins.
  # actor_ids - A list of user ids to filter the possible visible users on.
  #
  # Returns an ActiveRecord::Relation
  def visible_users_for(viewer, type: :all, actor_ids: nil, limit: MEGA_ORG_MEMBER_THRESHOLD)
    scope = case type
    when :all, :direct_member
      members(actor_ids: actor_ids, limit: limit)
    when :admin
      admins(actor_ids: actor_ids, limit: limit)
    when :member_without_admin
      members(action: :read, actor_ids: actor_ids, limit: limit)
    else
      raise ArgumentError, "Organization#visible_users_for type must be valid"
    end

    if limit_to_public_members?(viewer)
      # Anonymous users, non-org-members, and users using oauth apps blocked by
      # the org can only see public members of the org.
      scope = scope.publicly_belongs_to(id)
    end

    scope
  end

  def visible_user_ids_for(viewer, type: :all, actor_ids: nil, limit: MEGA_ORG_MEMBER_THRESHOLD)
    user_ids = case type
    when :all, :direct_member
      member_ids(actor_ids: actor_ids, limit: limit)
    when :admin
      admin_ids(actor_ids: actor_ids, limit: limit)
    when :member_without_admin
      member_ids(action: :read, actor_ids: actor_ids, limit: limit)
    when :guest_collaborator
      if self.enterprise_managed_user_enabled?
        guest_collaborators.pluck(:id)
      else
        []
      end
    else
      raise ArgumentError, "Organization#visible_user_ids_for type must be valid"
    end

    return user_ids if user_ids.empty?

    if limit_to_public_members?(viewer)
      # Anonymous users, non-org-members, and users using oauth apps blocked by
      # the org can only see public members of the org.

      user_ids = GitHub::BatchedScope.batched(values: user_ids) do |values|
        Organization.connection.select_values(Arel.sql(<<-SQL, user_id: values, org_id: self.id))
          SELECT user_id FROM public_org_members
           WHERE organization_id = :org_id
             AND user_id IN (:user_id)
        SQL
      end
    end

    user_ids
  end

  # Public: Should a viewer only see public members?
  #
  # Returns a Boolean
  def limit_to_public_members?(viewer)
    return true if viewer.nil? || viewer.new_record? || human_non_member?(viewer) || bot_without_access_to_members?(viewer) || mannequin_without_access_to_members?(viewer)
    return true if viewer.governed_by_oauth_application_policy? && !allows_oauth_application?(viewer.oauth_application)

    # To avoid leaking private information(org member information) for scopeless
    # tokens we want to make sure the viewer has read:org or repo scope.
    # Context: https://github.com/github/github/issues/93190
    # Repo scope context: https://github.com/github/github/pull/93604#issuecomment-410885909
    has_permission = Api::AccessControl.scope?(viewer, "read:org") || Api::AccessControl.scope?(viewer, "repo")
    return true if !has_permission

    # Viewer can see private members
    false
  end

  # Public: Scope of *all* Users associated with this org.
  #
  # Be careful: If you are presenting a list of org users to someone, don't use
  # this method. Use #visible_users_for instead.
  #
  # Returns an ActiveRecord scope.
  def people
    User.where(id: people_ids)
  end

  # Public: List of *all* user ids associated with this org.
  #
  # Returns an Array of user ids.
  def people_ids
    member_ids
  end

  # Public: Get the number of members in this org.
  #
  # Returns an Integer.
  def member_count
    member_ids.size
  end

  # Public: get id's for all members and billing managers of this org
  #
  # Returns an Array of id's, de-duplicated
  def member_and_billing_manager_ids
    Set.new(member_ids + billing_manager_ids).to_a
  end

  # Returns members of the Organization, users who could authenticate via the SAML SSO IdP if configured
  #
  # Returns ActiveRecord::Relation of Users
  def saml_members
    members
  end

  # Public:
  def direct_or_team_member?(user)
    member?(user)
  end

  # Organizations can't forget their password - they have none!
  #
  # Returns nothing.
  def forgot_password(address = nil)
    nil
  end

  # This is a User callback we want to skip.
  def set_initial_primary_email
    true
  end

  # Orgs don't have UserEmails or primary emails.
  def email=(email)
    warn "Called Organization#email= which is a noop" if !Rails.env.test?
  end

  # Orgs have no verified emails.
  def should_verify_email?
    false
  end
  alias_method :no_verified_emails?, :should_verify_email?

  # Orgs have no verified emails.
  def enable_mandatory_email_verification
    # noop
  end

  # Public: Orgs don't have UserEmails, so the outbound_email defaults to their profile_email
  # This overrides behavior on User.
  # NOTE: This is not a required attribute for Organizations!
  #
  # Returns a String or nil
  def outbound_email
    T.unsafe(self).profile_email
  end

  def contactable_admins
    admins.reject { |u| u.spammy? || u.suspended? }
  end

  # Clobbered by serialize_attributes. Need to make sure we call
  # User's `gravatar_id` because it has special behavior.
  def gravatar_id
    super
  end

  # Ensures gravatar email at least has an '@' sign in it. C'mon.
  #
  # Should be run as a validation callback.
  #
  # Returns nothing.
  def gravatar_email_must_be_an_email
    if gravatar_email.present? && !gravatar_email.to_s.match(EMAIL_REGEX)
      errors.add("gravatar_email", "isn't a valid email address.")
    end
  end

  # The org's repositories used when searching using `search_repos`,
  # typically in conjunction with an autocompleter.
  #
  # Returns an Array of Repository objects
  def searchable_repos
    org_repositories
  end

  def internal_repositories
    return Repository.none unless business
    repositories.joins(:internal_repository).where("internal_repositories.business_id = ?", T.must(business).id)
  end

  def supports_internal_repositories?
    !!business&.supports_internal_repositories?
  end

  # Find repos that belong to the organization by either a match on the repo
  # name, or on owner name + repo name.
  #
  # Params:
  #
  #      term - The string to search for
  #     limit - Optional - Max # of results
  #
  # Returns an Array of Repository objects.
  def search_repos(term, limit = 30)
    limit = limit.to_i

    query = /^#{Regexp.quote(term.to_s)}/i
    searchable_repos.
      select { |repo| ("#{repo.owner.name}/#{repo.name}" =~ query) || (repo.name =~ query) }.
      uniq.
      sort_by { |repo| repo.name.downcase }.
      first(limit)
  end

  # Public: is the organization permitted to own a fork of the given repo?
  #
  # Returns true if the fork is allowed by policy
  def fork_allowed?(repo:, user:)
    return true if repo.public?
    return fork_allowed_by_policy?(repo) if subject_to_enterprise_fork_policies?(repo)
    return true if allowed_internal_fork_to_org_in_same_business?(repo)
    return true if same_org_as_repo?(repo)
    !repo.internal?
  end

  private def fork_allowed_by_policy?(repo)
    return true unless repo.in_organization?

    if same_org_as_repo?(repo) && repo.allow_private_repository_forking_to_same_organization?
      true
    elsif same_business_as_org?(repo.organization) && repo.allow_private_repository_forking_to_enterprise_organizations?
      true
    else
      repo.allow_private_repository_forking_to_any_location? && !repo.internal?
    end
  end

  def allowed_internal_fork_to_org_in_same_business?(repo)
    repo.internal? && same_business_as_org?(repo.owner)
  end

  def same_org_as_repo?(repo)
    self == repo.owner
  end

  def same_business_as_org?(org)
    return false unless org.organization?
    return false if org.business.nil?
    business == org.business
  end

  # Public: Mark the org as deleted but don't destroy it yet.
  #
  # actor - Optional User who performed the deletion. Defaults to nil.
  # site_admin_deletion - Boolean indicating whether the deletion was
  #   performed by a site admin. Defaults to false.
  #
  # Returns nothing.
  def soft_delete!(actor = nil, site_admin_deletion: false)
    return unless can_soft_delete?(actor)
    return unless permit_deletion?(actor)

    SoftDeletedOrganization.create!(organization: self)
    # We also update the data in User#raw_data to mimic a real deletion so we get all the current benefits of hidden access etc
    self.deleted_at = Time.now
    self.deleted_by = actor.display_login if actor
    self.deleted = true

    save!

    actor = actor.present? ? actor : User.ghost
    payload = { actor: actor, email: billing_email }
    add_admins_to_instrumentation
    instrument :delete, payload

    payload.merge!(organization: self, customer_id: Licensing::Customer.id_for(self))
    GlobalInstrumenter.instrument "organization.soft_delete", payload

    unless delegate_billing_to_business?
      # Reset billing attempts, cancel pending plan changes, and disable auto pay before suspending billing.
      # This will be DRYed up in future so all plans, sponsors, EAs etc do this with a single call - https://github.com/github/meao/issues/2777
      reset_billing_attempts if billing_attempts.to_i > 0
      incomplete_pending_plan_changes.each(&:cancel) if incomplete_pending_plan_changes.any?
      disable_auto_pay!(:customer_initiated) unless auto_pay_reasons&.include?(:india_rbi)

      # Suspend billing for standalone org avoid any charges before it's purged.
      suspend_billing
    end

    unless site_admin_deletion
      options = AccountMailer::Serializers.delete_org(self, admins)
      AccountMailer.delete_org(options).deliver_later
      options = AccountMailer::Serializers.delete_private(self)
      AccountMailer.delete_private(options).deliver_later
    end

    SoftDeleteOrganizationRepositoriesJob.perform_later(T.must(self.id))
    SoftDeleteOrganizationProjectsJob.perform_later(T.must(self.id))
  end

  def can_soft_delete?(actor)
    !GitHub.single_business_environment?
  end

  def soft_deleted?
    soft_deleted_organization.present?
  end

  sig { override.returns(T::Boolean) }
  def active?
    !deleted? && !soft_deleted?
  end

  # Public: Mark a "deleted" organization as "not deleted".
  #
  # To be used when deletion fails and an org is left in a "deleted" state
  # and should be marked as "not deleted" to allow deletion to occur again,
  # or to restore a soft-deleted org.
  #
  # Returns Boolean.
  def mark_not_deleted(actor: nil)
    return unless deleted? || soft_deleted?

    if soft_deleted?
      # Other soft-deleted resources are restored by `after_destroy_commit` hooks in the SoftDeletedOrganization model
      soft_deleted_organization&.destroy

      # Resume billing for standalone org.
      unless delegate_billing_to_business?
        resume_billing
        enable_auto_pay!(:customer_initiated) if auto_pay_reasons&.include?(:customer_initiated)
      end

      GlobalInstrumenter.instrument "organization.restore", {
        actor: actor,
        organization: self,
        customer_id: Licensing::Customer.id_for(self),
      }
    end

    super(actor: actor)
  end

  def soft_deleted_at
    soft_deleted_organization&.created_at
  end

  def belongs_to_a_soft_deleted_business?
    return false unless business_id = business_membership&.business_id

    Business.deleted.where(id: business_id).any?
  end

  # Deleting orgs in the background is a good idea because of all the
  # associated objects - such as repos - which could cause the process
  # to be slow. As such, we wanted to set the `deleted` flag before
  # queueing up a job to hide the org from parts of the web UI so it
  # feels like it was actually deleted.
  #
  # actor - User attempting the deletion.
  # site_admin_deletion - Boolean indicating whether the deletion was
  #   performed by a site admin. Defaults to false.
  #
  # Returns nothing.
  def async_destroy(actor = nil, site_admin_deletion: false)
    return unless permit_deletion?(actor)
    add_admins_to_instrumentation

    super(actor, site_admin_deletion: site_admin_deletion)

    GitHub.dogstats.increment("organization", tags: ["action:destroy"])
  end

  # Public: Instrument "org.destroy" event for org hard deletion of a soft deleted org. This is
  # needed because the "org.delete" event is instrumented when an org is soft deleted.
  #
  # Returns nothing.
  def instrument_deletion
    if soft_deleted?
      add_admins_to_instrumentation

      instrument :destroy, {
        email: @email_for_instrument_deletion,
        plan: GitHub.enterprise? ? "enterprise" : "free",
      }
    else
      super
    end
  end

  # Is deletion of this organization permitted?
  #
  # actor - User attempting the deletion.
  #
  # Returns Boolean.
  def permit_deletion?(actor = nil)
    cannot_delete_reason(actor).blank?
  end

  # Public: Get the reason that deletion is not permitted.
  #
  # actor - User attempting the deletion.
  #
  # Returns Symbol or nil.
  def cannot_delete_reason(actor = nil)
    return :trusted_oauth_apps_owner if trusted_oauth_apps_owner?
    return :sponsorable if sponsorable?
    listing = sponsors_listing
    return :sponsors_listing_not_deletable if listing.present? && !listing.deletable?
    return :legal_hold if self.legal_hold?
    return :trade_restrictions if self.trade_screening_record.delete_restricted?
    return nil if actor&.site_admin?
    return :repo_deletion_not_allowed unless repo_deletion_allowed?
    super
  end

  def repo_deletion_allowed?(actor = nil)
    return true if actor&.site_admin?
    return true if repositories.count == 0
    return true if !GitHub.single_business_environment? || GitHub.global_business.members_can_delete_repositories?
    false
  end

  def add_admins_to_instrumentation
    context = { admin_ids: admin_ids }
    GitHub.context.push(context.merge(admins: admins.map(&:login)))
    Audit.context.push(context.merge(admins: admins.map(&:display_login)))
  end

  # Orgs don't want emails.
  #
  # Returns a Boolean.
  def notifications?
    false
  end

  def self.user_role_target_type
    "Organization"
  end

  def user_role_target_type
    self.class.user_role_target_type
  end

  # Public: Finds all Teams in this Organization a given User belongs to.
  #
  # user   - The User in question.
  # viewer - (Optional) The User viewing the teams. If left nil, we assume all
  #          teams are visible to the viewer.
  #
  # Returns a Team scope.
  def teams_for(user, viewer: nil)
    scope = user.teams.owned_by(self)
    scope = scope.where(id: visible_teams_for(viewer)) if viewer.present?

    scope
  end

  # Public: Cancel any pending requests from a user to join any teams
  # in this organization
  #
  # user - User to cancel pending join requests for
  #
  # Returns nothing.
  def cancel_team_membership_requests_for(user_ids)
    requests = pending_team_membership_requests.where(requester_id: user_ids)

    ActiveRecord::Base.connected_to(role: :writing) do
      requests.each { |r| r.cancel(actor: actor) }
    end
  end

  # Public: Retrieve a Team matching slug.
  #
  # slug       - The team's slug String
  # visible_to - Require the team to be visible to this User
  #
  # Returns a Team or nil.
  def find_team_by_slug(slug, visible_to: nil)
    return unless team = teams.find_by(slug: slug)
    team if visible_to.nil? || team.visible_to?(visible_to)
  end

  # Public: retrieve the teams for the user based on the provided query
  #
  # query              - a TeamSearchQuery
  # user               - the User in question
  # immediate_only     - return only root teams
  # order_by_name_asc  - return results ordered by team name
  #
  # Returns a Team scope
  def team_search_for_user(query, user, immediate_only: false, order_by_name_asc: false)
    scope = if query.members_filter.present?
      if query.members_filter == "me"
        teams_for(user)
      elsif query.members_filter == "empty"
        Team.without_members(visible_teams_for(user).pluck(:id))
      end
    else
      visible_teams_for(user)
    end

    if query.users_filter.present?
      query.users_filter.each_with_index do |name, i|
        break if i > TeamSearchQuery::USER_FILTER_MAX
        if searched_user = User.find_by_login(name)
          searched_user_teams = teams_for(searched_user)
          teams_scoped_to_searched_user = scope.pluck(:id) & searched_user_teams.pluck(:id)
          scope = Team.where(id: teams_scoped_to_searched_user)
        end
      end
    end

    case query.visibility_filter
    when "secret"
      scope = scope.secret
    when "visible"
      scope = scope.closed
    end

    if immediate_only
      root_team_ids = root_teams.pluck(:id)
      scope = scope.where(id: root_team_ids)
    end

    if order_by_name_asc
      scope = scope.order("name ASC")
    end

    if query.cleaned_query.present?
      scope = scope.where(["name LIKE ? OR slug LIKE ?", "%#{query.cleaned_query.strip}%", "%#{query.cleaned_query.strip}%"])
    end

    scope
  end

  # Public: Finds all this organization's teams that are visible to a user and
  # eligible to be a parent team
  def parent_teams_search_for(query, user, child_team_slug: nil)
    async_team_sync_tenant.then do |team_sync_tenant|
      async_business.then do |business|
        async_teams.then do
          scope = visible_teams_for(user).closed.reorder("teams.name ASC")

          if team_sync_tenant&.enabled?
            team_ids = team_sync_tenant.team_group_mappings.distinct.pluck(:team_id)
            scope = scope.where.not(id: team_ids)
          end

          if EnterpriseTeam.enabled_for_organizations?(business: business)
            enterprise_team_managed_team_ids = enterprise_team_organization_mappings.pluck(:team_id)
            scope = scope.where.not(id: enterprise_team_managed_team_ids)
          end

          if slug = child_team_slug.presence
            if team = visible_teams_for(user).where(slug: slug).includes(:organization).first
              scope = scope.where("teams.id NOT IN (?)", [team.id] + team.descendant_ids)
            end
          end

          query = ActiveRecord::Base.sanitize_sql_like(query.to_s.strip.downcase)

          if query.present?
            scope = scope.where(["name LIKE ? OR slug LIKE ?", "%#{query}%", "%#{query}%"])
          end

          if scim_managed_enterprise?
            scope = scope.not_externally_managed
          end

          scope
        end
      end
    end.sync
  end

  # Public: Finds all this organization's discussions that are visible to a user.
  def visible_discussions_for(user, scope: nil)
    repo_ids = visible_repositories_for(user).owned_by(self).pluck(:id)
    discussions = Discussion.for_repository(repo_ids).filter_spam_for(user).includes(:repository)
    discussions = discussions.merge(scope) if scope
    discussions.select do |discussion|
      discussion.repository.discussions_active?
    end
  end

  # Public: Finds all this organization's teams that are visible to a user.
  #
  # * Org owners can see all of the org's teams, regardless of privacy level.
  # * A Bot whose installation has `read` permission on the org's `members`, can see all
  #   of the org's teams, regardless of privacy level.
  # * Org members can see all of the org's closed teams, as well as all of the
  #   org's secret teams that they're on.
  # * Outside collaborators and other users cannot see any of the org's teams.
  #
  # NOTE: This logic is duplicated in Team#visible_to?(user) to avoid loading
  # all team IDs to check a single team's visibility. Please change both spots.
  #
  # user - The User in question.
  # fields - an optional array of fields to select from the teams table
  #
  # Returns a Team scope.
  def visible_teams_for(user, fields: nil)
    if all_teams_visible_for?(user)
      query = teams.includes(:organization)
      query = query.select(fields) if fields
      query
    elsif member?(user)
      member_team_ids = teams_for(user).pluck(:id)
      query = Team.where(id: member_team_ids, organization_id: id).or(Team.where(organization_id: id).with_minimum_privacy(:closed)).
        where(deleted: false).includes(:organization)
      query = query.select(fields) if fields
      query
    else
      Team.none
    end
  end

  # Internal: are all teams in this Organization visible to this user?
  #
  # * Org owners can see all of the org's teams, regardless of privacy level.
  # * A Bot of installation with permission on members, can see all
  #   of the org's teams
  def all_teams_visible_for?(user)
    adminable_by?(user) || installation_with_access?(user)
  end

  # Determine whether the user is an integration with admin or member permission
  def installation_with_access?(user)
    return false unless user.respond_to?(:installation)
    resources.members.readable_by?(user) || repository_resources.administration.readable_by?(user)
  end

  # Creates a Team.
  #
  # name        - A name for the team
  # creator     - User who is creating this team
  # repos       - Array of Repositories to add as members
  # ldap_dn     - String for LDAP distinguished name
  # maintainers - Array of Users to add as team maintainers
  # group_mappings - Array of external group Hashes to map the Team to.
  # attrs       - Attributes to be set on creation
  #
  # Accepts an optional block for additional attributes
  #
  # Returns a Team, whether created or not.
  def create_team(creator:, repos: nil, ldap_dn: nil, maintainers: [], group_mappings: [], attrs: {})
    attributes = attrs.merge({ ldap_dn: ldap_dn })
    team = Team::Creator.create_team(
      creator,
      self,
      attributes,
      maintainers: maintainers,
      group_mappings: group_mappings,
    )

    return team unless team.errors.empty?

    if repos
      authorize_repos_for_team(repos.compact, creator).each do |repo|
        team.add_repository(repo, team.permission) if repo.organization_id == id
      end
    end

    team
  end

  # Internal: given a list of repos and a user trying to create a team for this
  # org, ensure that the creator can admin each repo. For any that the creator
  # is not admin, silently drop the repo from the list so that we do not expose
  # information about whether a given repo exists or not.
  #
  # Returns an Array<Repository>
  private def authorize_repos_for_team(repos, creator)
    organization_owned_repos = repos.filter do |repo|
      repo.organization_id == id
    end

    if feature_enabled?(:team_creation_with_repo_admin_check)
      repos.filter { |repo| repo.resources.administration.writable_by?(creator) }
    else
      subject_ids = ::Authorization
        .service
        .most_capable_abilities_between_multiple_actors_and_subjects(
          actor_type: User,
          actor_ids: [creator.id],
          subject_type: Repository,
          subjects: organization_owned_repos,
      )
        .filter { |ability| ability.action == "admin" }
        .map(&:subject_id)

      repos.filter { |repo| subject_ids.include?(repo.id) }
    end
  end

  # Private: Cancels and deletes all EA org associated subscription items.
  private def cancel_enterprise_subscription_items!
    return unless business&.self_serve_payment?
    T.must(self.business).cancel_member_organization_subscription_items!(self)
  end

  private def instrument_before_destroy
    instrument "before_destroy", {
      email: @email_for_instrument_deletion,
      plan: GitHub.enterprise? ? "enterprise" : "free",
    }
  end

  # Public: Updates the specified teams in this organization with the given
  # privacy level. Returns an array of ids representing those teams that were
  # updated.
  def bulk_update_privacy(team_ids, privacy)
    updates = []

    return updates unless Team.valid_privacy?(privacy)

    teams.where(id: team_ids).find_each do |team|
      next if team.cant_change_visibility?

      team.privacy = privacy

      if team.save
        updates << team.id
      end
    end

    updates
  end

  # Checks if the given user should use transfer requests when moving a
  # repository to this organization
  #
  # Returns a boolean
  def requires_transfer_requests_from?(user, repository_visibility = nil)
    !can_create_repository?(user, visibility: repository_visibility)
  end

  # Is the default visibility for repositories owned by orgs private?
  #
  # On Enterprise Server, honor the default repository visibility setting
  # for the installation. On GitHub .com enable private as the default for orgs
  # that can add private repositories because they are paid accounts.
  #
  # Returns a Boolean.
  def private_repo_by_default?
    return super if GitHub.enterprise?
    can_add_private_repo?
  end

  def default_repo_visibility
    return GitHub.default_repo_visibility if GitHub.enterprise?
    return "internal" if members_can_create_internal_repositories?
    super
  end

  # Can a given user create a repository for this organization?
  #
  # user: The user whose ability to create a  repo is being checked.
  # role: :admin if the user should be treated as an admin
  # visibility: The type of repo to create: "public", "private", or "internal".
  #             A nil value will return true if _any_ repo visibilities are
  #             allowed to be created.
  def can_create_repository?(user, role: nil, visibility: nil)
    async_can_create_repository?(user, role: role, visibility: visibility).sync
  end

  # Public: Returns a promise that resolves to a Boolean and represents whether the given user
  # can create a repository in this organization.
  #
  # user: The user who's ability to create a  repo is being checked.
  # role: If the user should be treated as an admin (default: nil).
  #       :admin - To treat the user as an admin.
  #       :octoshift_migrator - To treat the user as a user who's migrating/importing.
  # visibility: The type of repo to create: "public", "private", or "internal".
  #             A nil value will return true if _any_ repo visibilities are
  #             allowed to be created.
  def async_can_create_repository?(user, role: nil, visibility: nil)
    return Promise.resolve(false) unless visibility.nil? || Repository::VISIBILITIES.include?(visibility)
    return Promise.resolve(false) if !GitHub.public_repositories_available? && visibility == Repository::PUBLIC_VISIBILITY
    return Promise.resolve(false) unless user && (user.user? || user.bot?)
    return Promise.resolve(false) if archived?
    return Promise.resolve(false) if user.emu_creating_public_repo?(visibility)
    return Promise.resolve(true) if %i[admin octoshift_migrator].include?(role)

    async_adminable_by?(user).then do |adminable|
      next true if adminable

      # cast public to boolean because it may be the string "false"
      public = public.to_s == "true"

      if user.can_have_granular_permissions?
        installation = user.ability_delegate

        next false if installation.target != self

        installation.permissions["administration"] == :write
      else
        teams = teams_for(user)
        Promise.all(teams.map(&:async_organization)).then do
          # Keep support for allowing members of legacy admin teams to add repos.
          result = if teams.any?(&:admin?)
            true
          elsif role == :direct_member || member?(user)
            case visibility
            when nil
              members_can_create_repositories?
            when "public"
              members_can_create_public_repositories?
            when "private"
              members_can_create_private_repositories?
            when "internal"
              members_can_create_internal_repositories?
            end
          else
            false
          end
          Promise.resolve(result)
        end
      end
    end
  end

  def can_own_repositories?
    true
  end

  def update_team_privacy(privacy)
    raise ArgumentError unless Team.valid_privacy?(privacy)
    raise AlreadyUpdatingTeamPrivacy if updating_team_privacy?

    self.updated_team_privacy_at = Time.now
    save

    UpdateOrganizationTeamPrivacyJob.perform_later(id, privacy)
  end

  def update_team_privacy!(privacy)
    teams.each do |team|
      team.throttle do
        team.privacy = privacy
        team.save
      end
    end

    self.updated_team_privacy_at = nil
    save
  end

  def updating_team_privacy?
    updated_team_privacy_at && updated_team_privacy_at > 10.minutes.ago
  end

  def can_create_team?(user)
    # This check should be for integrators only
    return true if resources.members.writable_by?(user) && user.can_have_granular_permissions?

    # Eventually this should probably be checked in Authzd
    if members_can_create_teams?
      member?(user) || adminable_by?(user)
    else
      adminable_by?(user)
    end
  end

  def can_publicize_memberships?(current_user, members: self.members)
    return false if GitHub.private_org_membership_visibility_enforced?
    return false unless current_user && current_user.user?

    members == [current_user] && member_publicizable?(current_user)
  end

  def can_conceal_memberships?(current_user, members: self.members)
    return false if GitHub.public_org_membership_visibility_enforced?
    return false unless current_user && current_user.user?
    return true if adminable_by?(current_user)

    members == [current_user] && member?(current_user)
  end

  # Returns a boolean for whether or not the given viewer should be able to view
  # the org membership for the given member.
  #
  # This covers scenarios outside of basic access control for which we still
  # want to enforce certain restrictions on visibility.
  def membership_visible_via_api?(viewer:, member:)
    return false if membership_state_of(member) == :inactive
    return true if viewer == member

    if viewer.can_have_granular_permissions?
      # Membership visibility for GitHub apps is governed by fine-grained
      # permissions rather than our normal user-based auth checks.
      resources.members.readable_by?(viewer)
    elsif adminable_by?(viewer)
      # Org admins can see any type of membership.
      true
    else
      # As per https://github.com/github/github/issues/120931, billing managers
      # memberships should not be visible to ordinary org members.
      !current_or_pending_billing_manager?(member)
    end
  end

  # create the trusted oauth org
  def self.create_trusted_oauth_apps_owner
    return unless GitHub.enterprise? # restrict to enterprise for now
    Organization.where(login: GitHub.trusted_oauth_apps_org_name).first_or_create(
      login: GitHub.trusted_oauth_apps_org_name,
      plan: GitHub::Plan.find("free").name,
      billing_email: "ghost-org@github.com",
      admins: [User.ghost],
    )
  end

  # Every organization needs a team of users who can administrate the
  # organization. These are generally called Owners.
  def add_initial_admins
    return unless @admins.present?
    @admins.each { |user| add_admin(user, skip_notifications: being_created?) }
  end

  # Shortcut for setting just a single admin.
  def admin=(admin)
    self.admins = [admin]
  end

  # Shortcut for grabbing the admin, if there's only one.
  # Please don't use this method in app code - it's mainly to appease
  # Machinist.
  def admin
    admins.size == 1 ? admins[0] : raise("More than one admin!")
  end

  # Given an array of admin login strings, sets the admins to be the users
  # identified by those logins.
  #
  # e.g.
  #   org.admin_logins = %w( pjhyett defunkt mojombo )
  def admin_logins=(logins)
    self.admins = User.with_logins(*logins)
  end

  # The admins as user objects. This is used during organization creation by the
  # `add_initial_admins` method.
  def admins=(admins)
    @admins = admins
  end

  def admins(actor_ids: nil, limit: nil)
    # The @admins ivar is for pre-create validation that checks that admins are
    # present, even if they haven't been granted yet by `add_initial_admins`.
    # Don't use this ivar for anything but creating new organizations.
    return @admins if @admins
    direct_admins(actor_ids: actor_ids, limit: limit)
  end

  def admin_ids(actor_ids: nil, limit: nil)
    direct_admin_ids(actor_ids: actor_ids, limit: limit)
  end

  # The team of administrators for this organization. They have all the power.
  def owners_team
    if !defined? @owners_team
      @owners_team = teams.where(name: "Owners").first
    end

    @owners_team
  end

  # The former team of administrators for this organization. They once had all
  # the power, but as of direct org membership, they are a mere relic of their
  # former glory. Always use this instead of `owners_team` or manually checking
  # the team's name/slug.
  #
  # Returns a Team or nil.
  def legacy_owners_team
    teams.where(name: "Owners", permission: "admin").first
  end

  # Can the given user leave an Organization? Only members and non-surviving
  # admins can leave. A "non-surviving admin" is basically the last person
  # standing: an org must have at least one admin. If the last admin wants to
  # leave they can just delete the damn org.
  #
  # Returns a Boolean
  def can_leave?(user)
    leave_status_for(user) == true
  end

  def leave_status_for(user)
    reload

    if last_admin?(user)
      :last
    else
      direct_or_team_member?(user)
    end
  end

  # Maintenance command to verify consistency of the public_members association
  # used to determine whether a user's org membership is concealed or not.
  # Sometimes this member list gets out of sync with the system-of-record team
  # tables. If things *do* get out of sync, it should be considered a bug:
  # notify @github/abilities for further research.
  #
  # NOTE This method is really unoptimized and should not be used for any
  # general action on the site. Staff use only.
  #
  # TODO reexamine this after orgs-next, as there won't be anything to get out
  # of sync.
  def reset_public_members!
    users = public_members.select { |u| !direct_or_team_member?(u) }
    ActiveRecord::Base.connected_to(role: :writing) do
      users.each { |user| conceal_member(user) }
    end
  end

  # Cleanup internal state on AR reload
  def reset_memoized_attributes
    remove_instance_variable :@admins if defined? @admins
    remove_instance_variable :@owners_team if defined? @owners_team

    reset_trade_memoized_attributes
    super
  end

  def reset_trade_memoized_attributes
    remove_instance_variable(:@linked_trade_screening_record) if defined?(@linked_trade_screening_record)
    remove_instance_variable(:@has_linked_trade_screening_record) if defined?(@has_linked_trade_screening_record)
    remove_instance_variable(:@org_is_on_business_tos) if defined?(@org_is_on_business_tos)
    remove_instance_variable(:@org_is_on_standard_tos) if defined?(@org_is_on_standard_tos)
  end

  # Extremely destructive and awesome method: transforms a normal
  # user account into an organization.
  #
  # Teams are created and users placed in them according to the
  # current collaborators. All teams initially are `pull` as that's
  # the implicit permission level of collaborators on normal
  # repositories as of writing.
  #
  # user          - The User object that is being transformed into an Organization.
  # owner         - The User object that will become the owner of the new Organization.
  # new_org_attrs - A hash of attributes to set on the new Organization.
  #
  # Returns nothing.
  # Raises TransformationFailed if there was validation error before the job
  # could be scheduled.
  def self.transform(user, owner, new_org_attrs = {})
    if user.email.nil?
      raise TransformationFailed.new("Transform requires a primary email on the user account.")
    end

    if user.trade_screening_record.delete_restricted?
      raise TransformationFailed.new("Transform requires an unrestricted account.")
    end

    if owner.nil?
      raise TransformationFailed.new("Transform requires an owner.")
    end

    if owner == user
      raise TransformationFailed.new("This user will become an organization and can't be an owner.")
    end

    unless user.is_a?(User) && user.user?
      raise TransformationFailed.new("Transform requires the user be a user.")
    end

    unless owner.is_a?(User) && owner.user?
      raise TransformationFailed.new("Transform requires the owner be a user.")
    end

    if owned_org = user.organizations.detect { |org| org.last_admin?(user) }
      raise TransformationFailed.new("Cannot transform user because user is the last owner of #{owned_org.display_login}")
    end

    if owned_business = user.businesses(membership_type: :admin).detect { |business| business.last_owner?(user) }
      raise TransformationFailed.new("Cannot transform user because user is the last owner of Enterprise account #{owned_business}.")
    end

    if start_transform(user)
      TransformUserIntoOrgJob.perform_later(user.id, owner.id, new_org_attrs)
    end
  end

  # Synchronous version of `Organization.transform`
  def self.transform!(user, owner, new_org_attrs = {})
    if user.organization?
      end_transform(user)
      return
    end

    org = T.let(nil, T.nilable(Organization))
    transaction do
      # Remove user as a collaborator from anything they're a member of
      # Note: This must be done *before* the User becomes an Organization, or the
      # `remove_member` ability revocation won't work.
      user.teams.each { |team| team.remove_member user }
      user.member_repositories.each { |repo| repo.remove_member user }
      RepositoryInvitation.where(invitee_id: user.id).find_each { |invitation| invitation.destroy }
      OrganizationInvitation.where(invitee_id: user.id, accepted_at: nil).find_each { |invitation| invitation.cancel(actor: user) }
      user.organizations.each_slice(100) do |slice|
        slice.each { |organization| organization.remove_member(user) }
      end

      user.clear_issue_assignments
      user.destroy_reactions
      user.trade_screening_record.destroy!
      user.discussions.destroy_all
      user.discussion_comments.destroy_all
      user.two_factor_credential&.destroy
      user.u2f_registrations.destroy_all

      # remove user as admin from all Enterprise accounts
      admin_invitations = BusinessAdministratorInvitation.with_invitee_or_normalized_email(invitee: user, emails: user.emails.map(&:email)).pending
      admin_invitations.each { |invitation| invitation.cancel(actor: user) }
      user.businesses(membership_type: :admin).each { |business| business.remove_owner(user, actor: user) }
      user.businesses(membership_type: :billing_manager).each { |business| business.billing.remove_manager(user, actor: user) }
      user.businesses.each { |business| business.remove_user_from_business(user, force: true) }

      # Revoke all OAuth tokens
      user.oauth_accesses.destroy_all

      # Uninstall all Integration Installations
      user.integration_installations.each { |installation| installation.uninstall(actor: user) }

      # Destroy all dashboard notices
      user.delete_notices

      # It's no longer possible to block this user since it's an org now
      user.ignored_by_users.destroy_all

      # All account succession agreements for that user are now nullified, now that they're an org.
      SuccessorInvitation.terminate_all(user)

      # Disable private profile, since it doesn't exist for orgs
      user.private_profile = false if user.private_profile?

      # The metamorphosis.
      previous_plan = user.plan.to_s
      user.type = "Organization"
      user.save!
      user.update!(new_org_attrs)

      if GitHub.billing_enabled?
        # Ensure we have enough seats to cover all collaborators
        user.seats = user.default_seats
        user.save!
      end

      # Fresh version of our new Organization.
      org = find(user.id)

      # Setting the Organization#creator skips sending OrganizationMailer#admin_added emails
      # till the transformation process is committed to the database
      org.creator = owner

      # Set up the owners team / admins
      org.admins = [owner]
      org.add_initial_admins

      # Ensure all our repos and forks know they're part of an organization.
      org.associate_repositories

      # Ensure all projects are updated to the correct owner type post-transfer.
      # This has to be done with User because owner is a polymorphic association
      # and we can't simply call `org.projects` until after this is complete
      org.associate_user_projects(user, owner)

      org.associate_user_memex_projects(user, owner)

      # Add collaborating team members to outside collaborators
      user.repositories.each do |repository|
        repository.teams.each do |team|
          team.members.each do |member|
            # Guard against trying to add the original User, which has now become an
            # Organization, which we have to test against `id`.
            next if member.id == user.id
            org.repositories.find(repository.id).add_member(member, action: Authorization.service.most_capable_action_between(actor: member, subject: repository))
          end
        end
      end

      # Set up the default third-party application policy used for new orgs.
      org.initialize_application_policy

      # Set up the default attributes.
      org.sync_default_repository_permission!(actor: org)

      # Clean up some of the user's data that is no longer necessary.
      org.clear_transformed_user_data

      org.track_plan_change(org, GitHub::Plan.find!(previous_plan))

      # Disable if over plan limits
      org.enable_or_disable!

      # Rebuild the contributions data for the new org's repositories.
      org.rebuild_contributions

      # So everyone knows we've been transformed.
      end_transform(user)

      org.save
    end

    org = find(user.id)
    org.instrument :transform, owner: owner.to_s, tos_sha: TosAcceptance.current_sha

    # NB: Need to force the BT update since the update catches
    # to see if there are changes on the relevant fields.
    org.update_external_subscription!(force: true)

    # ensure org has initial set of default labels
    org.populate_initial_user_labels

    if GitHub.single_business_environment? && GitHub.global_business
      # Ensure the new org is added to the global enterprise account.
      GitHub.global_business.add_organization org
    end

    # Notify the org owner that they have been added as an admin
    org.admins.each do |admin|
      OrganizationMailer.admin_added(admin, org, nil).deliver_later
    end

    # Setup the default issue types for the new org
    unless GitHub.flipper[:default_issue_types_job_killswitch].enabled?
      SetupIssueTypesForOrganizationJob.perform_later(org: org)
    end

    if org.feature_enabled?(:collaborator_cache_write) || GitHub.flipper[:collaborator_cache_write].enabled?
      OrganizationCollaboratorBackfillJob.perform_later(org: org)
    end

    # Tada.
    org
  ensure
    end_transform(user)
  end

  # Sets organization_id on all repos owned by the organization and
  # private forks owned by members of the org.
  def associate_repositories
    repositories.each do |repo|
      # Preserve the (outside) collaborators.
      repo.update_organization remove_collaborators: false

      # Forks of private repos get associated with the org.
      next unless repo.private?

      repo.reload&.network&.sync_org_owned_private_network_with_forks

      repo.forks.each do |frk|
        frk.update_organization remove_collaborators: false
      end
    end
  end

  # Changes the owner type and sets up the project permissions
  # This will also re-sequence, so the project number may change if they have
  # deleted projects
  def associate_user_projects(user, owner)
    projects = user.projects.sort_by(&:number)
    projects.each do |project|
      project.transform_owner_type!(owner: self, new_creator: owner)
    end
  end

  # Changes the owner type and sets up the project permissions
  # This will also re-sequence, so the project number may change if they have
  # deleted projects
  # user is the objects that has been updated to type org
  def associate_user_memex_projects(user, owner)
    projects = user.memex_projects.sort_by(&:number)
    projects.each do |project|
      project.transform_owner_type!(new_owner: self, new_creator: owner)
    end
  end

  # Returns a list of potential repositories grouped by collaborators. The
  # values are arrays of repositories which should belong to unique teams.
  #
  # That is, if two repositories have the same collaborators they
  # will be one team while another repository with different
  # collaborators will be part of another.
  #
  # Repositories with no collaborators are excluded.
  def repositories_grouped_by_collaborators
    teams = {}

    repos_and_forks = repositories.map do |repo|
      [repo, repo.forks.private]
    end

    repos_and_forks.flatten.each do |repository|
      collabs = repository.all_members.select(&:user?)
      collabs_hash = collabs.map(&:id).sort_by(&:to_s).join("-")

      next if collabs_hash.empty?

      teams[collabs_hash] ||= []
      teams[collabs_hash] << repository
    end

    teams.values
  end

  # Removes user data which is no longer necessary now that the user
  # has been transformed into an organization, such as public keys and
  # passwords.
  def clear_transformed_user_data
    self.password = "n0n3:#{Time.now.to_i}"
    self.gravatar_email = gravatar_email || email
    self.billing_email  = billing_email || email
    self.gh_role = nil
    save!

    sessions.destroy_all
    public_keys.clear

    users_the_org_unfollowed = following.to_a.dup
    users_who_unfollowed_the_org = followers.to_a.dup

    followings.destroy_all
    followeds.destroy_all
    emails.clear
    email_roles.clear

    # Update respected follower/ing counts on users
    users_the_org_unfollowed.each { |u| u.followers_count! }
    users_who_unfollowed_the_org.each { |u| u.following_count! }

    # Unstar all repos and Gists.
    (starred_repositories + starred_gists).each do |starrable|
      unstar(starrable)
    end

    # Orgs don't have review requests
    clear_review_requests

    # Orgs don't have notifications.
    Notifications::Subscriptions.async_delete_user_subscriptions(T.must(id))

    # Orgs can't login, so they can't see the interaction warning
    T.must(interaction_setting).destroy if interaction_setting

    # If they have a profile we want to remove everything except the
    # allow listed profile fields. This way an organization does not
    # remain hireable, for instance.
    #
    # Also sets profile display staff badge to false, since orgs cannot
    # have staff badges
    if profile
      allowlist = %w( name blog location )
      denylist = Profile.column_names - allowlist

      denylist.each do |field|
        method = "profile_#{field}="
        send(method, nil) if respond_to?(method) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
      end

      T.must(profile).display_staff_badge = false
      T.must(profile).readme_opt_in = false

      T.must(profile).save
    end
  end

  # The Redis key used for keeping track of a user => org transform.
  def self.transform_key(user)
    "org:transforming:#{user.id}"
  end

  # Begin transforming the passed user into an organization.
  def self.start_transform(user)
    Organization::KV.store.setnx(transform_key(user), TRANSFORM_FLAG, expires: TRANSFORM_FLAG_EXPIRY.from_now)
  rescue GitHub::KV::UnavailableError
    false # if KV is unavailable, we can't set the flag. Don't continue.
  end

  # Are we still transforming?
  def self.transforming?(user)
    Organization::KV.store.get(transform_key(user)).value { false }
  end

  # Complete transforming the passed user into an organization.
  #
  # Returns nothing.
  def self.end_transform(user)
    Organization::KV.store.del(transform_key(user))
  rescue GitHub::KV::UnavailableError
    # Noop, ignore. Rely on expiration to clean up the flag.
  end

  # Find organizations with logins matching a specific term.
  #
  # Params:
  #
  #   term  - The string to search for.
  #   limit - Maximum number of results. Defaults to 30.
  #
  # Returns an Array of Organizations.
  def self.search(term, limit: 30, deleted: false)
    orgs = user_query("#{term} type:org", friends: [], limit: limit)
    orgs.uniq!
    orgs.compact!
    deleted ? orgs.select!(&:soft_deleted?) : orgs.select!(&:active?)
    orgs
  end

  def must_be_org_plan
    # Ignore this validation if this looks like the trusted org
    return if login == GitHub.trusted_oauth_apps_org_name
    errors.add("plan", "must be an Organization plan.") if plan.blank? || !plan.orgs?
  end

  def events_key(options = nil)
    "org:#{id}:public"
  end

  def event_prefix
    :org
  end

  def event_key
    :org
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

  # Public: Instrument new user creation.
  #
  # Returns nothing.
  def instrument_creation
    payload = {
      email: billing_email,
      plan: plan.try(:name),
      actor: creator,
      tos_sha: TosAcceptance.current_sha,
    }

    instrument :create, payload

    number_of_organizations_adminable_by_actor = creator&.owned_organizations&.count
    first_organization_adminable_by_actor = creator&.owned_organizations&.first

    # If the organization just created is the first adminable by the actor it may not be immediately
    # available from read replicas so we manually set the number to 1 and the first org to self.
    if number_of_organizations_adminable_by_actor == 0
      number_of_organizations_adminable_by_actor = 1
      first_organization_adminable_by_actor = self
    end

    GlobalInstrumenter.instrument "organization.create", {
      organization: self,
      actor: creator,
      number_of_organizations_adminable_by_actor: number_of_organizations_adminable_by_actor,
      first_organization_adminable_by_actor: first_organization_adminable_by_actor,
      actor_email: creator&.primary_user_email,
      actor_profile: creator&.profile,
      visitor_id: GitHub.context[:visitor_id].to_s,
    }
  end

  # Public: The User who is creating the Organization. This is not persisted,
  #         and is set by Organization::Creator#perform during org creation.
  attr_accessor :creator

  # Public: The Business who will be associated with the Organization. This is
  # not persisted, and is set by Organization::Creator#perform during org
  # creation
  attr_accessor :associated_business_on_creation

  def instrument_github_app_manager(member, action:)
    case action
    when :grant
      instrument :integration_manager_added, manager: member
    when :revoke
      instrument :integration_manager_removed, manager: member
    end
  end

  # Public: Instrument an external identity for a user within this Organization's
  # SAML Provider getting revoked
  #
  # payload - Hash of custom payload data.
  #
  # Returns nothing.
  def instrument_external_identity_revoked(payload = {})
    instrument :revoke_external_identity, payload
  end

  # Public: retrieve the ExternalIdentity for this Organization
  #
  # An Organization can only have one ExternalIdentity, so this method
  # is just a shortcut to retrieve the first entry in external_identities
  def external_identity
    external_identities.first
  end

  # Public: Instrument a user's SAML SSO session getting revoked.
  #
  # payload - Hash of custom payload data.
  #
  # Returns nothing.
  def instrument_sso_session_revoked(payload = {})
    instrument :revoke_sso_session, payload
  end

  def audit_log
    @audit_log ||= AuditLog.new(self)
  end

  # Public: Check whether the github trusted auths are attached to this organization.
  #
  # Returns true when the org is the same that we configured.
  def trusted_oauth_apps_owner?
    self.id == GitHub.trusted_apps_owner_id
  end

  # Public: Safely add a public member, even if they're already a public member
  def publicize_member(user)
    return false unless member_publicizable?(user)

    # Allow multiple concurrent inserts, e.g. simultaneous API calls
    sql_bindings = {
      user_id: user.id,
      org_id: id,
    }
    sql = Arel.sql <<-SQL, **sql_bindings
      INSERT INTO public_org_members (user_id, organization_id)
      VALUES (:user_id, :org_id) ON DUPLICATE KEY UPDATE user_id = :user_id
    SQL
    self.class.connection.insert(sql)

    user.synchronize_search_index

    true
  end

  # Public: Safely add public members, even if they're already public members
  def bulk_publicize_members(users, skip_user_synchronize_index: false)
    publicizable_members = users.filter { |user| member_publicizable?(user) }
    return if publicizable_members.empty?

    data_rows = publicizable_members.map do |user|
      [
        user.id, # user_id
        id       # organization_id
      ]
    end

    upsert_query = <<-SQL
      INSERT INTO public_org_members
        (user_id, organization_id)
      :rows
      ON DUPLICATE KEY UPDATE
        user_id = VALUES(user_id)
    SQL
    sql = Arel.sql(upsert_query, rows: Arel::Nodes::ValuesList.new(data_rows))
    self.class.connection.insert(sql)

    # these happen in the background
    unless skip_user_synchronize_index
      publicizable_members.each { |user| user.synchronize_search_index }
    end
  end

  def conceal_member(user)
    conceal_members([user])
  end

  def conceal_members(users, skip_search_index: false)
    return if users.empty?

    pm = public_members
    with_write { pm.delete(users) }
    users.each { |user| user.synchronize_search_index } unless skip_search_index

    true
  end

  # Public: Is user a public member of this organization?
  def public_member?(user)
    user && public_members.exists?(user.id)
  end

  # Overriding some following stuff from User
  # Orgs don't follow
  def following_count(viewer:);  0; end
  def following_count!; 0; end

  def repository_counts_class
    OrgRepositoryCounts
  end

  # Public: Repositories owned by this org and visible to a user.
  #
  # Experiment control: scopes User#associated_repository_ids to all org repo IDs
  #
  # user - User who should be able to see all the returned repositories
  # associated_repository_ids - Optional. Array of repository IDs as Integers
  #                             representing the repositories associated with this user.
  #                             Use this kwarg to memoize the potentially expensive call to
  #                             user.associated_repository_ids
  # org_pinned_repo_ids       - Optional. Array of repository IDs as Integers
  #                             representing the repositories pinned by an Org.
  #                             Use this kwarg to memoize the potentially expensive call to
  #                             Repository.owned_by(self).ids
  # batched                   - Optional. Return a batched repository scope.
  #
  # Returns a Repository scope.
  def visible_repositories_for(user, associated_repository_ids: nil, org_pinned_repo_ids: nil, limit_visible_internal_repos_to_org: false, batched: false)
    return org_repositories.public_scope if user.nil?
    return org_repositories if adminable_by?(user)

    org_repo_ids = org_pinned_repo_ids || Repository.owned_by(self).pluck(Arel.sql("/*vt+ IGNORE_MAX_MEMORY_ROWS=1 */ id"))
    user_associated_repo_ids = associated_repository_ids || user.associated_repository_ids(repository_ids: org_repo_ids)

    tags = ["associated_repository_ids_present:#{associated_repository_ids.present?}"]
    tags << "org_pinned_repo_ids_present:#{org_pinned_repo_ids.present?}"
    GitHub.dogstats.distribution("organization.visible_repositories_for.associated_repo_id_count", user_associated_repo_ids.count, tags: tags)

    user_associated_org_repo_ids = user_associated_repo_ids & org_repo_ids

    internal_repo_ids = if supports_internal_repositories?
      if GitHub.esm_enabled? && GitHub.enterprise?
        InternalRepository.where(business_id: GitHub.global_business.id).pluck(:repository_id)
      else
        InternalRepository.where(business_id: user.business_ids(valid_license: true)).pluck(:repository_id)
      end
    else
      []
    end
    if limit_visible_internal_repos_to_org
      internal_repo_ids_in_org = org_repo_ids & internal_repo_ids
      combined_ids = user_associated_org_repo_ids | internal_repo_ids_in_org
    else
      combined_ids = user_associated_org_repo_ids | internal_repo_ids
    end
    public_org_repos = org_repositories.public_scope
    return public_org_repos if combined_ids.empty?
    combined_ids |= public_org_repos.ids

    if batched
      return org_repositories.batched_scope(:id, values: combined_ids)
    end

    org_repositories.where(id: combined_ids)
  end

  # Public: Repositories owned by this org and visible to a user.
  #
  # Experiment candidate: uses org scoping and private filter in User#associated_repository_ids
  #
  # user - User who should be able to see all the returned repositories
  # associated_repository_ids - Optional. Array of repository IDs as Integers
  #                             representing the repositories associated with this user.
  #                             Use this kwarg to memoize the potentially expensive call to
  #                             user.associated_repository_ids
  # org_pinned_repo_ids       - Optional. Array of repository IDs as Integers
  #                             representing the repositories pinned by an Org.
  #                             Use this kwarg to memoize the potentially expensive call to
  #                             Repository.owned_by(self).ids
  # Returns a Repository scope.
  def visible_repositories_for_candidate(user, associated_repository_ids: nil, org_pinned_repo_ids: nil)
    return org_repositories.public_scope if user.nil?
    return org_repositories if adminable_by?(user)

    # Reduce the user associated repository ids to organization owned repositories.
    ari_org = self
    org_repo_ids = org_pinned_repo_ids

    # If the caller did not specify associated_repository_ids, load only the IDs for
    # private repositories owned by this organization - the org's public repos will
    # be included separately.
    #
    # If the org has fewer than ARI's BATCH_THRESHOLD repositories, scoping to those IDs
    # rather than the org will be faster due to repository_ids_indirect_via_membership's
    # Ability query performance.
    repo_count_threshold = Repositories::AssociatedRepositoriesDependency::AssociatedRepositories::BATCH_THRESHOLD
    if org_pinned_repo_ids.nil? && associated_repository_ids.nil?
      org_repo_ids = Repository.owned_by(self).private_scope.limit(repo_count_threshold + 1).pluck(:id)
      if org_repo_ids.count <= repo_count_threshold
        ari_org = nil
      else
        org_repo_ids = nil
      end
    end

    scope = Repository
    sql_where = "repositories.active = 1 AND repositories.owner_id = ?"
    sql_params = [self.id]

    sql_conditions = ["repositories.public = 1"]

    # If the user has direct or indirect access to any of this org's private repositories, include them.
    user_associated_private_org_repo_ids = associated_repository_ids || user.associated_repository_ids(
      organization: ari_org,
      exclude_public: true,
      repository_ids: org_repo_ids
    )

    tags = ["associated_repository_ids_present:#{associated_repository_ids.present?}"]
    tags << "org_pinned_repo_ids_present:#{org_pinned_repo_ids.present?}"
    GitHub.dogstats.distribution("organization.visible_repositories_for.associated_repo_id_count", user_associated_private_org_repo_ids.count, tags: tags)

    if user_associated_private_org_repo_ids.any?
      sql_conditions << "repositories.id IN (?)"
      sql_params << user_associated_private_org_repo_ids
    end

    # If this org has internal repositories and the user is a member of the org's business,
    # include the org's internal repositories.
    if supports_internal_repositories? && internal_repositories.any? && user.is_business_member?(T.must(business).id)
      scope = scope.joins("LEFT JOIN internal_repositories ON internal_repositories.repository_id = repositories.id AND internal_repositories.business_id = #{T.must(business).id}")
      sql_conditions << "internal_repositories.repository_id IS NOT NULL"
    end

    sql_where += " AND (#{sql_conditions.join(" OR ")})"
    scope.where(sql_where, *sql_params)
  end

  # Public: Repositories owned by this org and associated with a user.
  #
  # For a repository to be "associated" with a user, the user must have some
  # sort of official connection to it, either through a team or by being a
  # direct collaborator.
  #
  # user - User who should be associated with all the returned repositories
  #
  # Returns a Repository scope.
  def repositories_associated_with(user)
    return Repository.none if user.nil?
    return org_repositories if adminable_by?(user)

    # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
    org_repositories.where(id: user.associated_repository_ids(include_oopfs: false))
    # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
  end

  # Public: Private repositories owned by this org and their forks.
  #
  #
  # Returns a Repository scope.
  def private_repositories
    org_repositories.where(public: false)
  end

  # Public: Find an unaccepted invitation to this organization for the specified
  # user.
  #
  # invitee     - User to find an invitation for.
  # email       - The String email address to find an invitation for.
  # role        - the role user is invited as, can be any role from OrganizationInvitation::ROLES.keys
  # include_private_emails - a Boolean indicating if we should return invitations
  #                          associated with an invitee's private email
  #
  # Returns an OrganizationInvitation, or nil if there is none.
  def pending_invitation_for(invitee = nil, email: nil, role: nil, include_private_emails: true)
    return unless User.valid_email?(email) || invitee.is_a?(User)

    start = Time.now
    scope = invitations.pending

    scope = scope.with_business_role(*Array.wrap(role)) if role
    invitation = scope.with_invitee_or_normalized_email(invitee: invitee, emails: email, include_private_emails: include_private_emails).last
    ms = (Time.now - start) * 1000
    GitHub.dogstats.distribution("organization.dist.time", ms, tags: ["action:pending_invitation_for"])
    invitation
  end

  # Public: Finds invitations to join a business sent to this organization
  #         that the specified user can accept (and thus should be warned about).
  #
  # user - User that should be able to accept any returned invitations.
  #
  # Returns an ActiveRecord::Relation for BusinessOrganizationInvitation.
  def business_invitations_acceptable_by(user)
    return BusinessOrganizationInvitation.none unless business.nil?
    return BusinessOrganizationInvitation.none unless self.adminable_by?(user)

    BusinessOrganizationInvitation.with_status(:created).where(invitee: self)
  end

  # Public: Get the membership state of the specified user for this
  # organization. This is intended to be used by the API only.
  #
  # user - User to check the membership state for.
  #
  # Returns :pending, :active, or :inactive.
  def membership_state_of(user)
    if direct_or_team_member?(user)
      :active
    elsif pending_invitation_for(user).present?
      :pending
    else
      :inactive
    end
  end

  # Public: Get all the legacy admin members of the organization. A legacy admin
  # member is a non-owner org member who is on at least one legacy admin team.
  #
  # Note: This is a fairly expensive method, and it's not memoized that so it
  # won't act weird after changing team memberships. If you need to access this
  # multiple times in one request, save it in a variable first.
  #
  # Returns an Array.
  def legacy_admin_members
    Team.members_of(teams.legacy_admin.map(&:id)) - admins
  end

  def migrate_legacy_admin_teams
    MigrateLegacyAdminTeamsJob.perform_later(id)
  end

  def migrate_legacy_admin_teams!
    teams.legacy_admin.each do |legacy_admin_team|
      legacy_admin_team.throttle do
        legacy_admin_team.migrate_legacy_admin
      end
    end
  end

  # Public: Get all of this organization's repositories that the specified users
  # are collaborating on.
  #
  # The result is a Hash with a user id keys and an array of Repository values.
  #
  # {
  #   8  => [<Repo 1>, <Repo 2>],
  #   13 => [<Repo 3>]
  # }
  #
  # Note: this will *only* return directly collaborating repositories. If a user
  # has access to an repository through some other means (such as being an org
  # admin or a team member), it will not be included in this list.
  #
  # users - The id or ids of the users to get collaborating repositories for.
  #
  # limit - a limit to apply when querying for repos
  #
  # Returns a Hash (described above in more detail).
  def collaborating_repositories_for(user_ids, limit: MEGA_ORG_REPOS_THRESHOLD)
    user_and_repo_ids = collaborating_repository_ids_for(user_ids, limit: limit)

    _, org_repo_ids = user_and_repo_ids.transpose

    org_repo_by_id = Repository.where(id: org_repo_ids).index_by(&:id)
    return {} if org_repo_by_id.empty?

    user_and_repo_ids.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(user_id, repo_id), result|
      next unless org_repo_by_id.has_key?(repo_id)

      result[user_id] << org_repo_by_id[repo_id]
    end
  end

  # Internal: Get all of this organization's repository ids that the specified users
  # are collaborating on.
  #
  # The result is an Array with a User id and Repository id values.
  #
  # [
  #   [<User 1>, <Repo 2>],
  #   [<User 1>, <Repo 3>],
  #   [<User 2>, <Repo 3>]
  # ]
  #
  # Note: this will *only* return directly collaborating repositories. If a user
  # has access to an repository through some other means (such as being an org
  # admin or a team member), it will not be included in this list.
  #
  # users - The id or ids of the users to get collaborating ids for.
  #
  # limit - a limit to apply when querying for repos
  #
  # Returns an Array (described above in more detail).
  def collaborating_repository_ids_for(user_ids, limit: MEGA_ORG_REPOS_THRESHOLD)
    user_ids = Set.new(Array(user_ids).compact)
    return [] if user_ids.empty?

    org_repo_ids = Repository.where(organization: self).active.limit(limit).pluck(Arel.sql("/*vt+ IGNORE_MAX_MEMORY_ROWS=1 */ id"))
    return [] if org_repo_ids.empty?

    user_ids_set = user_ids.to_set

    if org_repo_ids.size <= user_ids_set.size
      Ability.where(subject_id: org_repo_ids).where(
        subject_type: "Repository",
        actor_type: "User",
        priority: Ability.priorities[:direct],
      )
        .distinct
        .pluck(:actor_id, :subject_id)
        .filter { |user_id, _repo_id| user_ids_set.include?(user_id) }
    else
      org_repo_ids_set = org_repo_ids.to_set

      Ability.where(actor_id: user_ids_set).where(
        actor_type: "User",
        subject_type: "Repository",
        priority: Ability.priorities[:direct],
      )
        .distinct
        .pluck(:actor_id, :subject_id)
        .filter { |_user_id, repo_id| org_repo_ids_set.include?(repo_id) }
    end
  end

  # Public: Get all the pending invitations for direct members of this
  # organization
  #
  # Returns an AR relation of OrganizationInvitations
  def direct_member_pending_invitations
    pending_invitations.with_business_role(:direct_member).includes(:invitee)
  end

  # Public: Get users who have been invited to join this organization. Does not include users who
  # have already accepted the invitation or users from cancelled invitations.
  #
  # Returns an ActiveRecord User relation.
  def pending_members
    User.joins("INNER JOIN organization_invitations " \
               "ON organization_invitations.invitee_id = users.id").
         where(organization_invitations: { organization_id: id }).
         merge(OrganizationInvitation.pending)
  end

  # Public: Get all the users who have been invited to be admins of this org.
  #
  # Once direct org membership ships, we can kill this and just use the
  # OrganizationInvitation scope
  #
  # Returns an Array of Users.
  def invited_admins
    @invited_admins ||= pending_invitations.with_business_role(:admin).map(&:invitee)
  end

  # Public: Get all the invitees who have been invited to be admins or direct
  # members of this organization.
  #
  # Returns an Array of OrganizationInvitations.
  def pending_non_manager_invitations
    pending_invitations.except_with_role(:billing_manager).with_valid_role.order("id ASC")
  end

  # Public: Get the role of the specified user in this org.
  #
  # user - User to check the role of.
  #
  # Returns a Organization::Role model object
  def role_of(user)
    Organization::Role.new(self, user)
  end

  # Internal: Initialize the default OAuth application policy if one has not
  # already been configured for this organization.
  #
  # Returns nothing.
  def initialize_application_policy
    return unless restrict_oauth_applications.nil?

    self.restrict_oauth_applications = GitHub.oauth_application_policies_enabled?

    # Don't let this method return false. This method is invoked in a
    # before_validation callback, and returning false would inadvertently
    # prevent the record from being saved.
    nil
  end

  # Public: Has someone attempted to destroy the owners team recently?
  #
  # Returns a boolean.
  def tried_to_destroy_owners_team_recently?
    destroy_owners_team_attempted_at.present? && destroy_owners_team_attempted_at > 10.minutes.ago
  end

  # Public: The last time the organization was active.
  #
  # Returns a string containing a date or "No activity".
  def last_active
    admin = admins.first
    if admin && event = admin.events(type: :org, param: self).first
      event.created_at.in_time_zone
    else
      "No activity"
    end
  end

  # Public: Get a list of IDs for repositories in this organization that are accessible by the
  # given user.
  #
  # user - a User
  # scope - optional Relation for filtering
  #
  # Returns an Array of Integers.
  def all_org_repo_ids_for_user(user, scope: nil)
    all_org_repos_for_user(user, scope: scope).pluck(:id)
  end

  # Return a list of repositories for this org, accessible by the given
  # user, including:
  #
  # - public repositories which are owned by the org
  # - repositories owned by the org, when user is a member of org's Owners team
  # - repositories owned by the org, when user is a member of an org team which
  #   grants access to the repository
  # - internal repositories owned by the org, when user is a member of the org's business
  #
  # user - a User
  # scope - optional Relation for filtering
  # id_in_clause_limit - Integer limit for the `IN` clause for `Repository.where(id: [Int])` queries
  #
  # Returns an Array of Repositories.
  def all_org_repos_for_user(user, scope: nil, id_in_clause_limit: nil)
    public_scope = self.org_repositories.public_scope
    return filter_scope(public_scope, filter: scope) if user.nil?

    if user.feature_enabled?(:org_scoped_ari)
      repo_ids_with_team_membership = org_scoped_repo_ids_with_team_membership(user)
    else
      repo_ids_with_team_membership = unscoped_repo_ids_with_team_membership(user)
    end

    if id_in_clause_limit
      repo_ids_with_team_membership = repo_ids_with_team_membership.first(id_in_clause_limit)
    end

    if supports_internal_repositories?
      user_business_ids = if id_in_clause_limit
        user.business_ids.first(id_in_clause_limit)
      else
        user.business_ids
      end

      internal_repos_ids = org_repositories.
        left_joins(:internal_repository).
        where(internal_repository: { business_id: user_business_ids }).
        ids

      if id_in_clause_limit
        internal_repos_ids = internal_repos_ids.first(id_in_clause_limit)
      end
    else
      internal_repos_ids = []
    end

    repo_ids = repo_ids_with_team_membership + internal_repos_ids
    repos_scope = if user.feature_enabled?(:use_mysql8_all_org_repos_query)
      public_scope.or(self.org_repositories.active.where(id: repo_ids))
    else
      public_scope.or(Repository.active.where(id: repo_ids))
    end

    yield (repo_ids_with_team_membership&.size || 0) + (internal_repos_ids.size) if block_given?

    filter_scope(repos_scope, filter: scope)
  end

  def unscoped_repo_ids_with_team_membership(user)
    # The current user may be allowed to see this org's private repos if those repos are private forks
    # of repos owned by an org the user is an admin of. If this org has no private forks, there's
    # no need to check for this case, and if the user is an admin of this org they'll be able to
    # see those repos without a special oopfs check via their admin access.
    include_oopfs = !(self.adminable_by?(user) || self.repositories.forks.private_scope.none?)

    organization_ids = Repository.active.owned_by(self).pluck(Arel.sql("/*vt+ IGNORE_MAX_MEMORY_ROWS=1 */ id"))

    if organization_ids.size > REPO_INTERSECTION_THRESHOLD
      user.associated_repository_ids(
        including: [:direct, :indirect],
        repository_ids: organization_ids,
        include_oopfs: include_oopfs,
      )
    else
      user.associated_repository_ids( # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
        including: [:direct, :indirect],
        include_oopfs: include_oopfs,
      ) & organization_ids
    end
  end

  def org_scoped_repo_ids_with_team_membership(user)
    # The user may be allowed to see this org's private repos if those repos are private forks
    # of repos owned by an org the user is an admin of. Pass this organization to
    # User#associated_repository_ids so results can be scoped more efficiently.
    # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
    user.associated_repository_ids(including: [:direct, :indirect], organization: self)
    # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
  end

  # Return a list of ids of repositories owned by any of the supplied organizations, accessible by the given
  # user, including:
  #
  # - public repositories which are owned by any of the the orgs
  # - private repositories owned by any of the orgs, when user is a member of org's Owners team
  # - private repositories owned by any of the orgs, when user is a member of an org team which
  #   grants access to the repository
  #
  # org_ids - a list of Organization ids
  # user - a User
  #
  # Returns an Array of Repository ids
  def self.all_repo_ids_for_orgs_for_user(org_ids, user)
    public_repos_for_orgs = Repository.public_scope.active.where(organization_id: org_ids).ids
    private_repos_for_orgs = Repository.private_scope.active.where(organization_id: org_ids)
    org_private_repos_for_user = user.associated_repository_ids(
      including: [:direct, :indirect],
      repository_ids: private_repos_for_orgs.pluck(Arel.sql("/*vt+ IGNORE_MAX_MEMORY_ROWS=1 */ id"))
    )

    public_repos_for_orgs + org_private_repos_for_user
  end

  # Public - Which layouts should be used when viewing this in site admin
  #
  # Returns "user" for users, and "organization" for orgs
  def site_admin_context
    "organization"
  end

  # Internal: can this organization be billed?
  #
  # Returns a boolean
  def billable?
    true
  end

  # Internal: can the org be subscribed to notifications
  #
  # Returns false
  def newsies_enabled?
    false
  end

  # Public: Returns an elasticsearch query string that will find all of this
  # org's audit log events
  #
  # Returns a String which can be passed to elasticsearch as a `query_string`
  def audit_log_query
    "((_exists_:org AND org_id:#{id}) OR user_id:#{id} OR actor_id:#{id} OR data.old_user_id:#{id})"
  end

  def audit_log_kql_query
    "webevents | where (org_id == #{id} or user_id == #{id} or actor_id == #{id})"
  end

  # Public: Can the specified actor view projects on this organization?
  #
  # actor - The User trying to view projects.
  #
  # Returns a boolean.
  def projects_readable_by?(actor)
    if actor.can_have_granular_permissions?
      # When the actor is an app, we need to check if they've been granted
      # access to the organization's projects.
      resources.organization_projects.readable_by?(actor)
    else
      # When the actor is a user, they can always try to read an organization's
      # projects, since there may be public projects that are visible to
      # everyone. Per-project checking is done elsewhere.
      true
    end
  end

  # Public: Can the specified actor view projects on this organization?
  #
  # actor - The User trying to view projects.
  #
  # Returns Promise<bool>
  def async_projects_readable_by?(actor)
    if actor.can_have_granular_permissions?
      resources.organization_projects.async_readable_by?(actor)
    else
      Promise.resolve(true)
    end
  end

  # Public: Can the specified actor create/edit projects on this organization?
  #
  # actor - The User trying to create/edit projects.
  #
  # Returns a boolean.
  def projects_writable_by?(actor)
    resources.organization_projects.writable_by?(actor)
  end

  # Public: Can the specified actor create/edit projects on this organization?
  #
  # actor - The User trying to create/edit projects.
  #
  # Returns Promise<bool>
  def async_projects_writable_by?(actor)
    resources.organization_projects.async_writable_by?(actor)
  end

  # Public: Can the specified actor administer projects on this organization?
  #
  # actor - The User trying to administer projects.
  #
  # Returns a boolean.
  def projects_adminable_by?(actor)
    # We intentionally use writable_by? here, since there's no concept of
    # admin on projects in the pre-Abilities permission system.
    projects_writable_by?(actor)
  end

  # Public: Can the specified actor administer projects on this organization?
  #
  # actor - The User trying to administer projects.
  #
  # Returns Promise<bool>
  def async_projects_adminable_by?(actor)
    # We intentionally use writable_by? here, since there's no concept of
    # admin on projects in the pre-Abilities permission system.
    async_projects_writable_by?(actor)
  end

  # Public: The domains associated with this organization that are eligible to receive emails,
  # associated either directly or through the owning enterprise. By default, will return all
  # domains that are verified or approved, though those results can be limited to just approved
  # or just verified.
  #
  # include_verified  -   include verified domains
  # include_approved  -   include approved domains
  #
  # Returns a Promise<Array[VerifiableDomain]>.
  def async_email_eligible_domains(include_verified: true, include_approved: true)
    return Promise.resolve(VerifiableDomain.none) unless include_verified || include_approved

    async_business.then do
      VerifiableDomain.usable_for(self).filtered_by_type(include_verified, include_approved)
    end
  end

  # Public: sync version of async_email_eligible_domains
  #
  # Returns: Array[VerifiableDomain]
  def email_eligible_domains(include_verified: true, include_approved: true)
    return VerifiableDomain.none unless include_verified || include_approved

    async_email_eligible_domains(
      include_verified: include_verified, include_approved: include_approved
    ).sync
  end

  # Public: get an array of url's for the VerifiableDomain's for this
  # organization which are eligible to receive emails. The result is de-duplicated,
  # in case the org and the enterprise have verified or approved the same domain.
  # By default, will return all domains that are verified or approved, though those
  # results can be limited to just verified or approved domains. Memoizes the result.
  #
  # include_verified  -   include verified domains
  # include_approved  -   include approved domains
  #
  # Returns: Array[String]
  def email_eligible_domain_urls(include_verified: true, include_approved: true)
    return [] unless include_verified || include_approved

    @verified_urls_hash ||= {}
    domain_urls = if include_verified && include_approved
      @verified_urls_hash[:all] ||= VerifiableDomain.usable_for(self).verified_or_approved
    elsif include_verified
      @verified_urls_hash[:verified] ||= VerifiableDomain.usable_for(self).verified
    elsif include_approved
      @verified_urls_hash[:approved] ||= VerifiableDomain.usable_for(self).approved
    end

    domain_urls.map(&:domain).uniq
  end

  # Public: check if an org admin can see this email address. In GHEC, admins can see only verified
  # domain emails. In GHES, they can see verified or approved domain emails. Cannot see any
  # email from a domain that's neither approved nor verified.
  #
  # user_email  -   UserEmail to check
  #
  # Returns: Boolean
  def show_user_email_address?(user_email)
    verifiable_domain = eligible_domain_emails_hash[user_email.normalized_domain]

    # Don't show email if we can't find a domain for it.
    return false unless verifiable_domain

    # Show email if its domain has been verified.
    return true if verifiable_domain.verified?

    # Don't show email if its domain is neither approved nor verified.
    # (this would be suspicious, as eligible_domain_emails_hash is supposed to only get domains
    # that are approved and/or verified)
    return false unless verifiable_domain.approved?

    # if domain is approved, but not verified, show the email only if admins are
    # allowed to see approved domain emails (true on GHES).
    VerifiableDomain.approved_domain_emails_visible_to_admins?
  end

  # Public: Returns a Hash of member IDs and an Array of their emails.
  #
  # member_ids - ids of users to get emails for.
  #
  # Returns a Hash{Integer => Array[UserEmail]}
  def domain_emails_for_member_ids(member_ids:)
    if defined?(@domain_emails_for_member_ids)
      return @domain_emails_for_member_ids
    end

    @domain_emails_for_member_ids = UserEmail.email_addresses_from_domains(
      email_eligible_domain_urls, member_ids
    )
  end

  # Public: The verified domains from this organization's profile.
  #
  # Returns an Array[String].
  def verified_profile_domains
    async_verified_profile_domains.sync
  end

  # Public: The verified domains from this organization's profile.
  #
  # Returns a Promise<Array[String]>
  def async_verified_profile_domains
    async_profile.then do
      profile_domains = [T.unsafe(self).profile_blog, T.unsafe(self).profile_email].compact.reject(&:blank?)
      normalized_domains = profile_domains.map { |domain| VerifiableDomain.normalize_domain(domain) }.to_set
      next [] unless normalized_domains.any?

      async_email_eligible_domains(include_approved: false).then do |domains|
        verified_domains = domains.map(&:domain).to_set
        if normalized_domains.subset?(verified_domains)
          (verified_domains & normalized_domains).to_a
        else
          []
        end
      end
    end
  end

  # Public: Does this organization have a verified domain on its profile?
  #
  # Returns a Boolean.
  def is_verified?
    async_is_verified?.sync
  end

  # Public: Does this organization have a verified domain on its profile?
  #
  # Returns a Promise<Boolean>.
  def async_is_verified?
    async_verified_profile_domains.then do |verified_profile_domains|
      verified_profile_domains.any?
    end
  end

  # Public: get the SAML provider for the Business that owns this Organization.
  # Note: this method will never return the Organization SAML provider - it is specifically
  # designed to retrieve the parent Business' SAML provider, if there is one.
  #
  # Returns a Promise<Business::SamlProvider>
  # will return a Promise<nil> if the Organization doesn't belong to a Business, or if
  # the Business doesn't have SAML enabled.
  def async_business_saml_provider
    async_business.then do |business|
      business&.async_saml_provider
    end
  end

  # Public: Determines if this Organization belongs to a business that has enterprise managed user provisioning enabled
  #
  # Returns a Boolean
  def enterprise_managed_user_enabled?
    self.associated_business_on_creation&.enterprise_managed_user_enabled? || !!business&.enterprise_managed_user_enabled?
  end

  # Public: Determines if this Organization belongs to a business that has enterprise managed user provisioning enabled
  #
  # Returns a Boolean
  def async_enterprise_managed_user_enabled?
    async_business.then do |business|
      !!business&.enterprise_managed_user_enabled?
    end
  end

  # Public: Determines if this Organization belongs to a business that has enterprise managed through SCIM
  #
  # Returns boolean
  def scim_managed_enterprise?
    enterprise_managed_user_enabled? ||
    enterprise_server_scim_enabled?
  end

  # Public: Determines if the Organization belongs to a business managed through SCIM on an enterprise server
  #
  # Returns a Boolean
  def enterprise_server_scim_enabled?
    !!business&.enterprise_server_scim_enabled?
  end

  # Public: Determines if the Organization belongs to a business managed through SCIM on an enterprise server
  #
  # Returns a Boolean
  def async_enterprise_server_scim_enabled?
    async_business.then do |business|
      !!business&.enterprise_server_scim_enabled?
    end
  end

  # Public: Does this organization have the EU data transfer SCC flag set?
  # Returns a boolean.
  def standard_contractual_clauses?
    Organization::KV.store.exists("organization.standard_contractual_clauses.#{self.id}").value { false }
  end

  # Public: Flags the organization as subject to EU data transfer SCC.
  # Returns nothing.
  def flag_for_standard_contractual_clauses!(actor: self)
    Organization::KV.store.setnx("organization.standard_contractual_clauses.#{id}", "1")

    payload = { org: self, prefix: "staff" }

    if actor.site_admin?
      guarded_actor = GitHub.guarded_audit_log_staff_actor_entry(actor)
      instrument :flag_for_standard_contractual_clauses, payload.merge(guarded_actor)
    else
      instrument :flag_for_standard_contractual_clauses, payload.merge(actor: actor)
    end
  end

  # Public: Remove the flag marking the organization as subject to EU data transfer SCC.
  # Returns nothing.
  def remove_standard_contractual_clauses_flag!(actor: self)
    Organization::KV.store.del("organization.standard_contractual_clauses.#{id}")

    payload = { org: self, prefix: "staff" }

    if actor.site_admin?
      guarded_actor = GitHub.guarded_audit_log_staff_actor_entry(actor)
      instrument :remove_standard_contractual_clauses_flag, payload.merge(guarded_actor)
    else
      instrument :remove_standard_contractual_clauses_flag, payload.merge(actor: actor)
    end
  end

  # Private: Sets the associated company record via the company name provided.
  # Returns a Company
  def update_company
    return if @company_name.blank?
    # Don't allow an org to have a company if it is on the Standard terms of service
    return if on_standard_terms_of_service?

    self.company = retry_on_find_or_create_error do
      Company.find_by(name: @company_name) || Company.create(name: @company_name)
    end
  end

  # returns boolean if current business should display optional event settings
  def show_optional_audit_log_event_settings?
    can_enable_audit_log_ip_disclosure?
  end

  # Public: returns boolean if current org can disclose ip
  def can_enable_audit_log_ip_disclosure?
    return false if GitHub.enterprise?
    # If part of enterprise, check if the enterprise can disclose ip
    business.nil? ? true : T.must(business).can_enable_audit_log_ip_disclosure?
  end

  # Public: returns boolean if current org can disable ip
  def can_disable_audit_log_ip_disclosure?
    # Not owned by a business
    return true if business.nil?

    # If part of enterprise and enterprise is enabled, can't disable
    !T.must(business).source_ip_disclosure_enabled?
  end

  def company=(company)
    self.companies.delete_all
    self.companies << company
  end

  def company
    self.companies.last
  end

  def terms_of_service
    @terms_of_service ||= Organization::TermsOfService.new(organization: self)
  end

  sig { returns(TradeControls::TradeScreeningRecordLink) }
  def trade_screening_record_link
    @trade_screening_record_link ||= TradeControls::TradeScreeningRecordLink.new(organization: self)
  end

  sig { returns(Billing::ContactLink) }
  def billing_contact_link
    @billing_contact_link ||= Billing::ContactLink.new(organization: self, contact_type: :billing)
  end

  def on_standard_terms_of_service?
    terms_of_service.standard?
  end

  def on_corporate_terms_of_service?
    terms_of_service.corporate?
  end

  def root_teams
    # rubocop:disable GitHub/DoNotUseLower
    Team.where(organization_id: id).where("LOWER(HEX(id)) = tree_path")
  end

  # Public: The last IP address of the Organization's most recently updated admin.
  #
  # Returns String or nil
  def last_ip
    super || recent_admin&.last_ip
  end

  def advanced_security_eligible?
    GitHub.billing_enabled? && plan.advanced_security_eligible?
  end

  def enhanced_team_posts_enabled?
    feature_enabled?(:enhanced_team_posts)
  end

  def team_discussions_disabled?
    return @is_team_discussions_disabled if defined?(@is_team_discussions_disabled)
    @is_team_discussions_disabled = feature_enabled?(:team_discussions_disabled)
  end

  def private_config_as_code_repo
    @private_config_as_code_repo ||= org_repositories.find_by(name: PRIVATE_CONFIG_AS_CODE_REPO_NAME)
  end

  # Public: Is adaptive card parsing enabled for this repository?
  def adaptive_card_parsing_enabled?
    return @adaptive_card_parsing_enabled if defined?(@adaptive_card_parsing_enabled)

    @adaptive_card_parsing_enabled = feature_enabled?(:adaptive_card_markdown_parsing)
  end

  def queuetime_metric_enabled?
    return @queuetime_metric_enabled if defined?(@queuetime_metric_enabled)
    @queuetime_metric_enabled = feature_enabled?(:queuetime_metric_enabled)
  end

  def async_notices_for(viewer:)
    Promise.all([
      async_saml_sso_banner(viewer: viewer),
    ]).then { |notices| notices.compact }
  end

  def async_saml_sso_banner(viewer:)
    Promise.all([
      async_saml_provider,
      async_business,
    ]).then do
      saml_sso_banner = User::NoticesDependency::ORGANIZATION_NOTICES[:saml_sso_banner]

      if saml_sso_enabled? &&
        member?(viewer) &&
        !ExternalIdentity.linked?(provider: external_identity_session_owner.saml_provider, user: viewer) &&
        !viewer.dismissed_organization_notice?(saml_sso_banner, self)
        saml_sso_banner
      end
    end
  end

  # Internal: can the viewer see members of this organization?
  def member_or_can_view_members?(viewer)
    direct_or_team_member?(viewer) || bot_with_access_to_members?(viewer)
  end

  # Check whether this org has the plan support and either:
  #  settings enabled for display commenter full name on the organization
  #  or user level enabling of the flag
  #
  # at a per repo level by visibility#
  #
  # visibility  - The visibility scope. :public or :private.
  def display_commenter_full_name_for_repo?(visibility:, viewer:)
    self.plan_supports_display_commenter_full_name?(visibility: visibility) && self.display_commenter_full_name_setting_enabled?
  end

  # Check if this org has a plan supporting display commenter full name
  #
  # visibility  - The visibility scope. :public or :private.
  def plan_supports_display_commenter_full_name?(visibility:)
    self.plan.supports?(:display_commenter_full_name, visibility: visibility)
  end

  # Populate organization with initial default labels.
  def populate_initial_user_labels
    UserLabel.initial_labels.each do |label_hash|
      new_label = user.user_labels.create(label_hash)
    end
  end

  def set_display_commenter_full_name_for_enterprise
    enable_display_commenter_full_name(actor: admins.first) if GitHub.enterprise?
  end

  def same_business?(user)
    return false unless business
    return false unless user&.organization?
    business == user.business
  end

  # target for conditional access is the entity governing resources that are subject to conditional access policies.
  # Since Organizations can own resources like repositories and other resources, they could define conditional access policies.
  #
  # Returns the self Organization instance
  def target_for_conditional_access
    self
  end

  # Determines the target for for conditional access for multiple Organization instances
  #
  # organizations - an enumerable of Organization
  #
  # returns Hash[Organization] => target for conditional access
  def self.multiple_target_for_conditional_access(organizations)
    ConditionalAccess::Filter.ensure_with_class(organizations, Organization)
    organizations.each_with_object({}) { |v, h| h[v] = v }
  end

  # Determines whether organization invitations can be bypassed
  #
  # Enabled on Enterprise and organizations that are part of an EMU business
  # to allow admins to directly add users to their org
  # rather than going through the invitation flow
  def bypass_org_invitations?
    GitHub.bypass_org_invites_enabled? || enterprise_managed_user_enabled?
  end

  # Public: Adds organization profile email record to be verified.
  #
  # initiator - Organization admin who initiated profile email verification
  #
  # Returns the (hopefully) created OrganizationProfileEmail...
  #   NOTE: It could be an invalid email that is not persisted!
  def add_profile_email_to_verify(initiator)
    organization_profile_emails.create(profile_email: T.unsafe(self).profile_email, initiator_id: initiator)
  end

  # Public: Instrument a request to export GitHub Connect usage metrics data for
  # EnterpriseInstallations belonging to this Organization.
  #
  # payload - Hash of custom payload data.
  #
  # Returns nothing.
  def instrument_connect_usage_metrics_export(payload = {})
    instrument :connect_usage_metrics_export, payload

    GlobalInstrumenter.instrument("github_connect.usage_metrics_export_request", {
      target_type: "ORG",
      target_name: self.name,
      target_id: self.id,
      requested_at: Time.now.utc
    })
  end

  # Public: See if any S4 stats exist for any EnterpriseInstallations belonging to this Org
  #
  # Returns boolean
  def has_s4_stats?
    s4 = GitHub::Connect::S4.new
    s4.record_count("u#{id}") > 0
  end

  # Public: Download the usage metrics data for all EnterpriseInstallation objects
  # associated with this Org.
  #
  # format - the format we want the data in: "json" or "csv"
  #
  # Returns a hash of:
  #   :blob - the JSON/CSV data from the github/s4 service
  #   :record_count - the number of records in the blob
  #   :content_type - the content type of the blob (JSON or CSV mimetype on success)
  def s4_usage_metrics(format: "json")
    s4 = GitHub::Connect::S4.new
    s4.metrics_export("u#{id}", format: format)
  end

  def eligible_for_legacy_upsell?
    return false if archived?

    self.plan.legacy? &&
    self.seats < 100
  end

  def guest_collaborators(query = nil)
    return [] unless self.business&.enterprise_managed_user_enabled?

    external_identities = ExternalIdentity.where(user_id: self.members.pluck(:id), guest_collaborator: true).includes(:user)

    if query
      external_identities = external_identities.joins(:user).where("users.login LIKE ?", "%#{query}%")
    end

    User.where(id: external_identities.pluck(:user_id))
  end

  def org_invite_email_verification_enabled?
    !bypass_org_invitations?
  end

  def org_invite_deduplication_enabled?
    !bypass_org_invitations?
  end

  sig { override.returns(T.nilable(Business)) }
  def resolve_tenant
    business
  end

  # Public: Disable features that are only available on the business_plus plan.
  #
  # Used when an Organization is downgraded from the business_plus plan or removed
  # from a Business.
  #
  # actor - User representing the actor responsible for the change.
  #
  # Returns nothing.
  def disable_business_plus_features(actor:)
    enterprise_installations.destroy_all
    if restrict_notifications_to_verified_domains?
      disable_notification_restrictions(actor: actor)
    end
    saml_provider&.destroy
    if ip_allowlist_enabled?
      disable_ip_allowlist(actor: actor)
    end
    if ssh_certificate_requirement_enabled? && !SshCertificateAuthority.eligible_for_feature?(self)
      disable_ssh_certificate_requirement(actor)
    end
    if ip_allowlist_app_access_enabled?
      disable_ip_allowlist_app_access(actor: actor)
    end
    restrict_public_repo_creation_plan_downgrade(actor: actor)
  end

  def exceeds_owned_repo_limit?
    repositories.limit(MEGA_ORG_REPOS_THRESHOLD).count == MEGA_ORG_REPOS_THRESHOLD
  end

  # Private: Perform bulk organization membership addition instrumentation.
  #
  # users       - an array of users to add as a member
  # action      - action to update to. A String or Symbol, :read, :write, or :admin. Defaults
  #               to :read
  # adder       - The optional User adding the user
  # invitation  - The optional OrganizationInvitation inviting the user
  # caller_type - The optional Symbol caller type
  #
  # Returns nothing.
  sig { params(users: T::Array[User], action: T.any(String, Symbol), adder: T.nilable(User), invitation: T.nilable(OrganizationInvitation), caller_type: T.nilable(Symbol)).void }
  def instrument_add_members(users, action, adder, invitation, caller_type = nil)
    payloads = users.map { |user| get_instrument_options(user, action, adder, invitation, caller_type) }
    if EnterpriseTeam.enabled_for_organizations?(business: self.business) && caller_type == :enterprise_team
      BackgroundInstrumentationJob.perform_later self, :add_member, payloads
    else
      payloads.each { |payload| instrument_add_member payload }
    end
  end

  sig { params(user_ids: T::Array[Integer], organization_ids: T::Array[Integer], actor: T.nilable(User), action: Symbol, business: T.nilable(Business), caller_type: T.nilable(Symbol), team_ids: T::Array[Integer]).returns(T::Hash[Integer, T::Array[Integer]]) }
  def self.add_users_to_organizations(user_ids:, organization_ids:, actor:, action: :read, business: nil, caller_type: nil, team_ids: [])
    # Filter out no 2fa users from orgs that require 2fa
    user_ids_without_2fa = []
    org_ids_without_2fa = []
    organizations = Organization.where(id: organization_ids).to_a
    if !business&.two_factor_requirement_enabled? && !business&.members_without_2fa_allowed?
      user_ids_without_2fa = User.where(id: user_ids).two_factor_disabled.pluck(:id)
      if user_ids_without_2fa.any?
        two_factor_required_org_ids = organizations.reject { |o| o.members_without_2fa_allowed? }.pluck(:id)
        org_ids_with_2fa = Configuration::Entry.targeting_user_ids(two_factor_required_org_ids)
              .named(Configurable::TwoFactorRequired::KEY)
              .with_true_value
              .pluck(:target_id)
        org_ids_without_2fa = organization_ids - org_ids_with_2fa
      end
    end

    # Calculate which memberships need to be created
    all_memberships = user_ids.reduce({}) do |m, id|
      m[id] = user_ids_without_2fa.include?(id) ? org_ids_without_2fa : organization_ids
      m
    end
    existing_memberships = Ability.where(
      subject_type: "Organization",
      subject_id: organization_ids,
      actor_type: "User",
      actor_id: user_ids
    ).pluck(:actor_id, :subject_id).reduce({}) do |m, r|
      m[r[0]] = (m[r[0]] || []) + [r[1]]
      m
    end
    needed_memberships = all_memberships.keys.reduce({}) do |m, i|
      m[i] = all_memberships[i] - (existing_memberships[i] || [])
      m
    end.reject do |_, v|
      v.nil? || v.empty?
    end
    new_memberships = []
    now = Time.now
    abilities = needed_memberships.flat_map do |uid, org_ids|
      org_ids.each { |oid| new_memberships.push([uid, oid]) }
      org_ids.map do |oid|
        new_memberships.push([uid, oid])
        {
          subject_type: "Organization",
          subject_id: oid,
          actor_type: "User",
          actor_id: uid,
          action: action,
          priority: :direct,
          created_at: now,
          updated_at: now
        }
      end
    end

    # TODO this should be batched for multiple orgs
    org_teams = T.let(nil, T.nilable(T::Hash[T.nilable(Integer), T::Array[Team]]))
    if existing_memberships.any? && !team_ids.empty? && caller_type == :enterprise_team
      org_teams = Team.where(id: team_ids).group_by(&:organization_id)

      organization_ids.each do |org_id|
        org_team = org_teams[org_id]&.first
        unless org_team
          GitHub.logger.warn("Organization team not found",
            "code.namespace" => self.class.name,
            "code.function" => __method__,
            "gh.organization_id" => org_id,
          )
          next
        end

        already_members_user_ids = existing_memberships.select { |_, subject_ids| subject_ids.include?(org_id) }.keys
        # avoid creating admin entries just because the user was already in the org due to membership from another ET managed team
        potential_admin_user_ids = already_members_user_ids - OrganizationMembershipEntry.where(organization_id: org_id, user_id: already_members_user_ids, adder_type: :enterprise_team).pluck(:user_id).uniq
        new_admin_entries = potential_admin_user_ids - OrganizationMembershipEntry.where(organization_id: org_id, user_id: potential_admin_user_ids, adder_type: :admin).pluck(:user_id).uniq
        with_write { T.must(org_team).organization&.bulk_add_organization_membership_entry(user_ids: new_admin_entries, team: org_team, adder_type: :admin, caller_type: caller_type) if new_admin_entries.any? }

        # we still need to create their :enterprise_team OMEs
        newly_managed_user_ids = already_members_user_ids - new_admin_entries
        with_write { T.must(org_team).organization&.bulk_add_organization_membership_entry(user_ids: newly_managed_user_ids, team: org_team, adder_type: :enterprise_team, caller_type: caller_type) if newly_managed_user_ids.any? }
      end
    end


    return {} if abilities.empty?
    Ability.transaction do
      abilities.in_groups(100, false).each do |batch|
        with_write { Ability.insert_all(batch) }
      end
    end
    PermissionCache.clear

    # Add OMEs for unaffiliated users TODO this should be batched for multiple orgs
    if !team_ids.empty? && caller_type == :enterprise_team
      org_teams ||= Team.where(id: team_ids).group_by(&:organization_id)
      organization_ids.each do |org_id|
        org_team = org_teams[org_id]&.first
        next unless org_team
        users_added = needed_memberships.select { |_, subject_ids| subject_ids.include?(org_id) }.keys
        with_write { T.must(org_team).organization&.bulk_add_organization_membership_entry(user_ids: users_added, team: org_team, caller_type: caller_type, adder_type: :enterprise_team) if users_added.any? }
      end
    end

    needed_memberships
  end

  # Public: Cancel pending invitations related to the organization where the
  # given user is either the inviter or the invitee. Includes direct membership
  # to organization owned repositories.
  #
  # user  - User involved in the invitations to be cancelled.
  # force - Boolean indicating if abilities/permissions checks should be
  # performed before cancelling. Defaults to false.
  #
  # Returns nothing.
  def cancel_all_invitations_involving(user, force: false)
    cancel_all_invitations_from(user, force: force)
    cancel_all_invitations_to(user)
    cancel_all_repository_invitations_involving(user)
  end

  # Public: Deletes the business user account for a user who is in this organization
  # and not in any other organization in the business
  #
  # user - the user to be removed from the business
  #
  # Returns nothing.
  def remove_user_from_business(user)
    return if GitHub.single_business_environment?
    # This feature flag is moving the responsibility of removing BUAs to the business
    return if T.must(business).feature_enabled?(:remove_unaffiliated_users_from_business)

    return unless unique_business_member_ids.include?(user.id)

    with_write { T.unsafe(T.must(business).user_accounts).remove_members([user.id]) }
  end

  private

  # Private: Perform organization membership addition instrumentation.
  #
  # payload - A hash containing the following keys:
  #           :user       - The User to add as a member
  #           :action     - The action to update to. A symbol or string, :read, :write, or :admin. Defaults to :read
  #           :adder      - The optional User adding the user
  #           :invitation - The optional OrganizationInvitation inviting the user
  #
  # Returns nothing.
  sig { params(payload: T::Hash[Symbol, T.untyped]).void }
  def instrument_add_member(payload)
    instrument :add_member, payload
    options = payload.merge(org: self, action: :add)
    GlobalInstrumenter.instrument "org.add_member", options
  end

  sig { params(user: User, action: T.any(String, Symbol), adder: T.nilable(User), invitation: T.nilable(OrganizationInvitation), caller_type: T.nilable(Symbol)).returns(T::Hash[Symbol, T.untyped]) }
  def get_instrument_options(user, action, adder, invitation, caller_type)
    instrument_options = { user: user, permission: action }
    instrument_options[:actor] = adder if adder.present?
    if invitation.present?
      instrument_options[:invitation_id] = invitation.id
      instrument_options[:invitation_email] = invitation.email if invitation.email
    end
    if GitHub.context[:hide_staff_user] && GitHub.guard_audit_log_staff_actor?
      instrument_options.merge!(GitHub.guarded_audit_log_staff_actor_entry(adder))
      # GlobalInstrumenter wants a real user
      instrument_options[:actor] = User.staff_user
    end
    instrument_options[:timestamp_override] = Time.current if EnterpriseTeam.enabled_for_organizations?(business: self.business) && caller_type == :enterprise_team
    instrument_options
  end

  # Internal: block users from adding billing emails that appear on the sanctions list
  #
  # Returns nothing.
  def cannot_add_sanctioned_billing_emails
    if ::TradeControls::Domains.sanctioned_email?(billing_email)
      errors.add(:billing_email, "cannot add #{billing_email} - #{::TradeControls::Notices.notice_as_plaintext(:sanctioned_domain_warning)}")
    end
  end

  # Internal: block users from adding billing emails that appear on the disposable list
  def cannot_add_disposable_billing_emails
    if UserEmail::DisposableEmailsDependency.disposable_email?(billing_email)
      errors.add(:billing_email, "cannot add #{billing_email} - #{UserEmail::GENERIC_DOMAIN_ERROR}")
    end
  end

  # Internal: cancel pending organization invitations where the
  # given user is the inviter.
  #
  # user - User involved in the invitations to be cancelled.
  # force - Boolean indicating if abilities/permissions checks should be
  # performed before cancelling. Defaults to false.
  #
  # Returns nothing.
  def cancel_all_invitations_from(user, force: false)
    pending_invitations.where(inviter_id: user.id).each do |invitation|
      # Only cancel pending invitations from the user when forced or when the
      # user is no longer able to send invitations:
      if force || cannot_send_invitations?(user: user, teams: invitation.teams, role: invitation.role)
        invitation.cancel(actor: user)
      end
    end
  end

  # Internal: can the given user send invitations on behalf of the given teams
  # for the given role?
  #
  # user  - User to check ability to send invitations.
  # teams - Teams to check abilities to send invitations to.
  # role  - The role on the given teams that the invitation is intended for.
  #
  # Returns a Boolean.
  def cannot_send_invitations?(user:, teams:, role:)
    !user.can_send_invitations_for?(self, teams: teams, role: role)
  end

  # Internal: cancel pending organization invitations where the
  # given user is the invitee.
  #
  # user - User involved in the invitations to be cancelled.
  #
  # Returns nothing.
  def cancel_all_invitations_to(user)
    pending_invitations.where(invitee_id: user.id).each { |i| i.cancel(actor: user) }
  end

  # Internal: cancel pending invitations to org-owned repositories where the
  # given user is either the inviter or invitee.
  #
  # user - User involved in the invitations to be cancelled.
  #
  # Returns nothing.
  def cancel_all_repository_invitations_involving(user)
    RepositoryInvitation.cancel_all_invitations_involving(
      repo_ids: org_repositories.pluck(Arel.sql("/*vt+ IGNORE_MAX_MEMORY_ROWS=1 */ id")),
      user: user,
    )
  end

  # Private: Removes all User moderators from this organization.
  #
  # Returns a Boolean.
  def remove_user_moderators
    moderation.remove_all_user_moderators
  end

  # Internal: Instrument billing email change.
  #
  # Returns nothing.
  def instrument_billing_email_change
    GitHub.instrument "billing.change_email", org_id: id, org: login,
      email: billing_email, old_email: organization_billing_email_before_last_save
  end

  # Internal: Check if we can delete this organization.
  #
  # Return true if it's not the trusted org.
  def check_trusted_oauth_apps_owner
    throw :abort if trusted_oauth_apps_owner?
  end

  # Internal: Check if the specified user can have their membership with this
  # org publicized.
  #
  # user - User we're trying to publicize.
  #
  # Returns a boolean.
  def member_publicizable?(user)
    member?(user)
  end

  def all_team_members
    return User.none if new_record?
    User.where(id: all_team_member_ids)
  end

  def all_team_member_ids
    return [] if new_record?
    Team.user_ids_for(team_ids)
  end

  # Internal: is a user a member of one of this organization's teams teams?
  def team_member?(user)
    user && user.user? && !user.new_record? && all_team_member_ids.include?(user.id)
  end

  # Internal: Get all repositories owned by this org that the user has access to
  # through team memberships, where their team-based access is more priviledged than direct access grants.
  # Return the highest-ranking role granted across all teams for each qualifying repository.
  #
  # Returns a hash of: { repository_id => role_name }
  def team_roles_to_preserve(user)
    all_team_ids = Set.new
    teams_for(user).each { |team| all_team_ids.merge(team.id_and_ancestor_ids) }

    return {} if all_team_ids.blank?

    repo_ids = Repository.active.where(owner_id: id).pluck(:id)

    # Retrieve the repository id and team-based action of any direct or
    # team-based abilities a user has on this org's repos where the direct
    # action either does not exist or the team-based action is better.
    # Explicitly does not consider default org permissions nor permissions
    # through org adminship.
    team_abilities = []

    repo_ids.each_slice(1000) do |ids|
      query_bindings = {
        user_id: user.id,
        team_ids: all_team_ids.to_a,
        repo_ids: ids,
        direct: Ability.priorities[:direct],
      }

      query = Arel.sql <<-SQL, **query_bindings
        SELECT subject_id, MAX(abilities.action) team_action
        FROM abilities
        LEFT OUTER JOIN (
          SELECT subject_id repository_id, action
          FROM abilities
          WHERE actor_id   = :user_id
          AND actor_type   = 'User'
          AND subject_type = 'Repository'
          AND priority     = :direct
        ) direct_actions
        ON direct_actions.repository_id = abilities.subject_id
        WHERE subject_type        = 'Repository'
        AND abilities.subject_id IN (:repo_ids)
        AND priority              = :direct
        AND actor_type            = 'Team'
        AND actor_id             IN (:team_ids)
        AND (direct_actions.action IS NULL OR abilities.action >= direct_actions.action)
        GROUP BY subject_id
      SQL

      team_abilities.concat(Ability.connection.select_rows(query))
    end

    # For each result, the team ability on the repo is at least equal to the direct ability
    # So, there is a chance the team ability is role based, and we need to preserve to role.
    user_roles = []
    all_repo_ids = team_abilities.map { |repo_id, _| repo_id }.uniq
    all_repo_ids.each_slice(1000) do |repo_ids|
      ur_scope = UserRole.includes(:role).where(target_type: "Repository", target_id: repo_ids)
      batch_user_roles = ur_scope.where(actor_type: "Team", actor_id: all_team_ids.to_a)
        .or(ur_scope.where(actor_type: "User", actor_id: user.id))
      user_roles.concat(batch_user_roles.to_a)
    end

    roles_to_preserve = team_abilities.map do |repo_id, team_ability|
      user_roles_for_repo = user_roles.select { |ur| ur.target_id == repo_id }
      next [repo_id, Ability.actions.key(team_ability)] if user_roles_for_repo.empty?

      best_role_rank = user_roles_for_repo.map { |ur| ur.role.action_rank }.max
      if best_role_rank < team_ability
        next [repo_id, Ability.actions.key(team_ability)]
      else
        best_user_roles = user_roles_for_repo.select { |ur| ur.role.action_rank == best_role_rank }
        user_custom_roles = best_user_roles.select { |ur| ur.role.custom? }
        best_user_roles = user_custom_roles if user_custom_roles.any?

        if best_user_roles.any? { |ur| ur.actor_type == "User" }
          next nil # no changes needed, direct assignments are preserved
        else
          chosen_role = best_user_roles.sort_by { |ur| ur.actor_id }.first.role
          next [repo_id, chosen_role.name]
        end
      end
    end

    T.unsafe(roles_to_preserve.reject { |repo_role| repo_role.nil? }).to_h
  end

  # Internal: Take all the repository permissions that the specified user has
  # through this organization's teams and directly assign the most-privileged role.
  #
  # user - The user whose permissions we're converting.
  #
  # Returns nothing.
  def convert_team_permissions_to_direct_abilities(user)
    roles_by_repo = team_roles_to_preserve(user)

    Repository.where(id: roles_by_repo.keys).each do |repo|
      role_name = roles_by_repo[repo.id]

      # We use add_member_without_validation_or_notifications instead of
      # add_member here because we don't want to subscribe the user to the repo
      # or send them emails.
      repo.add_member_without_validation_or_notifications(user, action: role_name)
    end
  end

  # Internal: is the viewer a Mannequin that will never have any permissions
  def mannequin_without_access_to_members?(viewer)
    viewer.is_a?(Mannequin)
  end

  # Internal: is the viewer a Bot who does NOT have permission to read 'members'
  #
  # * A Bot of installation without permission on members, cannot see all
  #   of the org's members
  def bot_without_access_to_members?(viewer)
    viewer.is_a?(Bot) && !resources.members.readable_by?(viewer)
  end

  # Internal: is the viewer a Bot who DOES have permission to read 'members'
  def bot_with_access_to_members?(viewer)
    viewer.is_a?(Bot) && resources.members.readable_by?(viewer)
  end

  # Internal: is the viewer a regular user who is not a member of the org?
  def human_non_member?(viewer)
    (viewer.user? && !member?(viewer))
  end

  # Remove all review request data
  def clear_review_requests
    issue_event_details = IssueEventDetail.joins(issue_event: [{ issue: [:pull_request] }])
      .joins("INNER JOIN `review_requests` ON `review_requests`.`pull_request_id` = `pull_requests`.`id`")
      .where("review_requests.reviewer_id" => id)
      .where("review_requests.reviewer_type" => "User")
      .where("issue_events.event" => %w(review_requested review_request_removed))
      .where("issue_event_details.subject_id" => id)

    issue_events = issue_event_details.map(&:issue_event)

    issue_events.map { |ie| T.must(ie).destroy }
    issue_event_details.map(&:destroy)

    ReviewRequest.where(reviewer_id: id, reviewer_type: "User").each do |request|
      request.dismiss
      request.save
    end
  end

  def actor
    @actor ||= (User.find_by(id: GitHub.context[:actor_id]) || User.ghost)
  end

  # Internal: is the organization is in the process of being created? During
  #           creation, Organization::Creator#perform will set the :creator
  #           accessor; otherwise :creator should be nil.
  def being_created?
    !creator.nil?
  end

  # Internal: Deletes business user accounts for users who are in this organization
  # and not in any other organization in the business
  #
  # Returns nothing.
  def remove_business_user_accounts_for_members
    return if GitHub.single_business_environment?
    return unless business.present?

    T.unsafe(T.must(business).user_accounts).remove_members(unique_business_member_ids)
  end

  # Internal: Deletes custom property definitions
  #
  # Returns nothing.
  def remove_custom_property_definitions
    CustomProperties::Public.destroy_all_definitions(self)
  end

  # Private: Creates a business user account for a user who is in this organization
  # and not in any other organization in the business
  #
  # user - the user to be added to the business
  #
  # Returns nothing.
  def add_user_to_business(user)
    return if GitHub.single_business_environment?
    T.must(business).add_user_accounts([user.id])
  end

  # Private: Creates a business user account for every user who is in this organization
  # and not in any other organization in the business
  #
  # users - the users to be added to the business
  #
  # Returns nothing.
  def bulk_add_users_to_business(user_ids)
    return if GitHub.single_business_environment?
    T.must(business).add_user_accounts(user_ids)
  end

  # Internal: Filters original scope using another scope if it exists
  #
  # scope - the original scope to filter
  # filter - the scope to use for the merge
  #
  # Returns filtered scope
  def filter_scope(scope, filter: nil)
    filter ? scope.merge(filter) : scope
  end

  # Returns organizations that have a team sync tenant with the appropriate
  # status
  scope :with_team_sync_status, lambda { |status|
    org_ids = TeamSync::Tenant.
      where(organization_id: ids, status: status).
      pluck(:organization_id)

    where(id: org_ids)
  }

  # Private: Find the most recently updated admin for this Organization.
  #
  # If the Organization has no admins (which should be rare), returns nil.
  #
  # Returns User or nil
  def recent_admin
    admins.order(updated_at: :desc).limit(1).first
  end

  # Validates that the (primary) billing email is not in the list of external billing emails
  def billing_email_is_unique
    # Only validate uniqueness if the billing email is valid
    if errors[:billing_email].blank?
      unless self.billing_external_emails.find_by(email: self.billing_email).blank?
        errors.add(:billing_email, "is already in the list of email recipients")
      end
    end
  end

  def set_spammy_notice
    return unless GitHub.spamminess_check_enabled?

    SpammyOrgCheckJob.perform_later(self) if spammy?
  end

  def set_billingless_org_notice
    return unless billing_email.blank? && paid_plan?

    Billing::BillinglessOrgCheckJob.perform_later(self)
  end

  def set_disabled_org_billing_notice
    return unless disabled? && paid_plan?

    Billing::DisabledOrgBillingCheckJob.perform_later(self)
  end

  def set_disabled_org_repos_notice
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    is_over_limit = over_plan_limit?
    finish = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    elapsed_ms = ((finish - start) * 1000).round
    GitHub.dogstats.distribution("organization.global_notice.plan_limit_model_check", elapsed_ms)

    return unless is_over_limit

    Billing::DisabledOrgReposCheckJob.perform_later(self)
  end

  def eligible_domain_emails_hash
    @domains_hash ||= email_eligible_domains.index_by(&:domain)
  end

  def organization_collaborator_cache_write?
    feature_enabled?(:collaborator_cache_write) || business&.feature_enabled?(:collaborator_cache_write)
  end
end
