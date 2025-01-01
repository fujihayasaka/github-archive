# typed: true
# frozen_string_literal: true

require "html_truncator"

class Repository < ApplicationRecord::Domain::Repositories
  #  _______  _______  _______  _______
  # |       ||       ||       ||       |
  # |  _____||_     _||   _   ||    _  |
  # | |_____   |   |  |  | |  ||   |_| |
  # |_____  |  |   |  |  |_|  ||    ___|
  #  _____| |  |   |  |       ||   |
  # |_______|  |___|  |_______||___|
  #
  # Reach out to #repos-platform before adding dependencies.
  extend Repository::Creatable
  extend GitHub::SimplePagination
  extend GitHub::RenameColumn
  extend GitHub::Encoding

  include Repositories::IRepository
  include Entity
  include GitHub::ColumnCount
  include ActiveSupport::NumberHelper
  include Ability::Subject
  include Ability::Membership
  include GitHub::FlipperActor
  include GitHub::VexiActor
  include GitHub::RateLimitedCreation
  include GitHub::Validations
  include GitHub::UTF8
  include GitHub::Relay::GlobalIdentification
  include GitHub::BatchedScope
  include Dumpable
  include GitRepository::UrlMethods
  include GitRepository::SpokesAdapter
  include Repository::ConsistencyCheck
  include Repository::Backup
  include Repository::DiskQuota
  include Repository::StaffTools
  include Repository::StorageAdapter
  include Repository::LegalHold
  include TreeListable
  include Notifications::SubscribableList
  include Spam::Spammable
  include StaffAccessible
  include Permissions::Attributes::Wrapper
  include Repository::AbilityDependency
  include Repository::ActionsAppDependency
  include Repository::ActionsDependency
  include Repository::ActivityDependency
  include Repository::AdvancedSecurityDependency
  include Repository::AdvisoryDependency
  include Repository::AppDependency
  include Repository::ArchiveCommandDependency
  include Repository::ArchivedDependency
  include Repository::AuthVersionDependency
  include Repository::BillingDependency
  include Repository::BranchRenamesDependency
  include Repository::BranchProtectionDependency
  include Repository::BusinessDependency
  include Repository::CheckDependency
  include Repository::CodeScanningDependency
  include Repository::CodeqlBulkBuilderDependency
  include Repository::CommunityDependency
  include Repository::ConfigRepoDependency
  include Repository::ConfigurationDependency
  include Repository::ContributorsDependency
  include Repository::CustomPropertiesDependency
  include Repository::CustomKeyLinksDependency
  include Repository::DependabotDependency
  include Repository::DependenciesDependency
  include Repository::DeploymentDependency
  include Repository::DeployKeysDependency
  include Repository::DiscussionsDependency
  include Repository::DownloadsDependency
  include Repository::EditorConfigDependency
  include Repository::EnterpriseManagedUsersDependency
  include Repository::FeatureFlagsDependency
  include Repository::GitDependency
  include Repository::GroupDependency
  include Repository::FundingLinksDependency
  include Repository::HovercardDependency
  include Repository::IgnoreDependency
  include Repository::ImageDependency
  include Repository::InstallationsDependency
  include Repository::InteractionLimitDependency
  include Repository::InstrumentationDependency
  include Repository::IssueDependency
  include Repository::LanguageAnalysisDependency
  include Repository::LockDependency
  include Repository::MembershipDependency
  include Repository::MergeQueueDependency
  include Repository::MilestoneDependency
  include Repository::NetworkDependency
  include Repository::NetworkPrivilegeDependency
  include Repository::NotificationsDependency
  include Repository::OauthApplicationPolicyDependency
  include Repository::OrganizationsDependency
  include Repository::PagesDependency
  include Repository::PinnedEnvironmentsDependency
  include Repository::PermissionExportDependency
  include Repository::PermissionsDependency
  include Repository::PinnedIssuesDependency
  include Repository::PlanDependency
  include Repository::PreferredFilesDependency
  include Repository::ProjectsSettingsDependency
  include Repository::PullRequestDependency
  include Repository::ProgrammaticAccessDependency
  include Repository::RateLimitDependency
  include Repository::ReceiveHooksDependency
  include Repository::ReflogDependency
  include Repository::RefsDependency
  include Repository::RemoteCacheDependency
  include Repository::RemovalDependency
  include Repository::RenameDependency
  include Repository::ReportDependency
  include Repository::RestoreDependency
  include Repository::RoleBasedPermissionsDependency
  include Repository::RpcDependency
  include Repository::SearchDependency
  include Repository::SecurityCenterDependency
  include Repository::SecurityProductsDependency
  include Repository::SidebarSectionVisibilityDependency
  include Repository::SpamDependency
  include Repository::SpokesAPIDependency
  include Repository::SponsorsDependency
  include Repository::StafftoolsDependency
  include Repository::StatusesDependency
  include Repository::TemplateDependency
  include Repository::TieredReportingDependency
  include Repository::TagProtectionStatesDependency
  include Repository::TokenScanningDependency
  include Repository::TopicsDependency
  include Repository::TradeComplianceDependency
  include Repository::TransferDependency
  include Repository::TwoFactorRequirementDependency
  include Repository::VisibilityDependency
  include Repository::VulnerabilityAlertRuleDependency
  include Repository::VulnerabilityDependency
  include Repository::WatchersDependency
  include Repository::WebCommitDependency
  include Repository::WikiDependency
  include Repository::WorkflowsDependency
  include Repository::ContributionsDependency
  include Repository::LatestReleaseDependency
  include RuleEngine::RuleSettingsDependency
  include GitRepository::CommitsDependency
  include GitRepository::CommitsDependency::ICommitsDependency
  include Repository::Sequence
  include LegacyImportable
  include HydroEventHelper
  include PreloadableAttributes
  include Repository::Prefillable
  include Coders::CodableColumn
  include GH::Associations::BatchMethodAdapters
  include GH::Domain::Cache::Cachable::Dirtyable
  include AttributeAccessTelemetry
  #  _______  _______  _______  _______
  # |       ||       ||       ||       |
  # |  _____||_     _||   _   ||    _  |
  # | |_____   |   |  |  | |  ||   |_| |
  # |_____  |  |   |  |  |_|  ||    ___|
  #  _____| |  |   |  |       ||   |
  # |_______|  |___|  |_______||___|
  #
  # Reach out to #repos-platform before adding dependencies.

  self.permissions_wrapper_class = Permissions::Attributes::Repository

  class CorruptionDetected < StandardError; end
  class RepoCreationOutsideOrchestration < StandardError; end
  class ComparisonMissingHeadRepo < StandardError; end
  class FailedDefaultBranchUpdateError < StandardError; end

  PUBLIC_VISIBILITY = "public"
  PRIVATE_VISIBILITY = "private"
  INTERNAL_VISIBILITY = "internal"
  VISIBILITIES = [
    PUBLIC_VISIBILITY,
    PRIVATE_VISIBILITY,
    INTERNAL_VISIBILITY
  ].freeze
  # Used to determine an upper limit on how many users can be returned in a JSON response for
  # user suggestions.
  JSON_USER_MENTION_LIMIT = 50_000
  NAME_WITH_OWNER_PATTERN = /\A[^\/]+\/[^\/]+\z/
  NAME_MAX_LENGTH = 100
  URI_TEMPLATE = Addressable::Template.new("/{owner}/{name}").freeze
  COMMITS_URI_TEMPLATE = Addressable::Template.new("/{owner}/{name}/commits{+commitish}").freeze
  # Used as the default upper limit for org membership when checking if participants have
  # access to a repo. Checking repo access in orgs with extremely large memberships (AutoDesk)
  # can cause requests to timeout
  ORG_MEMBERSHIP_VERIFICATION_LIMIT = 10_000
  # The repository name for organization level health files
  GLOBAL_HEALTH_FILES_NAME = ".github"
  # If we want to be nice, we bump this up from the default of 20 in dotcom
  INCREASED_HOOK_LIMIT = 30
  ALLOWED_OWNER_TYPES = %w(User Organization).freeze
  REPO_STARGAZERS_BATCH_SIZE = 1000
  REPO_ENV_LIMIT = 100
  VALID_ORG_REPO_ACTIONS_AND_ROLES = %i(read write admin triage maintain).freeze
  DESCRIPTION_CHAR_LIMIT = 350
  DEFAULT_ASC_SORT_FIELDS = [:full_name, :id, :name]

  class_attribute :per_page, default: 30

  attr_accessor :auto_init
  attr_accessor :expected_creation
  attr_accessor :gitignore_template
  attr_accessor :license_template
  attr_accessor :one_branch_fork
  attr_accessor :reflog_data
  attr_accessor :skip_after_create_callbacks
  attr_accessor :template_hook_failure
  attr_accessor :validate_description_length

  attr_preloadable :viewer_can_see_commenter_full_name

  FIELDS_COPIED_ON_FORK = %w(
    name
    source_id
    pushed_at
    pushed_at_usec
    public
    description
    homepage
    disk_usage
    primary_language_name_id
    has_wiki
    template
  ).freeze

  # This method returns the name of the column that stores the stargazer count.
  # The column is currently named `watcher_count` for legacy reasons, but we'll
  # probably rename it at some point in the future. Any code referencing this
  # column in SQL fragments should use this method instead of hard coding
  # "watcher_count"
  def self.stargazer_count_column
    "watcher_count"
  end

  # Public: Name of the database field used to store the repository's star count.
  # Overridden from Starrable.
  #
  # Returns a String.
  def stargazer_count_column
    self.class.stargazer_count_column
  end

  rename_column watcher_count: :stargazer_count

  sig { params(increment: T::Boolean).returns(T::Boolean) }
  def modify_stargazer_count(increment:)
    update_column_count(increment:, column_name: self.class.stargazer_count_column)
  end

  def self.private_forks_for(organization:, belonging_to_user:)
    includes(:parent)
      .where(parents_repositories: { public: false, owner_id: organization.id })
      .where(owner_id: belonging_to_user.id)
      .active
  end

  # Returns repositories owned by `belonging_to_user` that are forks (or forks of forks) of internal
  # repositories in orgs belonging to `business`.
  def self.biz_internal_forks_for(business:, belonging_to_user:)
    org_ids = business.organizations.pluck(:id)
    joins(:network)
      .joins("INNER JOIN `repositories` AS `root_repository` ON `repository_networks`.`root_id` = `root_repository`.`id`")
      .joins("INNER JOIN `internal_repositories` ON `root_repository`.`id` = `internal_repositories`.`repository_id`")
      .where(owner_id: belonging_to_user.id)
      .where("`root_repository`.`owner_id` IN (?)", org_ids)
  end

  # Override Dumpable.dumpable_options
  def self.dumpable_options(options)
    options.to_activerecord_options.update(include: :owner)
  end

  def self.dump_public(options = nil)
    unauthorized_org_ids = options&.delete(:unauthorized_org_ids)
    options = Dumpable::Options.from(options)
    if options.custom_conditions?
      raise ArgumentError, "Use #dump_page to pass custom conditions"
    end
    if unauthorized_org_ids.present?
      options.conditions = ["public = 1 AND (organization_id NOT IN (?) OR organization_id IS NULL)", unauthorized_org_ids]
    else
      options.conditions = "public = 1"
    end
    dump_page(options)
  end

  def self.dump_all(options = nil)
    options = Dumpable::Options.from(options)
    if options.custom_conditions?
      raise ArgumentError, "Use #dump_page to pass custom conditions"
    end
    dump_page(options)
  end

  # Find the repository corresponding to the full shard path. This is
  # capable of locating repositories organized in a sharded layout like
  # "/data/repositories/e/nw/e4/78/53/<network_id>/<repo_id>.git"
  # (github.com) as well as repositories organized in a simple layout like
  # "/data/repositories/<user>/<repo>.git".
  def self.with_path(path)
    if path =~ /\/[0-9a-f]\/nw\//
      repo_id = File.basename(path)[/\d+/]
      if FeatureFlag.vexi.enabled?(:repos_by_id_jobs, default: false)
        Repositories.domain.by_id(repo_id.to_i)
      else
        Repository.find_by(id: repo_id)
      end
    else
      parts = path.split("/")
      repo = parts[-1].chomp(".git").chomp(".wiki")
      owner = parts[-2]
      Repository.nwo("#{owner}/#{repo}")
    end
  end

  # Public: Find repositories with the given name and owner pairs.
  #
  # names_with_owners - Array of Strings like ["github/ce-stardust", "user/repo-name"]
  #
  # Returns an ActiveRecord Repository relation.
  #
  # When using this, always be aware of the size of the input array and use batching
  # such as `each_slice` if necessary before building the SQL query.
  # This scope will fail with a stack overflow at around 2000 elements.
  def self.with_names_with_owners(names_with_owners)
    return Repository.none if names_with_owners.empty?

    logins_and_names = names_with_owners.map do |nwo|
      owner, name = nwo.split("/")
      [owner, name]
    end

    logins = logins_and_names.collect(&:first)
    owner_ids_by_login = User.with_logins(logins).pluck(:login, :id).to_h
    owner_ids_by_login.keys.each do |login|
      owner_ids_by_login[User.to_display_login(login)] ||= owner_ids_by_login[login]
    end
    owner_ids_by_login.transform_keys!(&:downcase)

    conditions = logins_and_names.map do |login, name|
      arel_table[:owner_id].eq(owner_ids_by_login[login&.downcase]).and(arel_table[:name].eq(name)).and(arel_table[:active].eq(true))
    end

    joined_conditions = conditions.reduce do |all_conditions, condition|
      all_conditions.or(condition)
    end

    where(joined_conditions)
  end

  # Find a repository by its qualified "owner/repo" name.
  #
  # name_with_owner - The full repository name including a "/", or just the
  #                   owner name when repo is provided.
  # repo            - The repository name.
  #
  # Options
  #   search_redirects - Whether to search for redirected repositories with the
  #                      owner and name. Defaults to false.
  #   preload_internal - Whether to preload the internal repository. Defaults to false.
  #
  # Returns a Repository when a matching repository is found.
  def self.with_name_with_owner(name_with_owner, repo = nil, search_redirects: false, preload_internal: false)
    return nil unless name_with_owner

    start_time = GitHub::Dogstats.monotonic_time
    begin
      owner_login, name =
        if repo
          [name_with_owner, repo]
        else
          name_with_owner.split("/")
        end

      return unless name && GitHub::UTF8.valid_unicode3?(name.to_s)
      return unless owner_login && GitHub::UTF8.valid_unicode3?(owner_login.to_s)

      # A work around for orphaned repos but the owner gets recreated. We can have repositories with the same name
      # and owner login however the owner_ids are different. We want the last repository in this case
      if preload_internal
        repo = Repository
          .eager_load(:internal_repository)
          .where(owner_login: owner_login, name: name, active: true)
          .last
      else
        repo = Repository.where(owner_login: owner_login, name: name, active: true).last
      end

      return repo if repo
      RepositoryRedirect.find_redirected_repository("#{owner_login}/#{name}") if search_redirects
    ensure
      elapsed_ms = GitHub::Dogstats.duration(start_time)
      GitHub.dogstats.distribution("repository.with_name_with_owner", elapsed_ms)
    end
  end

  def self.find_all_public(page = 1)
    rel = active.where(public: true, parent_id: nil).where("pushed_at < NOW()").order("id DESC").page(page)
    rel.total_entries = -1
    rel
  end

  # The stock #read_attribute_for_serialization method is an alias for #send
  # which blows up when it tries to read the value of the watcher_count column
  # (since rename_column makes the #watcher_count method raise).
  # Aliasing it to #[] instead bypasses this problem.
  def read_attribute_for_serialization(attr)
    self[attr]
  end

  scope :public_scope,               -> { where(public: true) }
  scope :private_scope,              -> { where(public: false) }
  scope :private_not_internal_scope, -> { where(public: false).where("repositories.id NOT IN (SELECT repository_id FROM internal_repositories)") }
  scope :internal_scope,             -> { where(public: false).where("repositories.id IN (SELECT repository_id FROM internal_repositories)") }
  scope :active,                     -> { where(active: true) }
  scope :deleted,                    -> { where(active: nil) }
  scope :deleted_before,             -> (date) { deleted.where("updated_at < ?", date) }
  scope :most_starred,               -> { order("#{table_name}.#{stargazer_count_column} DESC") }
  scope :select_except,              -> (*columns) { select(column_names - columns.map(&:to_s)) }

  scope :public_or_internal_scope, -> (viewer) {
    if viewer
      owner_ids = [viewer.id]
      owner_ids.concat(
        FeatureFlag.vexi.enabled_or_raise?(:indirect_orgs_for_repo_templates, viewer) ? viewer.direct_and_indirect_org_ids : viewer.organization_ids # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      ) if viewer.user?

      joins("LEFT OUTER JOIN internal_repositories ON internal_repositories.repository_id = repositories.id")
        .where("repositories.public = ? OR internal_repositories.repository_id IS NOT NULL", true)
        .where(owner_id: owner_ids)
    else
      public_scope
    end
  }

  # This scope works for users who are not part of all orgs within a business
  scope :public_or_internal_scope_by_business, -> (business_id) {
    if business_id
      joins("LEFT JOIN internal_repositories ON internal_repositories.repository_id = repositories.id")
        .where("repositories.public = ? OR (internal_repositories.repository_id IS NOT NULL AND internal_repositories.business_id = ?)", true, business_id)
    else
      public_scope
    end
  }

  scope :public_or_accessible_by, -> (viewer) {
    if viewer
      accessible_repo_ids = Ability.where(
        subject_type: "Repository",
        actor_id: viewer.id,
        actor_type: viewer.ability_type,
        priority: Ability.priorities[:direct],
      ).pluck(:subject_id)

      active.where("repositories.public = ? OR repositories.id IN (?)", true, accessible_repo_ids)
    else
      active.where("repositories.public = ?", true)
    end
  }

  # Repositories that are the roots of their network.
  scope :network_roots, -> {
    where(parent_id: nil).order("repositories.id ASC")
  }
  scope :from_ids, -> (repo_ids) { where(id: repo_ids) }

  # Warning:
  # When sorting by :full_name, this scope executes the relation.
  # Do not apply :full_name sort unless the scope is adequately scoped down.
  # All of a users repos is OK. Repository.all is not OK. :)
  scope :sorted_by, -> (order_str, direction) {
    order_str = :full_name if order_str.blank?
    order_str = order_str.to_sym

    default_dir = :desc
    default_dir = :asc if DEFAULT_ASC_SORT_FIELDS.include?(order_str)

    dir = if direction.blank?
      default_dir
    else
      direction.to_s.downcase == "asc" ? :asc : :desc
    end

    case order_str
    when :created
      order(created_at: dir)
    when :updated
      order(updated_at: dir)
    when :pushed
      order(pushed_at: dir)
    when :full_name
      order(owner_login: dir, name: dir)
    when :name
      order(name: dir)
    when :id
      order(id: dir)
    else
      order(created_at: dir)
    end
  }

  scope :sorted_by_name, -> { order("repositories.name ASC") }
  scope :not_forks, -> { where(parent_id: nil) }
  scope :forks, -> { where("repositories.parent_id IS NOT NULL") }
  scope :forks_owned_by, -> (user) { where("repositories.owner_id = ? AND repositories.parent_id IS NOT NULL", user.id) }
  scope :forks_of, -> (repo) { where(parent_id: repo.id, active: true) }
  scope :organization_member_private_forks, -> (org, members) {
    member_ids = members.is_a?(ActiveRecord::Relation) ? members.pluck(:id) : members.map(&:id)

    private_scope.where(organization_id: org.id, owner_id: member_ids)
  }
  scope :with_owner, -> { active }

  # This scope and comment was taken from ArchivedRepository. The idea is to block users from restoring repos
  # that are part of a fork network. I guess because restoring those repos was especially flaky. Even though
  # the code to restore forked repos exists. Original comment:
  # We do not want to allow users to self-service restoration of repos that were parents or forks of other repos
  # this helps to set scope.
  # Functionally. we are checking for the existence of any Repository attributed to the RepositoryNetwork
  # Since repository networks have many repositories and archived repositories which all share a child parent
  # relationship, if there are ANY Repository's associated with the network, we know that we will not be
  # able to accurately predict the expected location / parentage within a network when a repo is restored.
  scope :network_safe_restoreable, -> { where(parent_id: nil, active: nil).joins("LEFT OUTER JOIN repository_networks rn ON repositories.source_id = rn.id LEFT OUTER JOIN repositories r ON rn.id = r.source_id AND r.active = 1")
    .where("r.id IS NULL")
  }

  def deleted_by_staff?
    !!deleted_by&.site_admin?
  end
  scope :owned_by, lambda { |user_or_id| where(owner_id: user_or_id) }
  scope :not_owned_by, lambda { |user_or_id| where.not(owner_id: user_or_id) }
  scope :owned_by_org, lambda { |org| where(organization_id: org.id) }
  scope :with_language, lambda { |language| where(primary_language_name_id: language.id) }

  scope :ordered_by_array_index, ->(sorted_repo_ids) do
    return if sorted_repo_ids.empty?

    # Convert to integers to make sure the input is good, to guard against SQL
    # injection in case user input is passed to this scope, then convert to
    # a string so we can #join them:
    ids_str = sorted_repo_ids.map(&:to_i).join(", ")

    order(Arel.sql("FIELD(#{table_name}.id, #{ids_str}) ASC"))
  end

  scope :user_owned, -> do
    where("repositories.organization_id IS NULL OR repositories.organization_id != repositories.owner_id")
  end

  scope :org_owned, -> do
    where("repositories.organization_id = repositories.owner_id")
  end

  scope :in_same_network_as, lambda { |repo| where(source_id: repo.source_id) }

  scope :with_issues_enabled,  -> { where(has_issues: true) }
  scope :with_issues_disabled, -> { where(has_issues: false) }

  scope :since, lambda { |time|
    where("repositories.updated_at >= ?", time).order("repositories.updated_at ASC")
  }
  scope :before, lambda { |time|
    where("repositories.updated_at <= ?", time).order("repositories.updated_at DESC")
  }

  scope :recently_updated,
    -> { order("repositories.pushed_at DESC, repositories.created_at DESC") }
  scope :recently_updated_by_id,
    -> { order("repositories.pushed_at DESC, repositories.id DESC") }
  scope :locked_repos, -> { where(locked: true) }
  scope :unlocked_repos, -> { where(locked: false) }

  scope :search, lambda { |query|
    with_prefix(:name, query)
  }

  # Public: Repositories whose organization attribute is set
  scope :with_organization, lambda {
    where.not(organization_id: nil).preload(:organization)
  }

  scope :is_not_disabled, -> { where(disabled_at: nil) }

  scope :filter_spam_and_disabled_for, ->(viewer) {
    relation = filter_spam_for(viewer)

    # Hide DMCA takedown repos from non-site-admins:
    relation = relation.is_not_disabled unless viewer&.site_admin?

    relation
  }

  belongs_to :owner, class_name: "User"
  belongs_to_domain(:owner, foreign_key: :owner_id, ar_relation: true, return_type: T.nilable(::User)) do |owner_ids|
    if FeatureFlag.vexi.enabled?(:issue_comments_api_use_mysql1_replica, default: false)
      ActiveRecord::Base.connected_to(role: :reading) do
        Users.domain.by_ids(owner_ids)
      end
    else
      Users.domain.by_ids(owner_ids)
    end
  end

  belongs_to :parent, class_name: "Repository"
  belongs_to_domain(:parent, foreign_key: :parent_id, return_type: T.nilable(::Repositories::IRepository), ar_relation: true) do |parent_ids|
    Repositories.domain.by_ids(parent_ids, allow_deleted: true)
  end

  belongs_to :network, class_name: "RepositoryNetwork", foreign_key: "source_id" # rubocop:todo Rails/InverseOf
  belongs_to_domain(:network, foreign_key: :source_id, return_type: T.nilable(RepositoryNetwork), ar_relation: true) do |source_ids|
    Repositories.domain.networks.by_ids(source_ids)
  end

  has_one :business, through: :organization

  setup_spammable(:owner)

  # Internal: an abstract collection, for the sub-resources of a Repository available for abilities
  def resources
    Repository::Resources.new(self)
  end

  has_many :branch_renames, class_name: "RepositoryBranchRename"

  # rubocop:todo Rails/InverseOf
  has_many :children,
    -> { where(active: true) },
    class_name: "Repository",
    foreign_key: :parent_id
  # rubocop:enable Rails/InverseOf

  def forks
    children
  end

  # rubocop:todo Rails/InverseOf
  has_many :private_network_repositories,
    -> { where(active: true, public: false) },
    class_name: "Repository",
    foreign_key: :source_id,
    primary_key: :source_id
  # rubocop:enable Rails/InverseOf

  has_many :close_issue_references, foreign_key: "issue_repository_id" # rubocop:todo Rails/InverseOf

  has_many :repository_invitations

  has_one :repository_sequence, dependent: :destroy, autosave: false
  has_one :token_scan_result_sequence, dependent: :destroy, autosave: false
  has_one :repository_vulnerability_alert_sequence, dependent: :destroy, autosave: false

  has_one :disabled_access_reason, as: :flagged_item

  has_one :community_profile, dependent: :destroy

  has_one :repository_import, dependent: :destroy
  has_one :import, through: :repository_import

  has_many :commit_mentions

  has_many :public_keys, extend: PublicKey::CreationExtension

  has_many :languages, dependent: :delete_all, autosave: true

  has_many :tabs

  has_many :commit_comments, class_name: "CommitComment", inverse_of: :repository

  # rubocop:todo Rails/InverseOf
  has_many :projects,
    foreign_key: :owner_id,
    as: :owner
  # rubocop:enable Rails/InverseOf

  has_many :protected_branches

  has_many :rulesets, as: :source, class_name: "RepositoryRuleset"
  has_many :rule_suites, class_name: "RuleEngine::RuleSuite"

  # Queued for destroy in background in Repository::RemovalDependency#purge
  has_many :pushes
  has_many :ref_updates
  has_many :ref_pushes

  has_many :releases

  has_many :release_assets
  has_many :repository_files
  has_many :user_assets

  has_many :packages, class_name: "Registry::Package"
  has_many :package_files, through: :packages

  has_many :redirects,  class_name: "RepositoryRedirect"

  has_many :commit_contributions

  # Join records to clones of this repository where this repository is a template
  has_many :repository_clones, foreign_key: "template_repository_id" # rubocop:todo Rails/InverseOf

  # The join record for this repository to the template repository it was cloned from, if any
  # rubocop:todo Rails/InverseOf
  has_one :template_repository_clone, foreign_key: "clone_repository_id",
    class_name: "RepositoryClone", dependent: :destroy
  # rubocop:enable Rails/InverseOf

  has_many :labels

  has_many :repository_vulnerability_alerts, extend: RepositoryVulnerabilityAlert::ForManifestAndPackage,
    inverse_of: :repository
  has_many :open_vulnerability_alerts, -> { T.bind(self, T.untyped); open }, class_name: "RepositoryVulnerabilityAlert"

  has_many :check_suites

  has_one :actions_cache_usage, dependent: :destroy

  has_many :workflows, class_name: "Actions::Workflow"

  has_many :workflow_runs, -> { order(id: :desc) }, class_name: "Actions::WorkflowRun"

  has_many :project_repository_links, dependent: :destroy

  has_many :environments

  has_one :protected_branch_for_default_branch, ->(repo) {
    where(name: repo.default_branch)
  }, class_name: "ProtectedBranch"

  validates_presence_of :name, :owner_id, on: :create
  validates :name, unicode3: true

  before_validation lambda { T.bind(self, Repository); self[:description] = nil }, if: lambda { T.bind(self, Repository); will_save_change_to_description? && description.blank? }
  validates :description,
    format: { without: /[[:cntrl:]]/, message: "control characters are not allowed" },
    allow_nil: true,
    if: :will_save_change_to_description?
  validates :description,
    unicode: true,
    length: { maximum: DESCRIPTION_CHAR_LIMIT, message: "cannot be more than #{DESCRIPTION_CHAR_LIMIT} characters" },
   if: :validate_description_length

  before_validation lambda { T.bind(self, Repository); self.validate_description_length = true }, on: :create

  force_utf8_encoding :description

  has_many :transfers, class_name: "RepositoryTransfer"

  has_many :user_roles, as: :target, dependent: :destroy
  has_many :roles, as: :owner, dependent: :destroy

  sig { override.returns(GH::Domain::Base) }
  def domain
    Repositories.domain
  end

  sig { override.returns(GH::Domain::Cache::Cachable) }
  def duplicate
    internal_attrs = internal_repository&.attributes if association(:internal_repository).loaded?

    coder = Coders::RepositoryCoder.new(raw_data.to_h)
    attrs = self.attributes
    attrs.delete("raw_data")
    repository = Repository.instantiate(attrs)
    repository.raw_data = coder

    if internal_attrs.present?
      internal_repository = InternalRepository.instantiate(internal_attrs)
      GitHub::PrefillAssociations.prefill_associations([repository], [:internal_repository], available_records: [internal_repository])
    end

    repository
  end

  def entity
    self
  end

  def change_owner_of!(project:, creator:, old_owner:)
    # Clear out all abilities, since repo projects just inherit their repo's
    # abilities.
    Ability.clear(project)

    # Remove any project links that exist
    project.unlink_repositories
  end

  # Public: Create a new commit in this repository.
  #
  # Use Ref#create_commit or Ref#append_commit instead. The is only meant for internal usages.
  #
  # parent_oid - String containing the OID of the new commit's
  #              parent. If there is no parent,
  #              nil and "" both work, but nil is preferred.
  #              Strings that are not valid OIDs, or parents
  #              that not members of the repository, are
  #              prohibited.
  # message    - String message. Required.
  # author     - An instance of User. This is typically the
  #              currently logged-in user.
  # files      - A dictionary (typically a Hash) representing
  #              the collected changes to be made for this commit.
  #              Each key->value mapping represents one of:
  #              (a) A create or update, represented as
  #              String path => String new contents, or (b)
  #              A deletion, represented as String path => nil,
  #              or (c) A moved file, represented as String
  #              new path => {:from => String old path,
  #              :contents => String new or same contents}
  # sign       - Boolean of whether to try to sign the commit.
  # skip_rule_evaluation - (Optional) Indicates whether rule evaluation should be skipped. This is only
  #                        necessary for creating temporary commits and should otherwise be avoided.

  #
  # Returns: An instance of Commit, or false if Commit#create
  #          (which it ultimately calls) raises certain exceptions.
  #          For example, if the parent_oid is a valid oid string but
  #          does not represent a parent commit in this respoistory,
  #          this method will return false.
  #
  # Raises: Does not directly raise any exceptions, but will pass through
  # some exceptions. For example, if parent_oid is not a valid oid string,
  # an exception will bubble up to the caller.
  def create_commit(parent_oid, message:, author: nil, files:, author_email: nil, committer: nil, sign: false, skip_rule_evaluation: false)
    metadata = { message: message, author: author, author_email: author_email, committer: committer }
    metadata[:authored_date] = Time.zone.now.iso8601

    self.commits.create(metadata, parent_oid.presence, sign:, skip_rule_evaluation:,) do |commit_files|
      files.each do |filename, contents|
        if contents.is_a?(Hash)
          commit_files.move(contents[:from].b, filename.b, contents[:contents].b)
        elsif contents
          commit_files.add(filename.b, contents.b)
        else
          commit_files.remove(filename.b)
        end
      end
    end
  rescue Git::Ref::ComparisonMismatch, GitRPC::Failure, ArgumentError
    false
  end

  def network_repositories
    T.must(network).repositories
  end

  def owner_login
    super || owner&.login
  end

  def owner_display_login
    User.to_display_login(owner_login)
  end

  # Public: Determine which icon to show for the repository.
  #
  # Returns a String.
  def repo_type_icon
    @repo_type_icon ||= begin
      if fork?
        "repo-forked"
      elsif private?
        "lock"
      else
        mirror? ? "mirror" : "repo"
      end
    end
  end

  def mirror?
    # Don't query for the mirror unless it's public
    public? && !!mirror
  end

  has_many :issues

  has_many :milestones, inverse_of: :repository

  has_many :pull_requests
  has_many :pull_request_review_comments
  has_many :pull_request_review_threads

  # rubocop:todo Rails/InverseOf
  has_many :pull_requests_as_head,
    class_name: "PullRequest",
    foreign_key: :head_repository_id
  # rubocop:enable Rails/InverseOf

  has_many :deployments,
    -> { order("deployments.id desc") },
    inverse_of: :repository

  has_one :page, dependent: :destroy, inverse_of: :repository

  has_one :mirror, dependent: :destroy

  has_one :repository_license, dependent: :destroy
  has_many :repository_licenses, dependent: :destroy
  has_one :internal_repository, dependent: :destroy

  # rubocop:todo Rails/InverseOf
  belongs_to :primary_language, class_name: "LanguageName", foreign_key: :primary_language_name_id
  # rubocop:enable Rails/InverseOf

  validates_length_of       :name, in: 1..NAME_MAX_LENGTH, too_long: "cannot be more than #{NAME_MAX_LENGTH} characters"
  validates_exclusion_of    :name, in: %w( . .. followers following repositories )
  validate :name_is_not_a_wiki_repo
  validates_numericality_of :owner_id
  validates :homepage, length: { maximum: 255 }, unicode3: true, allow_blank: true

  before_validation :normalize_name
  before_validation :set_organization, on: :create
  before_validation :normalize_active

  validate :ensure_owner_is_not_trade_controls_restricted, on: :create
  validate :ensure_creator_is_not_trade_controls_restricted, on: :create
  validate :ensure_uniqueness_of_name
  validate :ensure_name_not_retired
  validate :ensure_uniqueness_of_fork_in_network, on: :create
  validate :ensure_gitignore_template_exists, on: :create
  validate :ensure_license_template_exists, on: :create
  validate :ensure_owner_has_enough_repo_quota, on: :create
  validate :ensure_projects_can_be_enabled, on: :create
  validate :ensure_owner_is_a_user_or_organization

  after_create :create_sequence # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  after_create :initialize_repository_network, # rubocop:todo GitHub/AvoidActiveRecordCallbacks
               :setup_git_repository_if_exists,
               :clear_contributions_cache

  after_create :calculate_network_counts!, if: :active? # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :synchronize_search_index, on: [:update, :destroy], unless: -> { T.bind(self, Repository); skip_search_index_sync? }
  # rubocop:enable GitHub/AvoidActiveRecordCallbacks

  # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :synchronize_topics_search_index, on: :update, if: :saved_change_to_public?
  # rubocop:enable GitHub/AvoidActiveRecordCallbacks

  after_destroy :synchronize_search_index, # rubocop:todo GitHub/AvoidActiveRecordCallbacks
                :clear_contributions_cache

  before_save :set_made_public_at, if: :will_save_change_to_public? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  before_save :set_owner_login, if: :owner_id_changed? # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  before_create :set_made_public_at # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  before_create :raise_on_creation_outside_of_orchestration, unless: :expected_creation? # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  after_save :delist_actions, if: :private_or_deleted? # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  after_destroy :remove_vulnerability_manager_abilities # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  if !Rails.env.test? # rubocop:todo GitHub/DoNotBranchOnRailsEnv
    after_commit :enqueue_check_for_spam, # rubocop:todo GitHub/AvoidActiveRecordCallbacks
                 on: :create
  else
    cattr_accessor :checking_for_spam
    after_commit :enqueue_check_for_spam, # rubocop:todo GitHub/AvoidActiveRecordCallbacks
                 on: :create,
                 if: :checking_for_spam
  end

  after_destroy :calculate_network_counts!, # rubocop:todo GitHub/AvoidActiveRecordCallbacks
                :destroy_repository_network

  after_commit :delete_all_newsies_data, on: :destroy # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  def user
    owner
  end

  def user=(value)
    self.owner = value
  end

  attribute :owner_login, User::UserLoginType.new

  ##
  # Caching!
  after_commit :synchronize_issues_search_index # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  after_validation :record_name_change
  after_save :unfeature_from_sponsors_profile, if: :made_private? # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :update_repository_projects_setting, if: :repository_projects_setting_changed?
  # rubocop:enable GitHub/AvoidActiveRecordCallbacks
  # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :update_repository_memex_projects_setting, if: :repository_memex_projects_setting_changed?
  # rubocop:enable GitHub/AvoidActiveRecordCallbacks

  after_commit :instrument_update, on: :update # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  after_commit :track_creation_outside_of_orchestration, # rubocop:todo GitHub/AvoidActiveRecordCallbacks
               on: :create,
               unless: :expected_creation?

  # Destroying the user-page can change the URL for all project-pages, so we
  # rebuild everything.
  # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_destroy :queue_propagate_https_redirect, if: :is_cname_user_pages_repo?
  # rubocop:enable GitHub/AvoidActiveRecordCallbacks

  serialize_with_coder :raw_data, Coders::RepositoryCoder

  alias_method :auto_init?, :auto_init
  alias_method :expected_creation?, :expected_creation
  alias_method :skip_after_create_callbacks?, :skip_after_create_callbacks

  def to_s
    name
  end

  def to_param
    name
  end

  # As a part of https://github.com/github/repos/issues/4863, deleted_at was moved from raw_data to a true
  # column on the repositories table. No new values should be written, but if a repo is being restored,
  # we want to ensure raw_data.deleted_at is nil too.
  def deleted_at=(deleted_at)
    super(deleted_at)
    self.raw_data.deleted_at = nil if deleted_at.nil?
  end

  def deleted_at
    db_deleted_at = super
    if db_deleted_at
      GitHub.dogstats.increment("repository.deleted_at", tags: ["source:db"])
      db_deleted_at
    else
      GitHub.dogstats.increment("repository.deleted_at", tags: ["source:raw_data"])
      self.raw_data.deleted_at
    end
  end

  def deleted_at?
    super || self.raw_data.deleted_at?
  end

  def normalize_active
    # Don't allow active == false. Only true or nil.
    # It can cause SQL duplicate-key exceptions if you create + delete multiple repos with the same name.
    self.active = nil if self.active == false
  end

  def deleted?
    !active?
  end

  def soft_creating?
    !active? && !deleted_at.present?
  end

  def unpersisted?
    new_record? || destroyed? || (deleted? && !soft_creating?)
  end

  # Public: Is the given branch name or commit SHA one that exists in this repository?
  #
  # maybe_branch - String branch name or commit SHA or ref
  #
  # Returns a Boolean.
  def valid_branch?(maybe_branch)
    extractor = GitHub::RefShaPathExtractor.new(self)
    branch, _ = extractor.call(maybe_branch)
    !branch.nil?
  end

  # User that created this repository.
  # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
  def created_by
    @created_by ||= created_by_user_id && User.find_by(id: created_by_user_id)
  end
  # rubocop:enable GitHub/BooleanMemoizationWithOrOperator
  alias_method :created_by_user, :created_by

  # User that deleted this repository. This is stored as a serialized
  # attribute when the record is marked as deleted.
  # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
  def deleted_by
    @deleted_by ||= deleted_by_user_id && User.find_by(id: deleted_by_user_id)
  end
  # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

  # After validation callback that tracks if the name was changed so we know
  # whether to crack the owner cache once the record is saved. We don't update
  # the owner cache here because it runs on validation.
  def record_name_change
    @name_changed_during_validation = true if will_save_change_to_name?
  end

  # Override #reload to also reset various memoized attributes.
  def reset_memoized_attributes
    super
    reset_git_cache
    @teams_for = nil
    @network_owner = nil
    @default_branch = nil
    @owner_blocking_by_user_id = nil
    remove_instance_variable(:@global_health_files_repo) if defined?(@global_health_files_repo)
    remove_instance_variable(:@async_root) if defined? @async_root
    remove_instance_variable(:@async_network_owner) if defined? @async_network_owner
    remove_instance_variable(:@async_ip_restricted_private_fork) if defined? @async_ip_restricted_private_fork
    reset_archived
  end

  ##
  # Misc

  def <=>(other)
    return nil unless other.is_a?(Repository)

    name <=> other.name
  end

  # NOTE: Even though async_name_with_owner doesn't need anything async anymore,
  # other parts of our code will raise errors in tests (and might n+1 in prod
  # more often) if we don't load it here. We're essentially counting on the
  # user to request `name` so that we can use this method to preload `async_owner`
  # for other methods down the line. That's definitely not ideal! In order to
  # remove `async_owner` here, we'd need to track down every place we're
  # calling `owner` in a GraphQL-dependent method.
  def async_name_with_owner
    async_owner.then do
      name_with_owner
    end
  end

  # Based on the comment above for `async_name_with_owner`, we also load `async_owner` here
  # so that we can use this method in place of `async_name_with_owner`
  # for the :name_with_owner field in app/platform/interfaces/repository_info.rb
  def async_name_with_owner_for_api
    async_owner.then do
      name_with_owner_for_api
    end
  end

  def name_with_owner(separator = "/")
    "#{owner_login}#{separator}#{self}"
  end

  def name_with_display_owner
    "#{owner_display_login}/#{self}"
  end

  # This method is used to return the correct name_with_owner for API serialization for Proxima.
  # Internal calls to the API return the unique name_with_owner,
  # non-internal calls return name_with_display_owner.
  #
  # For non-proxima environments always returns name_with_display_owner which is the same value as name_with_owner.
  #
  # Do not use this method unless specifically indicated.
  # Other options to use: `.name_with_owner`, `.name_with_display_owner`
  def name_with_owner_for_api(use: :default)
    return name_with_display_owner unless GitHub.multi_tenant_enterprise?

    case use
    when :unique
      name_with_owner
    when :display
      name_with_display_owner
    else
      # TODO: Update to throw on unknown `use` values.
      # https://github.com/github/github/pull/261256/files/7403b0ac9ceeab75ee0e5b1393575f18510a8c57#r1123242822
      GitHub.dogstats.increment("repository.name_with_owner_for_api",  tags: ["use:#{use}"])

      if !GitHub.proxima_internal_api_unique_logins_required?
        name_with_display_owner
      else
        name_with_owner
      end
    end
  end

  alias full_name name_with_owner
  alias nwo name_with_owner
  alias name_with_owner_for_archive name_with_display_owner

  def token_scope
    if GitHub.multi_tenant_enterprise?
      id
    else
      name_with_owner
    end
  end

  def readonly_name_with_owner(separator = "/")
    ActiveRecord::Base.connected_to(role: :reading) { name_with_owner(separator) }
  end

  def readonly_name_with_owner_for_api(use: :default)
    ActiveRecord::Base.connected_to(role: :reading) { name_with_owner_for_api(use: use) }
  end

  def readonly_name_with_display_owner
    ActiveRecord::Base.connected_to(role: :reading) { name_with_display_owner }
  end

  def async_owner_default_new_repo_branch
    default_branch = T.let(nil, T.untyped)

    async_owner.then do |owner|
      if owner
        default_branch = owner.custom_default_new_repo_branch
        next default_branch if default_branch
      end

      async_organization.then do |org|
        if org
          org.async_business.then do |business|
            if business
              default_branch = business.custom_default_new_repo_branch
              next default_branch if default_branch
            end

            Configurable::DefaultNewRepoBranch.recommended_name
          end
        else
          if GitHub.single_business_environment?
            default_branch = GitHub.global_business&.custom_default_new_repo_branch
            next default_branch if default_branch
          end

          Configurable::DefaultNewRepoBranch.recommended_name
        end
      end
    end
  end

  # Public: Get the default branch name that the owner of this repository would prefer be
  # used for new repositories.
  #
  # Returns String
  def owner_default_new_repo_branch
    async_owner_default_new_repo_branch.sync
  end

  class << self
    alias_method :nwo, :with_name_with_owner
  end

  # The user who performed the action as set in the GitHub request context. If the context doesn't
  # contain an actor, fallback to the ghost user.
  def actor
    @actor ||= (User.find_by_login(GitHub.context[:actor]) || User.find_by(id: GitHub.context[:actor_id]) || User.ghost)
  end

  def async_network_owner
    return @async_network_owner if defined?(@async_network_owner)

    @async_network_owner = if association(:network).loaded? && network&.root_id == id
      async_owner
    else
      Platform::Loaders::NetworkOwner.load(source_id)
    end
  end

  def network_owner
    @network_owner ||= async_network_owner.sync
  end

  def deployments_dashboard_environment_channel(environment)
    GitHub::WebSocket::Channels.deployments_dashboard_environment(self, environment)
  end

  def visible?
    active? && !spammy?
  end

  # Compare base and head refs with a new GitHub::Comparison object.
  #
  # base  - The extended ref identifying the commit to act as the
  #         base of the comparison. Can be nil.
  # head  - The extended ref identifying the commit to act as the
  #         head of the comparison. Can be nil.
  # limit (optional) - Numeric limit for the total number of commits to retrieve.
  # pull  (optional) - PullRequest with which this comparison is associated.
  #                    Specifying this means its head and base repository will be used.
  # .                  Recommendation: deprecate this argument. It's only used from PullRequest#comparison.
  # head_repo (optional) - Repository that the head ref belongs to.
  #                        Should not be used in conjunction with 'pull'.
  #
  # Returns GitHub::Comparison
  def comparison(base, head, limit = 1000, pull = nil, head_repo: nil)
    GitHub::Comparison.deprecated_build(self, base, head, limit: limit, pull: pull, head_repo: head_repo)
  end

  # Public: Render the repository's Markdown description as HTML.
  def description_html
    GitHub::Goomba::DescriptionPipeline.to_html(description)
  end

  # Public: Render the repository's Markdown description as HTML without any
  # links, gracefully truncated.
  def short_description_html(limit: 200)
    formatted = GitHub::Goomba::SimpleDescriptionPipeline.to_html(description)
    HTMLTruncator.new(formatted, limit).to_html(wrap: false)
  end

  # Public: Asynchronous implementation of #short_description_html.
  def async_short_description_html(limit: 200)
    GitHub::Goomba::SimpleDescriptionPipeline.async_to_html(description).then do |formatted|
      HTMLTruncator.new(formatted, limit).to_html(wrap: false)
    end
  end

  ##
  # Access

  def repository
    self
  end

  # Public: If the repository is private and the network root owner has a billing
  # issue(thus is disabled), we will disable the repository.
  #
  # `has_any_trade_restrictions?` delegates to the user model, where we
  # check for ofac sanctioning. This is broken out from the other methods
  # as it doesn't matter what plan the user is on, nor is the user "disabled"
  # in the same sense as billing issues.
  #
  # Returns Boolean
  def disabled?(viewer: nil)
    async_disabled?(viewer: viewer).sync
  end

  def async_disabled?(viewer: nil)
    return Promise.resolve(false) unless private?
    promises = T.let([async_internal_repository, async_owner], T::Array[T.untyped])
    if FeatureFlag.vexi.enabled_or_raise?(:use_billing_locked_rather_than_disabled) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      promises.push(async_plan_customer)
    end
    Promise.all(promises).then do
      Promise.all([owner&.async_trade_controls_restriction, viewer&.async_trade_controls_restriction]).then do
        non_repo_plan_disabled_user? ||
        trade_restricted_by_owner? ||
        !!viewer&.has_any_trade_restrictions?
      end
    end
  end

  def issue_templates(viewer = nil, arguments = {})
    @issue_templates ||= {}
    filter = arguments[:filename]
    is_form = arguments[:is_form] || false
    key = "#{viewer&.id}-#{is_form ? 'form' : 'template'}-#{filter || 'all'}"
    @issue_templates[key] ||= IssueTemplates.new(self, viewer, filter)
  end

  # Public: Issue templates for this repository, either from the local repository
  # or a global health files repository for an organization.
  #
  # Returns IssueTemplates or nil.
  def preferred_issue_templates(viewer = nil, arguments = {})
    @preferred_issue_templates ||= async_preferred_issue_templates(viewer, arguments).sync
  end

  # Public: Issue templates for this repository, either from the local repository
  # or a global health files repository for an organization.
  #
  # Returns Promise<IssueTemplates|nil>.
  def async_preferred_issue_templates(viewer = nil, arguments = {})
    repo_issue_templates = issue_templates(viewer, arguments)
    if repo_issue_templates.any? ||
       global_health_files_repository? ||
       repo_issue_templates.issue_template_config.configured?

      Promise.resolve(repo_issue_templates)
    else
      async_owner.then do |_owner|
        async_global_health_files_repo.then do |global_repository|
          next repo_issue_templates unless global_repository.present?

          global_templates = global_repository.issue_templates(viewer, arguments)
          GitHub::PrefillAssociations.prefill_associations(global_templates.repository, :owner)
          # filter out templates based on repo settings
          global_templates.templates.keep_if { |template| template.supported?(self) }

          if global_templates.any? || global_templates.issue_template_config.configured?
            global_templates
          else
            repo_issue_templates
          end
        end
      end
    end
  end

  def template_tree_path
    File.join("/", name_with_display_owner, "tree", default_branch, IssueTemplates.template_directory)
  end

  def can_create_issue_templates?
    # We're trying to prevent cases where either .github or .github/ISSUE_TEMPLATE is a file
    valid_file_path?(".github/ISSUE_TEMPLATE/bug.md")
  end

  ##
  # Paths, URLs, Routing
  def normalize_name
    return unless active? || soft_creating?

    throw(:abort) unless owner

    self.name = EntityName.normalize(self[:name])
    true
  end

  # Internal: does this repo have an unique name?  Returns true if name
  # is unique, false otherwise.  Called via validation.
  def ensure_uniqueness_of_name
    return true if deleted? && !soft_creating?
    return true unless will_save_change_to_name?
    return false unless owner

    existing_repo = Repository.where(
      name: name,
      owner_id: T.must(owner).id,
      active: true,
    ).first

    if existing_repo.nil?
      true
    elsif !new_record? && existing_repo.id == id
      true
    else
      errors.add("name", :already_exists, message: "already exists on this account")
      false
    end
  end

  # Internal: Validates that this repository's name is not reserved, or if it is,
  #           that it is claimable by the owner.
  #
  # Returns a Boolean.
  def ensure_name_not_retired
    return true if deleted? && !soft_creating?
    return true unless will_save_change_to_name?
    return false unless owner.present?

    retired_namespace = RetiredNamespace.for(
      owner: T.must(owner).login,
      name: name,
    )

    return true unless retired_namespace.present?
    return true if retired_namespace.claimable_by?(owner)

    errors.add("name", "has been retired and cannot be reused")
    false
  end

  # Absolute permalink URL for this repository.
  #
  # include_host - Turn off the `GitHub.url` host in the url. (default true)
  #                repository.permalink(include_host: false) => `/github/github`
  #
  def permalink(include_host: true)
    if include_host
      "#{GitHub.url}/#{name_with_display_owner}"
    else
      "/#{name_with_display_owner}"
    end
  end

  # A URL for this repository constructed with database IDs rather than mutable
  # strings.
  #
  # For example, instead of https://github.com/github/github/, this returns
  # https://github.com/123/456.
  #
  # Since we have redirects in place to rewrite these to the more usual
  # name_with_owner URLs, this is sometimes useful for internal applications
  # that need a URL that is stable in the face of org or repo renames.
  #
  # include_host - Whether or not to prefix the URL path with the `GitHub.url` host.
  #
  # Returns the URL as a String.
  def id_based_url(include_host: true)
    if include_host
      # For dynamic environments like review-lab (e.g. "login.review-lab.github.com"), use
      # `GitHub.host_domain` so that we get just "github.com" as the domain (and so we avoid
      # generating an impermanent link). Otherwise, use the full host name (including sub-domains)
      # so that this behaves correctly for GHES instances hosted at different subdomains (which
      # might have different sets of respositories).
      domain = GitHub.dynamic_lab? ? GitHub.host_domain : GitHub.host_name

      "#{GitHub.scheme}://#{domain}/#{owner_id}/#{id}"
    else
      "/#{owner_id}/#{id}"
    end
  end

  def path_uri
    @path_uri ||= URI_TEMPLATE.expand(owner: owner_display_login, name: name)
  end

  def async_commits_path_uri(author: nil, commitish: nil)
    async_owner.then do |_owner|
      template_values = {
        owner: owner_display_login,
        name: name
      }
      template_values[:commitish] = "/#{commitish}" if commitish
      uri = COMMITS_URI_TEMPLATE.expand(template_values)
      uri.query_values = { author: author } if author
      uri
    end
  end

  def path
    @path || (owner && "#{T.must(owner).path}/#{self}.git")
  end

  def path=(path)
    @path = path
  end

  def short_git_path
    if GitHub.multi_tenant_enterprise?
      name_with_display_owner
    else
      name_with_owner
    end
  end

  # Rails's Object#present? delegates to blank?, which in turn delegates to
  # empty?. This method is overridden above, and can return true on an existing
  # repository, which makes Repository#present? return false.
  #
  # To avoid Repository#present? (and any other methods that delegate to blank?)
  # from unexpectedly returning false, we override blank? here.
  #
  # Returns a boolean.
  def blank?
    false
  end

  def availability
    @availability ||= Availability.new(self)
  end

  def availability_status
    availability.state
  end

  # Update the pushed_at_usec with the usec portion of the pushed_at timestamp.
  #
  # This works around mysql only storing second-resolution for timestamps.
  #
  # Called in before_save
  def update_pushed_at_usec(time)
    if time && (usec = time.usec) != 0
      self.pushed_at_usec = usec
    end
    true
  end

  # Combine pushed_at and pushed_at_usec to get a timestamp with usec set.
  #
  # Returns a Time object.
  def pushed_at
    if time = read_attribute(:pushed_at)
      time.utc.change(usec: pushed_at_usec || 0)
    end
  end

  def pushed_at=(time)
    update_pushed_at_usec(time)
    super
  end

  # Updates the pushed_at and pushed_at_usec timestamps without
  # running model callbacks.
  def update_pushed_at(time = Time.now)
    self.pushed_at = time

    self.class.where(id: id).update_all(pushed_at: pushed_at, pushed_at_usec: pushed_at_usec)
  end

  # Write template README and gitignore files and license files if those options were selected
  # when the repository was created.
  def initialize_git_repository_templates
    TemplateInitializer.new(self).perform
  rescue Git::Ref::HookFailed => e
    self.template_hook_failure = e.message.to_s
  rescue Git::Ref::ProtectedBranchUpdateError => e
    self.template_hook_failure = e.message.to_s
  rescue Git::Ref::RepositoryRuleViolationError => e
    self.template_hook_failure = e.detailed_message.to_s
  end

  # Generates the initial contents of the README.md file using the repository
  # name and description.
  #
  # Returns a string with the contents of the new README file.
  def generate_readme
    if user_configuration_repository?
      configuration_repository_readme_template
    else
      template = if description.present?
        "# #{name}\n#{description}\n"
      else
        "# #{name}"
      end
      escape_generated_readme_html(template)
    end
  end

  # After create filter used when the repository already exists on disk. Just
  # updates the pushed_at timestamp to ensure caches are cracked.
  def setup_git_repository_if_exists
    if exists_on_disk?
      update_attribute :pushed_at, Time.now
    end
  end

  # Verify that the repo.git/hooks symlink is in place and symlinked
  # to the appropriate hooks directory. This is used primarily in
  # development environments since the RAILS_ROOT is variable.
  def correct_hooks_symlink
    return if %w[development test].include?(Rails.env) && name == "github"
    return unless GitHub.enterprise?

    rpc.symlink_hooks_directory
  end

  # Manage access to this repository and its network. Disabling a repository
  # cuts of access to all protocols: git, ssh, web and api.
  #
  # Examples:
  #
  #   repository.access.disable("size", staff_user)
  #   repository.access.dmca_takedown(staff_user, "https://....")
  #
  # See RepositoryGitRepositoryAccess for details.
  def access
    @access ||= RepositoryGitRepositoryAccess.new(self)
  end

  def country_blocks
    access.country_blocks
  end

  # Internal: Verify the chosen template exists, otherwise set to nil.
  def ensure_gitignore_template_exists
    if gitignore_template.present? && !Gitignore.template_exists?(gitignore_template)
      errors.add(:gitignore_template, "is an unknown gitignore template.")
      false
    end

    true
  end

  # Internal: Verify the chosen license exists, otherwise set to nil.
  def ensure_license_template_exists
    if license_template.present? && !License[license_template]
      errors.add(:license_template, "is an unknown license template.")
      false
    end

    true
  end

  def has_master_branch?
    heads.include?("master")
  end

  # The id of the RepositoryNetwork this repository belongs to.
  #
  # For historical reasons, the network_id column is named "source_id" in the
  # database. This is a simple alias but should be used in favor of source_id
  # because it's a better description.
  #
  # Returns the integer network id.
  def network_id
    source_id
  end

  def network_id=(value)
    self.source_id = value
  end

  def name_is_not_a_wiki_repo
    return unless active? || soft_creating?
    if T.must(name).end_with?(".wiki")
      errors.add(:name, "cannot end in .wiki")
    end
  end

  def report_error(exception, options = {})
    Failbot.report(exception, { "gh.repo.id": id.to_s }.update(options))
  end

  # Public: Check whether repository fulfills dormancy guidelines
  # (Not created or pushed to for at least 6 months)
  #
  # NOTE: Also update `Organization#exempt_from_dormancy?` if changing this logic.
  #
  # Returns Boolean
  def dormant?(threshold = GitHub.dormancy_threshold)
    dormancy_time = Time.now - threshold
    (pushed_at.nil? || pushed_at < dormancy_time) &&
      (created_at.nil? || T.must(created_at) < dormancy_time)
  end

  # Public: Do we allow public push to this repo?
  #
  # Returns true if the repository allows pushes from anyone with an account,
  # false otherwise.
  def public_push?
    GitHub.public_push_enabled? && public? && !!public_push
  end

  def read_only?
    T.must(network).read_only?
  end

  def has_dockerfile?
    tree_entry(ref_to_sha(default_branch), "Dockerfile").present?
  rescue GitRPC::Error
    # GitRPC::InvalidFullOid will happen if default_branch doesn't exist.
    # GitRPC::NoSuchPath will happen if Dockerfile doesn't exist.
    false
  end

  # Public: destroy all protected branches for this repo
  #
  # Returns array
  def destroy_protected_branches
    protected_branches.destroy_all
  end

  # Public: Is this repository the global health files repository for an organization?
  #
  # Returns a Boolean.
  def global_health_files_repository?
    return false unless public?
    return false unless active?

    name == GLOBAL_HEALTH_FILES_NAME
  end

  # Private: Pages operations like `gh_pages_url` require the Page to exist
  # This method returns the page, if it exists, or initializes a new page
  # for calculating URLs prior to the page existing (e.g., previews)
  def page_for_url
    page || Page.new(repository: self)
  end

  # Internal: Ensure this repo affects the owner's contributions.
  def clear_contributions_cache
    preload_user
    return if user.nil?
    context = deleted? ? "destroy_repository" : "create_repository"
    Contribution.clear_caches_for_user(user, context: context)
  rescue GitHub::KV::UnavailableError
    # no-op
  end

  def preload_user
    # It's possible we're hitting the destroy callback from a PurgeRepositoryOrchestration where the owner is already
    # gone so we were unable to infer the tenant. If that's the case then let's just preload the user association
    # without tenant scoping to avoid a NullTenantQueryScopingError
    if GitHub.multi_tenant_enterprise? && GitHub::CurrentTenant.get.blank?
      GitHub::CurrentTenant.unscope { user }
    else
      user
    end
  end

  # Public: Has the specified user contributed to this repository?
  #
  # user - The User to check for contributions.
  #
  # Returns Promise<bool>
  def async_contributor?(user)
    return Promise.resolve(false) unless user

    Platform::Loaders::CommitContributorCheck.load(self, user.id)
  end

  # Public: Returns true unless locked_on_migration? or archived? are true.
  #
  # Returns a boolean
  def writable?
    async_writable?.sync
  end

  def async_writable?
    if locked || locked_on_migration? || access.disabled?
      Promise.resolve(false)
    else
      async_archived?.then(&:!)
    end
  end

  # Sign a commit body.
  #
  # If a commit_time is provided, request gpgverify sign the commit with this timestamp for determistic
  # resigning of an identical commit.
  #
  # Returns a String signature or nil.
  def sign_commit(commit_body, commit_time: nil)
    if GitHub.web_commit_signing_enabled?
      GitHub.gpg.sign(commit_body, time: commit_time)
    else
      nil
    end
  rescue GpgVerify::Unavailable
    nil
  rescue GpgVerify::Error => e
    Failbot.report(e, app: GitSigning::FAILBOT_APP)
    nil
  end

  # Returns a temporary clone url with signed auth token embedded
  #
  # user    - User instance to use for token generation
  # expires - How long the temporary token lasts before expiring
  # action  - repo action token will be valid for (read or write)
  #
  # Returns signed auth token string
  def temp_clone_token(user, expires: nil)
    return if user.nil?
    return "" unless private?

    expires ||= 5.minutes.from_now

    signed_auth_token_options = {
      scope: temp_clone_token_scope,
      expires: expires,
    }
    user.signed_auth_token(signed_auth_token_options)
  end

  # Public: Determines whether this repository runs its GitRPC commands with
  # trace2 instrumentation.
  #
  # Returns: Boolean
  def trace2_enabled?
    !GitHub.enterprise?
  end

  # Public: Determines if the owner has a "true_match" screening status
  #
  # Does the owner of this repository have a "true_match" SDN (Specially Designated Nationals) screening status
  #
  # Returns: Boolean
  def owner_trade_screening_delete_restricted?
    T.must(owner).trade_screening_record.true_match?
  end

  # Public: Determines whether if either the owner or network owner is trade restricted
  #
  # Is the owner, or the network owner trade restricted?  Network owner is the root
  # owner of a fork repository.
  #
  # Returns: Boolean
  def trade_restricted_by_owner?
    if network_id && network_owner
      return true unless network_owner.restriction_tier_allows_feature?(type: :repository)
    end

    if owner
      !T.must(owner).restriction_tier_allows_feature?(type: :repository)
    end
  end

  # Public: Determines if functionality is limited in this repo due to trade
  # controls restrictions
  #
  # Is this a private repo and the owner or network owner restricted, or
  # is it public and owned by a fully restricted organization
  #
  # Returns: Boolean
  def trade_restricted?
    (private? && trade_restricted_by_owner?) || trade_controls_read_only?
  end

  # Public: Determine which notification to show to API users.
  #
  # Returns: String
  def trade_restriction_api_error_message(viewer = nil)
    repo_owner = T.must(owner)
    if repo_owner.is_a?(Organization) && repo_owner.has_any_trade_restrictions?
      if repo_owner.adminable_by?(viewer)
        ::TradeControls::Notices.notice_as_plaintext(:org_restricted_repo_for_admins)
      elsif repo_owner.direct_or_team_member?(viewer)
        ::TradeControls::Notices.notice_as_plaintext(:org_restricted_repo_for_collaborators)
      else
        ::TradeControls::Notices.notice_as_plaintext(:org_restricted)
      end
    elsif viewer == repo_owner || repo_owner.is_a?(Organization)
      ::TradeControls::Notices.notice_as_plaintext(:user_account_restricted)
    else
      ::TradeControls::Notices.notice_as_plaintext(:private_repo_member_restriction, repo_owner.login)
    end
  end

  def target_for_conditional_access
    return owner if owner
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def async_target_for_conditional_access
    async_owner.then do |owner|
      if owner
        owner
      else
        :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      end
    end
  end

  def default_branch_for_display
    utf8(default_branch.dup)
  end

  def feature_enabled_for_repo_or_owner?(feature_name)
    self.owner&.feature_flag_enabled_or_raise?(feature_name) || self.feature_flag_enabled_or_raise?(feature_name) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
  end

  def reload_raw_data
    self.raw_data = Repository.where(id: id).pluck(:raw_data).first
  end

  # DGit repos in test and dev have an origin that points to a directory
  # with `dgitN` somewhere in it, like
  #   .../github/github/repositories/test/dgit1/...
  #                                       ^^^^^
  # Since the origin is stored in the config, and the config is hard
  # state, that means each replica will have a different checksum, which
  # makes the new repo unroutable under DGit.
  #
  # To make unit-testing forked repos under DGit possible, we just point
  # all replicas at the same origin.  In prod, this would be a no-op,
  # since they're all pointing at the same origin (on their respective
  # servers) anyway.  But leave it undefined on prod to be extra safe.
  if Rails.env.development? || Rails.env.test? # rubocop:todo GitHub/DoNotBranchOnRailsEnv
    def overwrite_origin_for_tests!
      rpc.config_store("remote.origin.url", "file://#{shard_path}")
    end
  end

  private

  # Special minimal HTML escape method for repository descriptions that are
  # inserted into generated READMEs. Only < and & are escaped so as not to make
  # the plain text of the generated README too tokeny but also avoiding
  # triggering HTML syntax in most cases.
  def escape_generated_readme_html(content)
    content.gsub(/[&<]/) do |match|
      case match
      when "&"; "&amp;"
      when "<"; "&lt;"
      end
    end
  end

  # The clone token scope is defined in duplicate here
  # and in the GitAuth code.
  def temp_clone_token_scope
    "TemporaryCloneURL:#{id}:read"
  end

  def ensure_owner_is_a_user_or_organization
    return if owner.nil? && !active?
    errors.add(:owner, "must be a User or Organization") unless ALLOWED_OWNER_TYPES.include?(owner.class.name)
  end

  def set_owner_login
    self.owner_login = owner&.login
  end

  def track_creation_outside_of_orchestration
    GitHub.dogstats.increment("repository.created_outside_orchestration")
    GitHub.logger.info("Repository created outside of orchestration",
      {
        "gh.repo.id" => self.id,
        "gh.request_id" => GitHub.context[:request_id]
      }
    )
  end

  def raise_on_creation_outside_of_orchestration
    # rubocop:todo GitHub/DoNotBranchOnRailsEnv
    suggestion = Rails.env.test? ? "Use create(:repository) instead." : "Use Repository.handle_creation instead."
    # rubocop:enable GitHub/DoNotBranchOnRailsEnv
    raise RepoCreationOutsideOrchestration, "Repositories should not be created directly. #{suggestion}"
  end

  def column_names
    @column_names ||= Set.new(self.class.column_names)
  end
end
