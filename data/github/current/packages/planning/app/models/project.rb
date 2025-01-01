# typed: false
# frozen_string_literal: true

class Project < ApplicationRecord::Domain::Projects
  include Ability::Subject
  include Ability::Membership
  include GitHub::Relay::GlobalIdentification
  include GitHub::Validations
  include Instrumentation::Model
  include Project::AuthorizerDependency
  include Project::ProjectLock
  include Project::SequenceDependency
  include Project::MigrationDependency
  include Project::WebsocketDependency
  include LegacyImportable

  include PreloadableAttributes
  include Project::AbilityDependency
  include Permissions::Attributes::Wrapper
  self.permissions_wrapper_class = Permissions::Attributes::Project

  class CardArchivingLockRequired < StandardError; end

  MAX_COLUMNS = 50
  MAX_REPOSITORY_LINKS = 25
  MAX_SUGGESTED_REPOS = 20
  MAX_NAME_LENGTH = 140
  SOURCE_KIND_GITHUB_TEMPLATE = "github_template"

  attr_preloadable :url

  belongs_to :owner, polymorphic: true
  destroy_in_background_with :owner, polymorphic_class_name: "Repository"
  belongs_to :creator, class_name: "User"
  card_scopes = proc do
    def notes
      self.where(content_id: nil)
    end

    def issues
      for_issues(scope: Issue.without_pull_requests)
    end

    def pulls
      for_issues(scope: Issue.with_pull_requests)
    end

    def for_issues(scope: nil)
      scoped_content_ids = where(content_type: "Issue").pluck(:content_id)
      scoped_issues = Issue.where(id: scoped_content_ids)
      scoped_issues = scoped_issues.merge(scope) if scope
      where(content_id: scoped_issues.ids) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    def with_purpose
      self.joins("INNER JOIN project_columns ON project_columns.id = project_cards.column_id").
        where("project_columns.purpose IS NOT NULL")
    end
  end

  card_order = "project_cards.created_at DESC, project_cards.id DESC"
  has_many :cards, -> { order(card_order) }, class_name: "ProjectCard", &card_scopes

  has_many :columns,
    -> { order("position ASC") },
    class_name: "ProjectColumn",
    inverse_of: :project

  has_many :project_workflows
  has_many :project_workflow_actions
  has_many :project_repository_links, dependent: :destroy
  has_many :linked_repositories,
    through: :project_repository_links,
    source: :repository,
    disable_joins: true
  has_one :project_migration, foreign_key: :source_project_id, inverse_of: :project

  destroy_dependents_in_background :cards
  destroy_dependents_in_background :columns
  destroy_dependents_in_background :project_workflows

  validates :creator, presence: true, on: :create
  validates :name, presence: true, length: { maximum: MAX_NAME_LENGTH }
  validates :owner_type, presence: true, inclusion: { in: %w[Repository Organization User] }
  validates :body, bytesize: { maximum: 16777215 }
  validate :projects_must_be_enabled, on: :create
  validate :actor_can_modify_projects, unless: -> { importing? || changes.keys == ["closed_at"] }
  validate :prevent_reopening_closed_migrated_project, if: :closed_at_changed?
  delegate :empty?, to: :cards, allow_nil: true

  before_validation :ensure_correct_owner_type, if: -> { owner_id_changed? || owner_type_changed? }

  before_create :set_number!, unless: :importing?
  after_create :owner_dependent_added

  after_commit :track_project_creation, :instrument_creation, :grant_write_to_owning_org_after_commit, on: :create
  after_commit :synchronize_search_index
  after_commit :instrument_update, on: :update

  before_destroy :destroy_project_callbacks_before_destroy
  after_destroy_commit :destroy_project_callbacks_after_commit

  after_commit :instrument_deletion, on: :destroy

  after_update :notify_metadata_subscribers

  def marked_for_deletion?
    deleted_at?
  end

  attribute :body, StringFromBinary.new
  attribute :name, StringFromBinary.new

  scope :open_projects, -> { where(closed_at: nil).not_marked_for_deletion }
  scope :closed_projects, -> { where("projects.closed_at IS NOT NULL").not_marked_for_deletion }
  scope :public_projects, -> { where(public: true) }

  scope :prefer_linked_to, -> (repo) {
    select("(project_repository_links.id IS NOT NULL) AS is_linked, projects.*").
      joins("LEFT OUTER JOIN project_repository_links ON project_repository_links.project_id = projects.id").
      where("project_repository_links.repository_id = ? OR project_repository_links.repository_id IS NULL", repo.id).
      order("is_linked DESC")
  }

  scope :marked_for_deletion, -> { where("deleted_at IS NOT NULL") }
  scope :not_marked_for_deletion, -> { where(deleted_at: nil) }

  # Get organization projects where the org has organization_projects.disable set.
  scope :org_projects_disabled_by_org, -> do
    org_ids_owning_projects = owned_by_organization.distinct.pluck(:owner_id)

    if org_ids_owning_projects.any?
      org_ids_with_disabled_org_projects = Configuration::Entry
        .named(Configurable::DisableOrganizationProjects::KEY)
        .targeting_user_ids(org_ids_owning_projects)
        .with_true_value
        .pluck(:target_id)

      if org_ids_with_disabled_org_projects.any?
        owned_by_organization.where(owner_id: org_ids_with_disabled_org_projects)
      else
        none
      end
    else
      none
    end
  end

  # Get repository projects where the repository has projects.disable set.
  #
  # repo_ids_owning_projects - Array of Repository IDs to check
  scope :repo_projects_disabled_by_repo, ->(repo_ids_owning_projects) do
    if repo_ids_owning_projects.any?
      repo_ids_with_disabled_repo_projects = Configuration::Entry
        .named(Configurable::DisableRepositoryProjects::KEY)
        .targeting_repository_ids(repo_ids_owning_projects)
        .with_true_value
        .pluck(:target_id)

      if repo_ids_with_disabled_repo_projects.any?
        owned_by_repository.where(owner_id: repo_ids_with_disabled_repo_projects)
      else
        none
      end
    else
      none
    end
  end

  # Get repository projects where the repository is owned by an organization that has projects.disable set.
  #
  # repo_ids_owning_projects - Array of Repository IDs to check
  scope :repo_projects_disabled_by_repo_owner, ->(repo_ids_owning_projects) do
    if repo_ids_owning_projects.any?
      org_ids_owning_repos_owning_projects = Repository.where(id: repo_ids_owning_projects).distinct.pluck(:owner_id)

      if org_ids_owning_repos_owning_projects.any?
        org_ids_with_disabled_repo_projects = Configuration::Entry
          .named(Configurable::DisableRepositoryProjects::KEY)
          .targeting_user_ids(org_ids_owning_repos_owning_projects)
          .with_true_value
          .pluck(:target_id)

        if org_ids_with_disabled_repo_projects.any?
          repo_ids_whose_owners_have_disabled_projects = Repository
            .where(id: repo_ids_owning_projects, owner_id: org_ids_with_disabled_repo_projects).pluck(:id)

          if repo_ids_whose_owners_have_disabled_projects.any?
            owned_by_repository.where(owner_id: repo_ids_whose_owners_have_disabled_projects)
          else
            none
          end
        else
          none
        end
      else
        none
      end
    else
      none
    end
  end

  # Get repository projects where the repository has projects.disable set, or
  # where the repository is owned by an organization that has projects.disable set.
  scope :repo_projects_disabled_by_repo_or_repo_owner, -> do
    repo_ids_owning_projects = owned_by_repository.distinct.pluck(:owner_id)

    repo_projects_disabled_by_repo(repo_ids_owning_projects)
      .or(repo_projects_disabled_by_repo_owner(repo_ids_owning_projects))
  end

  # Get repository and organization projects where the repository, the repository's owner, or the organization
  # has projects.disable set.
  scope :owner_projects_disabled, -> { org_projects_disabled_by_org.or(repo_projects_disabled_by_repo_or_repo_owner) }

  scope :owner_projects_enabled, -> { where.not(id: owner_projects_disabled) }

  scope :owned_by_repository, -> { where(owner_type: "Repository") }
  scope :owned_by_organization, -> { where(owner_type: "Organization") }

  def self.viewer_can_create_projects?(project_owner:, viewer:)
    GitHub.dogstats.distribution_time("project_permissions.dist.viewer_can_create_projects", tags: ["owner_type:#{project_owner.class.name}"]) do
      case project_owner
      when Repository
        !project_owner.locked_on_migration? && project_owner.pushable_by?(viewer)
      when Organization
        project_owner.member?(viewer)
      when User
        project_owner == viewer
      end
    end
  end

  # This method assumes that the caller has already checked whether or not
  # the viewer can create projects at all.
  def self.viewer_can_create_public_project?(project_owner:, viewer:)
    # Visibility for repository-owned projects is governed by the visibility of the repo itself.
    return false if project_owner.is_a?(Repository)

    # A user-owned project must be owned by the viewer, so they can create it publicly if they so wish.
    return true if project_owner.user?

    # An organization-owned project can be created publicly if members are allowed to make projects public.
    return true if project_owner.organization? && project_owner.members_can_change_project_visibility?

    # An org admin can always create a public project.
    return true if project_owner.organization? && project_owner.adminable_by?(viewer)

    # Otherwise, the viewer cannot create a public project.
    false
  end

  # Returns a list of orgs a viewer is able to create projects in
  def self.valid_org_owners_for(viewer:)
    viewer_org_ids = viewer.organization_ids
    viewer_org_ids_with_org_projects_disabled = Organization.ids_with_organization_projects_disabled(viewer_org_ids)
    viewer.organizations.where.not(id: viewer_org_ids_with_org_projects_disabled).by_login.limit(25)
  end

  def self.valid_repo_owners_for(repository_ids:)
    Repository.
      where(id: Repository.filter_ids_with_projects_enabled(repository_ids)).
      sorted_by_name.
      limit(25)
  end

  # Public: Returns a list of potential project owners where the viewer can
  # create project boards.
  #
  # viewer - the User creating a project board
  # query  - the user-defined search query string
  #
  # Returns an Array that may contain Organizations, Repositories, and the viewer
  def self.query_valid_owners_for(viewer:, query: nil)
    return [] if viewer.nil?

    clean_query = query.to_s.downcase.
      sub(/\A[\/\s]+/, ""). # strip leading slashes and whitespace
      sub(/[\/\s]+\z/, "")  # strip trailing slashes and whitespace

    results = [viewer]

    if clean_query.blank?
      results.concat(valid_org_owners_for(viewer: viewer))

      results.concat(valid_repo_owners_for(
        # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
        repository_ids: viewer.associated_repository_ids(min_action: :write)
        # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
      ))

      return results
    end

    maybe_owner, repo_name = clean_query.split("/", 2)
    org_or_user = User.find_by_login(maybe_owner)
    repo_query = repo_name || (maybe_owner if !org_or_user)

    results.concat(
      query_valid_repo_owners_for(
        viewer: viewer,
        owner: org_or_user,
        repo_query: repo_query,
      ).to_a,
    )

    results.concat(
      query_valid_org_owners_for(
        viewer: viewer,
        owner_query: maybe_owner,
        is_nwo_query: repo_name.present?,
      ).to_a,
    )

    results
  end

  def self.query_valid_org_owners_for(viewer:, owner_query:, is_nwo_query: false)
    # When the query string was a repo name-with-owner, we are only after repo matches
    return Organization.none if is_nwo_query

    valid_org_owners_for(viewer: viewer).with_prefix("login", owner_query)
  end
  private_class_method :query_valid_org_owners_for

  def self.query_valid_repo_owners_for(viewer:, owner:, repo_query:)
    # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
    associated_repo_ids = viewer.associated_repository_ids(min_action: :write)
    # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded

    repository_ids = if owner.present?
      repository_ids_owned_by_owner = Repository.filter_ids_with_projects_enabled(
        associated_repo_ids & Repository.owned_by(owner).ids
      )

      # Exclude exact match owners the viewer does not have access to
      # and use the login as a query parameter for repo name instead
      if repository_ids_owned_by_owner.any?
        repository_ids_owned_by_owner
      else
        repo_query = owner.display_login

        Repository.filter_ids_with_projects_enabled(associated_repo_ids)
      end
    else
      Repository.filter_ids_with_projects_enabled(associated_repo_ids)
    end

    query = Repository.where(id: repository_ids)

    if repo_query.present?
      query = query.with_prefix("repositories.name", repo_query)
    end

    query.sorted_by_name.limit(25).tap do |result|
      GitHub::PrefillAssociations.prefill_associations(result, [:owner, :organization])
    end
  end
  private_class_method :query_valid_repo_owners_for

  def self.owner_can_have_public_projects?(owner)
    owner_is_emu =
      if owner.class.name == "Organization"
        owner.enterprise_managed_user_enabled?
      else
        owner.is_enterprise_managed?
      end
    !owner_is_emu
  end

  def async_target_for_conditional_access
    async_owner.then do |owner|
      next owner.async_target_for_conditional_access if owner.is_a?(Repository)
      owner
    end
  end

  def public_project_or_owner?
    async_public_project_or_owner?.sync
  end

  def async_public_project_or_owner?
    if owner_type == "Repository"
      async_owner.then do |owner|
        owner.public?
      end
    else
      Promise.resolve(public?)
    end
  end

  def linked_repositories_viewer_can_see(viewer)
    async_linked_repositories_viewer_can_see(viewer).sync
  end

  def async_linked_repositories_viewer_can_see(viewer)
    return Promise.resolve(::Repository.none) if owner_type == "Repository"

    async_owner.then do
      async_project_repository_links.then do
        case owner_type
        when "Organization"
          available_repo_ids = owner.all_org_repo_ids_for_user(viewer)
          repo_ids = available_repo_ids & project_repository_links.map(&:repository_id)
          ::Repository.where(id: repo_ids).filter_spam_and_disabled_for(viewer)
        when "User"
          owner
            .visible_repositories_for(viewer)
            .where(id: project_repository_links.map(&:repository_id))
            .filter_spam_and_disabled_for(viewer)
        end
      end
    end
  end

  def open?
    !closed?
  end

  def closed?
    closed_at.present?
  end

  def open
    if !project_migration.nil?
      GitHub.dogstats.increment("memex_project_migration.source_project_reopened")
    end

    update(closed_at: nil)
  end

  def close
    update(closed_at: current_time_from_proper_timezone)
  end

  def state
    open? ? "open" : "closed"
  end

  def organization
    return owner if owner.is_a?(Organization)

    owner.organization if owner.is_a?(Repository) && owner.in_organization?
  end

  def content_scope(viewer:)
    content_scope = case owner
    when Repository
      if owner.public? || viewer.associated_repository_ids(repository_ids: [owner.id]).include?(owner.id)
        owner.issues
      else
        Issue.none
      end
    when User
      # Tried bounding the ARI call here (https://github.com/github/github/pull/241852#issuecomment-1287383801)
      # and it performed worse, so we're going to leave it unbounded for now
      # rubocop:disable GitHub/DontCallAssociatedRepositoryIdsUnbounded
      Issue.where(repository_id: owner.repositories.public_scope.ids + (owner.repositories.private_scope.ids & viewer.associated_repository_ids))
      # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
    end
  end

  def user_can_add_content?(user:, content:)
    return false unless writable_by?(user)

    content_scope(viewer: user).where(id: content.id).exists?
  end

  # In tests, owner_type for an Organization kept getting set to User.
  # I don't know why.
  def ensure_correct_owner_type
    if owner.class.name != owner_type
      self.owner_type = owner.class.name
    end
  end

  def soft_delete!
    touch(:deleted_at) unless self.destroyed?
    synchronize_search_index
  end

  def enqueue_delete(actor: modifying_user)
    soft_delete!
    DeleteProjectJob.perform_later(id, actor.id)
  end

  def move_column(column, after: nil)
    self.class.transaction do
      # Need to get the existing positions out of the way
      columns.update_all("position = position + 1000")

      # Set the new positions
      ordered_ids = columns.pluck(:id).map(&:to_s)
      ordered_ids.delete(column.id.to_s)

      if after && (after_index = ordered_ids.index(after.id.to_s))
        ordered_ids.insert(after_index + 1, column.id)
      else
        ordered_ids.unshift(column.id)
      end

      ordered_ids.each.with_index do |column_id, i|
        columns.find(column_id).update_column(:position, i)
      end
    end

    column.trigger_moved_hook(after)
  end

  def to_param
    number.to_s
  end

  def reset_column_positions
    columns.update_all("position = position + 1000")
    columns.order("position ASC").each_with_index do |column, i|
      column.update_column :position, i
    end
  end

  def as_json(*)
    { columns: columns }
  end

  # Public: Returns all Audit Log events for the current Project. The results
  # are paginated and can be controlled through options.
  #
  # options - The options Hash.
  #   :per_page  - The number of hits to return (default: 50)
  #   :page      - The current page (default: 1)
  #
  # Returns Array of Audit::Elastic::Hit instances.
  def audit_log(options = {})
    query = Audit::Driftwood::Query.new_project_query(options.merge(project: self))
    query.execute
  end

  def search_query_for(user)
    saved_query = Memex::KV.store.get(search_query_key(user)).value { nil }
    saved_query.force_encoding("UTF-8").scrub if saved_query.present?
  end

  # Public: Sets the search query for a user to be retrieved
  # as the default when returning to a project.
  #
  #  user - The user initiating the search
  #  query - the query string
  #
  # Returns encoded and scrubbed query that was saved
  def set_search_query_for(user, query:)
    query = query.dup.force_encoding("UTF-8").scrub if query

    ActiveRecord::Base.connected_to(role: :writing) do
      if query.blank?
        Memex::KV.store.del(search_query_key(user))
      else
        Memex::KV.store.set(search_query_key(user), GitHub::KV::BINARY(query))
      end
    end
    query
  end

  # Public: Synchronize this project with its representation in the search
  # index. If the project is newly created or modified in some fashion, then
  # it will be updated in the search index. If the project has been
  # destroyed, then it will be removed from the search index. This method
  # handles both cases.
  def synchronize_search_index
    if self.marked_for_deletion? || self.destroyed?
      RemoveFromSearchIndexJob.perform_later("project", self.id)
    else
      Search.add_to_search_index("project", self.id)
    end
    self
  end

  # Get a list of repos the user might like to add an issue to.
  # 1. If the project has linked repositories, recommend them.
  # 2. If there are issues in the project already, recommend their repos.
  # 3. If there are no issues in the project, recommend a list of repos
  # associated with the user that have issues enabled.
  # 4. In either case, if a filter is applied, reduce the list to those
  # whose names start with the filter string (splitting on CamelCase
  # names).
  #
  # Returns on Array of Repositories.

  def repository_suggestions(viewer:, filter: nil)
    return [] if owner_type == "Repository"

    # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
    viewable_repo_ids = Repository.where(id: viewer.associated_repository_ids).with_issues_enabled.ids
    # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
    linked_repo_ids = linked_repositories.ids

    repo_ids = if linked_repo_ids.any?
      viewable_repo_ids & linked_repo_ids
    else
      issue_ids = cards.where(content_type: "Issue").reorder(nil).pluck(:content_id)
      counts_subquery = Issue.select(:repository_id, "COUNT(id) issues_count")
        .where(id: issue_ids, repository_id: viewable_repo_ids)
        .group(:repository_id)

      Issue.select("counts.repository_id", "counts.issues_count")
        .from("(#{counts_subquery.to_sql}) counts")
        .order("counts.issues_count DESC")
        .limit(filter ? 100 : MAX_SUGGESTED_REPOS)
        .map(&:repository_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    repo_ids = viewable_repo_ids & Repository.owned_by(owner).ids if repo_ids.empty?
    position_by_repo_id = repo_ids.zip(0...repo_ids.size).to_h

    scope = Repository.where(id: repo_ids).limit(MAX_SUGGESTED_REPOS)
    scope = scope.with_substring("`repositories`.`name`", filter) if filter.present?
    scope.sort_by { |repo| position_by_repo_id[repo.id] }
  end

  # Applies a GitHub-provided template to a new OR empty Project and
  # saves the associated ProjectColumn and ProjectWorkflow objects
  #
  # See ProjectTemplate for template usage
  #
  def apply_template(template)
    errors.add(:base, "Can't apply template when columns are present") unless columns.none?
    errors.add(:base, "Invalid template provided") unless template.is_a?(ProjectTemplate)
    return false if errors.any?

    project_columns = columns.create(template.column_data)

    template.columns.each do |template_column|
      project_column = project_columns.find { |column| column.name == template_column.name }

      template_column.cards.each do |card|
        ProjectCard.create_in_column(project_column, creator: creator, content_params: { note: card.note, content_type: "Note" })
      end

      template_column.workflows.each do |trigger|
        project_workflows.set_workflow(trigger_type: trigger, creator: modifying_user, column: project_column)
      end
    end

    self.source_kind = SOURCE_KIND_GITHUB_TEMPLATE
    self.source_id = ProjectTemplate::SOURCE_MAPPINGS[template.class.to_s]
    save
  end

  # Filters repos by name on a given string
  def apply_repo_name_filter(repos, filter)
    filter = filter.downcase

    repos.to_a.select do |repo|
      repo.name.downcase.include?(filter)
    end.first(MAX_SUGGESTED_REPOS)
  end

  # Determines whether the project can be re-parented to a given object.
  # Note-only projects can be reparented to any owner. Projects with issue/PR
  # cards can be reparented if all issue/PR repositories are descendents of the
  # potential owner.
  #
  # NOTE: Only content is tested, not card creators or other actors.
  #
  #   new_owner - Repository, Organization, or User object
  #
  # Returns true or false
  def can_change_owner_to?(new_owner)
    return false if new_owner == owner
    return true if owner && !owner.is_a?(Repository) && MoveWork.started_for?(owner, self)

    card_content_owner_ids = cards.
      for_content_type("Issue").
      includes(:content).
      map(&:content). # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      map(&:repository_id).
      uniq

    if new_owner.is_a?(Repository)
      (card_content_owner_ids - [new_owner.id]).empty?
    elsif new_owner.is_a?(User)
      (card_content_owner_ids - new_owner.repositories.pluck(:id)).empty?
    end
  end

  # Re-parents the project to the given owner, as long as the operation is
  # permitted (see Project#can_change_owner_to?).
  #
  #   new_owner - a Repository, Organization, or User
  #
  # Returns the saved Project or false if the operation was blocked
  def change_owner!(new_owner:)
    return false unless can_change_owner_to?(new_owner)

    old_owner = owner
    self.owner = new_owner
    self.number = nil

    # Remove the memoized sequence context since it references the old owner
    remove_instance_variable(:@sequence_context) if instance_variable_defined?(:@sequence_context)

    # This prevents a frankenquery composed of a SELECT on the new owner_type's
    # table with a WHERE clause from the old owner_type's table and old
    # owner_id.
    #
    # Calling reset_scope on the association before
    # ActiveRecord::Associations::SingularAssociation#find_target gets called
    # resets the scope and executes the correct query.
    #
    association(:owner).reset_scope

    set_number!
    save!

    # Set up permissions on the new owner
    owner.change_owner_of!(project: self, creator: creator, old_owner: old_owner)

    # Add repository links for Org and User owned projects
    if old_owner.is_a?(Repository) && old_owner.owner == owner
      # Link the repository you just transferred from
      link_repository(old_owner, creator)
    end

    self
  end

  # Handles the scenario where we are transforming a User into an Organization.
  # - changes the project owner to an Organization
  # - updates the creator to the new org's administrator
  # - adds the creator as an admin
  def transform_owner_type!(owner:, new_creator:)
    raise "Cannot transform #{owner_type} project to #{owner.class.name} project" unless owner.is_a?(Organization)

    self.owner = nil
    change_owner!(new_owner: owner)
    self.creator = new_creator
    update_user_permission(new_creator, :admin)
    save!
  end

  # Public: Builds and returns the unique project search slug as a String.
  def search_slug
    "#{owner_slug}/#{number}"
  end

  # Public: Returns the owner of a project as a String.
  def owner_slug
    case owner
    when Repository
      owner.name_with_display_owner
    when User
      owner.display_login
    end
  end

  def event_context(prefix: event_prefix)
    {
      prefix => name,
      "#{prefix}_id".to_sym => id,
    }
  end

  def spammy?
    creator.try(:spammy?)
  end

  def url
    return @url if defined?(@url)
    @url = async_url.sync
  end

  def async_url(suffix = "", params = {})
    async_owner.then do |project_owner|
      case project_owner
      when Repository
        project_owner.async_owner.then do |user_owner|
          template = Addressable::Template.new("/{user}/{repo}/projects/{number}#{suffix}")
          template.expand({ user: user_owner.display_login, repo: project_owner.name, number: number }.merge(params))
        end
      when Organization
        template = Addressable::Template.new("/orgs/{org}/projects/{number}#{suffix}")
        template.expand({ org: project_owner.display_login, number: number }.merge(params))
      when User
        template = Addressable::Template.new("/users/{user}/projects/{number}#{suffix}")
        template.expand({ user: project_owner.display_login, number: number }.merge(params))
      else
        raise NotImplementedError, "Only repository, org, and user projects are supported"
      end
    end
  end

  def current_workflow_action_id
    GitHub.context[:project_workflow_action_id]
  end

  # Public: Queues an automatic resync job for processing if the project is in
  # the correct state.
  #
  # We also create and pass a job status id so we can track in the UI.
  def enqueue_resync_workflows
    return if open? || locked_for?(PROJECT_RESYNCING)
    status = Memex::JobStatus.create(id: ResyncProjectWorkflowsJob.job_id)

    ResyncProjectWorkflowsJob.perform_later(
      self.id,
      {
        actor_id: modifying_user.id,
        queued_at: Time.current,
        status_id: status.id,
      },
    )
  end

  # Get the workflows in the order in which they should run for resync
  def ordered_resync_workflows
    project_workflows.sort do |a, b|
      next 0 if a.trigger_type == b.trigger_type

      # Run pending card triggers first
      next -1 if ProjectWorkflow::PENDING_CARD_TRIGGERS.include?(a.trigger_type)
      next 1 if ProjectWorkflow::PENDING_CARD_TRIGGERS.include?(b.trigger_type)

      # Run reopened trigger next
      next -1 if ProjectWorkflow::REOPENED_TRIGGERS.include?(a.trigger_type)
      next 1 if ProjectWorkflow::REOPENED_TRIGGERS.include?(b.trigger_type)

      # Run review triggers next
      next -1 if ProjectWorkflow::REVIEW_TRIGGERS.include?(a.trigger_type)
      next 1 if ProjectWorkflow::REVIEW_TRIGGERS.include?(b.trigger_type)

      # Run everything else last
      0
    end
  end

  # This will go through all of the workflows for a project and run them for cards whose state
  # has changed up to the supplied time, catching the cards' column positions up.
  def resync_workflows!(actor:, as_of: Time.current)
    return if locked_for?(PROJECT_RESYNCING)

    GitHub.dogstats.increment("job.resync_project_workflows.resync_triggered")

    lock_safely(lock_type: PROJECT_RESYNCING, actor: actor) do
      ordered_resync_workflows.each do |workflow|
        workflow.resync!(actor: actor, as_of: as_of)
      end
      touch(:last_sync_at)
    end
  end

  def automation_context?
    GitHub.context[:project_workflow_action_id].present?
  end

  def progress
    @progress ||= ProjectProgress.new(self)
  end

  # Create a ProjectRepositoryLink between the Project and provided Repository
  # Statistics are tracked in ProjectRepositoryLink.
  # Raises an error if the link cannot be saved
  def link_repository(repository, actor)
    link = ProjectRepositoryLink.create!(project_id: id, repository_id: repository&.id, creator_id: actor&.id)

    instrument :link, actor: actor, repo: repository

    link
  end

  # Severs the ProjectRepositoryLink between the Project and provided Repository
  # Statistics are tracked in ProjectRepositoryLink.
  # Raises an error if the link is not found
  def unlink_repository(repository)
    project_repository_links.find_by!(repository_id: repository.id).destroy

    instrument :unlink, actor: modifying_user, repo: repository
  end

  # Severs the ProjectRepositoryLink between the Project and all repositories
  # upon ownership change
  # Statistics are tracked in ProjectRepositoryLink.
  # The most records this will return is MAX_REPOSITORY_LINKS
  def unlink_repositories
    UnlinkAllProjectRepositoryLinksJob.perform_later(id, GitHub.context[:actor_id])
  end

  def suggested_repositories_to_link(actor:)
    return Repository.none if owner_type == "Repository"

    issue_ids = cards.where(content_type: "Issue").pluck(:content_id)

    return Repository.none if issue_ids.empty?

    # Get the IDs of the unlinked repositories with cards in this project,
    # ordered by whichever ones have the most cards in this project.
    sql = Arel.sql(<<-SQL, issue_ids: issue_ids)
      SELECT issues.repository_id, COUNT(*) AS amount
      FROM issues
      WHERE issues.id IN (:issue_ids)
    SQL

    if linked_repository_ids.any?
      sql += Arel.sql(<<-SQL, linked_repository_ids: linked_repository_ids)
        AND issues.repository_id NOT IN (:linked_repository_ids)
      SQL
    end

    sql += Arel.sql(<<-SQL)
      GROUP BY issues.repository_id
      ORDER BY amount DESC
    SQL

    repo_ids = Issue.connection.select_values(sql) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

    if repo_ids.any?
      owner.visible_repositories_for(actor)
        .where(id: repo_ids)
        .filter_spam_and_disabled_for(actor)
        .order(Arel.sql("FIELD(repositories.id, #{repo_ids.join(",")})"))
        .limit(MAX_REPOSITORY_LINKS)
    else
      Repository.none
    end
  end

  def project_migration_payload
    return nil if project_migration.nil?

    project_migration.status_payload
  end

  def grant_write_to_owning_org_after_commit
    update_org_permission(:write) if owner.is_a?(Organization)
  end

  def destroy_project_callbacks
    @destroy_callback ||= DestroyProjectCallbacks.new
  end

  def destroy_project_callbacks_before_destroy
    if modifying_user&.spammy? || spammy?
      @delivery_system = nil
      return
    end
    destroy_project_callbacks.before_destroy(self)
  end

  def destroy_project_callbacks_after_commit
    if modifying_user&.spammy? || spammy?
      @delivery_system = nil
      return
    end
    destroy_project_callbacks.after_commit(self)
    @delivery_system.map(&:deliver_later) if @delivery_system.present?
  end

  # Internal: If the current project is being destroyed, we need to assemble various
  # payloads. The project is going to go away, and we need to make sure they are
  # still represented in hooks being fired for its associations.
  #
  # event - Required kwarg indicating which event is being delivered later
  #
  # Returns the current project.
  def construct_future_event(&block)
    @delivery_system = Array(@delivery_system)
    @delivery_system << Hook::DeliverySystem.new(yield)
    @delivery_system.last.generate_hookshot_payloads
  end

  def target_for_conditional_access
    owner.target_for_conditional_access
  end

  def path
    case
    when owner.class == Repository
      UrlHelpers.repo_project_path(owner.owner.display_login, owner.name, number)
    when owner.class == Organization
      UrlHelpers.org_project_path(owner.display_login, number)
    when owner.class == User
      UrlHelpers.user_project_path(owner.display_login, number)
    else
      raise NotImplementedError, "Only repository, org, and user projects are supported"
    end
  end

  private

  def search_query_key(user)
    "project_queries:#{id}:#{user.id}"
  end

  def set_number!
    ensure_correct_owner_type
    create_sequence_if_missing

    self.number = Sequence.next(self)
  end

  def track_project_creation
    GitHub.dogstats.increment("project.with_#{self.owner_type.underscore}_owner.created")
  end

  def safe_user
    creator || User.ghost
  end

  # The user who performed the action as set in the GitHub request context.
  # If the context doesn't contain an actor, fallback to the ghost user
  def modifying_user
    @modifying_user ||= (User.find_by_id(GitHub.context[:actor_id]) || User.ghost)
  end

  # Internal: payload for project instrumentation
  def event_payload
    payload = { project: self, rank: 1 }

    # add the org and repo (if it exists) to the payload so the project
    # activity shows up in the organizations audit log
    payload[owner.event_prefix] = owner if owner.present?
    if owner.is_a?(Repository) && owner.owner.is_a?(Organization)
      payload[owner.owner.event_prefix] = owner.owner
    end
    payload
  end

  def instrument_creation
    return unless owner.present?
    GlobalInstrumenter.instrument("project.create", {
      project: self,
      owner_repo: owner_type == "Repository" ? owner : nil,
      owner_user: owner_type != "Repository" ? owner : nil,
      actor: safe_user,
      action: :create,
    })
    instrument :create, actor: safe_user, spammy: spammy?
  end

  def instrument_state_change
    return unless owner.present?
    action = closed_at.present? ? :close : :open

    instrument action, actor: modifying_user

    GlobalInstrumenter.instrument("project.#{action}", {
      project: self,
      owner_repo: owner_type == "Repository" ? owner : nil,
      owner_user: owner_type != "Repository" ? owner : nil,
      actor: modifying_user,
      action: action,
    })
  end

  def instrument_update
    return instrument_state_change if previous_changes.has_key?("closed_at")

    return unless owner.present?

    GlobalInstrumenter.instrument("project.update", {
      project: self,
      owner_repo: owner_type == "Repository" ? owner : nil,
      owner_user: owner_type != "Repository" ? owner : nil,
      actor: safe_user,
      action: :update
    })

    old_name = previous_changes["name"].try(:first)

    changes = {}.tap do |hash|
      if old_name.present?
        hash[:old_name] = old_name
        hash[:name] = name
      end
      if previous_changes.has_key?("body")
        hash[:old_body] = previous_changes["body"].first
        hash[:body] = body
      end
      if previous_changes.has_key?("track_progress")
        hash[:old_track_progress] = previous_changes["track_progress"].first
        hash[:track_progress] = track_progress
      end
      if previous_changes.has_key?("public")
        hash[:old_public] = previous_changes["public"].first
        hash[:public] = public?
      end
    end

    if old_name.present?
      instrument :rename, old_name: old_name
    end

    if previous_changes.has_key?("public")
      instrument :access, access: public? ? "public" : "private"
    end

    if changes.present?
      instrument :update, actor: modifying_user, changes: changes
    end
  end

  def instrument_deletion
    instrument :delete
    GlobalInstrumenter.instrument("project.delete", {
      project: self,
      owner_repo: owner_type == "Repository" ? owner : nil,
      owner_user: owner_type != "Repository" ? owner : nil,
      actor: modifying_user,
      action: :delete,
    })
  end

  def projects_must_be_enabled
    errors.add(:owner, "Projects are disabled on this #{owner_type.downcase}.") unless owner.projects_enabled?
  end

  def prevent_reopening_closed_migrated_project
    errors.add(:base, "Projects (Classic) is being sunset. Closed projects that have been migrated cannot be reopened") if closed_at_was.present? && project_migration&.completed?
  end
end
