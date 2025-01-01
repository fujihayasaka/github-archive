# typed: true
# frozen_string_literal: true

require_relative "advisory_db/repository_advisories/k_v"

class RepositoryAdvisory < ApplicationRecord::Collab
  # These aliases allow Sorbet to understand generated relation methods
  # that can be called on a relation or collection proxy,
  # such as the various scopes that can be called
  PublicGeneratedRelationMethodsAlias = GeneratedRelationMethods
  CollectionProxyOrRelationType = T.type_alias do
    T.all(
        T.any(
        ActiveRecord::Associations::CollectionProxy,
        ActiveRecord::AssociationRelation
      ),
      PublicGeneratedRelationMethodsAlias
    )
  end

  class MarkdownBody
    include GitHub::UserContent

    attr_reader :body

    def initialize(body)
      @body = body || ""
    end

    def new_record?
      true
    end
  end

  include GitHub::RateLimitedCreation
  include GitHub::Relay::GlobalIdentification
  include NotificationsContent::WithCallbacks
  include Reaction::Subject::RepositoryContext
  include UserContentEditable
  include HasCVEUrl
  include Instrumentation::Model
  include AdvisoryDB::CvssScore
  include Reactable
  include AbuseReportable
  include Spam::ContentUserIsSpammy
  include PreloadableAttributes
  include AuthorAssociable
  include AdvisoryDB::ScopedVulnerabilityHelper
  include Repositories::Domain::Provider
  include UploadContainer::RepositoryAdvisoryDependency

  after_create :assign_upload_container_id_to_file_attachments
  after_create :assign_upload_container_id_to_user_assets
  attr_preloadable :viewer_can_react, :body_html, :readable_by, :viewer_can_update,
    :viewer_can_read_user_content_edits, :reaction_groups, :reaction_path, :user_is_spammy, :author_association_symbol

  include Permissions::Attributes::Wrapper
  self.permissions_wrapper_class = Permissions::Attributes::RepositoryAdvisory

  CVE_ID_PATTERN = /\ACVE-\d{4}-\d{4,31}\z/
  CVSS_V3_PATTERN = /\ACVSS:3\.\d+(\/[A-Z]{1,3}:[A-Z]){8,22}\z/
  CVSS_V4_PATTERN = /\ACVSS:4\.\d+(\/[A-Z]{1,3}:[A-Z]){11,26}\z/
  MESSAGE_ID_TEMPLATE = "<%{repo}/repository-advisories/%{id}@%{host}>"
  URI_TEMPLATE = Addressable::Template.new("/{owner}/{name}/security/advisories/{ghsa_id}")
  API_URI_TEMPLATE = Addressable::Template.new("/repos/{owner}/{name}/security-advisories/{ghsa_id}")

  enum :severity, %i{
    low
    moderate
    high
    critical
  }

  # All user editable text fields must support UTF-8 and need encoding forced
  attribute :title, StringFromBinary.new
  attribute :description, StringFromBinary.new
  attribute :body, StringFromBinary.new
  attribute :cve_id, StringFromBinary.new
  attribute :cvss_v3, StringFromBinary.new
  attribute :cvss_v4, StringFromBinary.new

  include ::Repositories::BelongsToRepository
  flagged_belongs_to_repository_via_domain
  belongs_to :author,
    class_name: "User",
    foreign_key: :author_id,
    inverse_of: false # no inverse association defined
  belongs_to :publisher,
    class_name: "User",
    foreign_key: :publisher_id,
    optional: true,
    inverse_of: false # no inverse association defined
  belongs_to :vulnerability,
    primary_key: :ghsa_id,
    foreign_key: :ghsa_id,
    optional: true,
    inverse_of: :repository_advisory
  belongs_to :scoped_vulnerability,
  ->(ra) { T.let(ra, RepositoryAdvisory).retrieve_with_vulnerability_scope },
    optional: true,
    class_name: "ScopedVulnerability",
    primary_key: :security_advisory_id,
    foreign_key: :id,
    inverse_of: :repository_advisory
  belongs_to :workspace_repository,
    class_name: "Repository",
    inverse_of: :parent_advisory

  # cannot use destroy_dependents_in_background for comments because of newsies
  # dependency on the advisory still being readable for unsubscribing
  has_many :comments,
    -> { order(id: :asc) },
    class_name: "RepositoryAdvisoryComment",
    dependent: :destroy
  has_many :cwe_references,
    as: :source,
    class_name: "CWEReference",
    dependent: :destroy
  has_many :cwes,
    through: :cwe_references,
    as: :source,
    class_name: "CWE",
    after_add: :instrument_add_cwe,
    after_remove: :instrument_remove_cwe
  has_many :events,
    -> { order(id: :asc) },
    class_name: "RepositoryAdvisoryEvent",
    dependent: :destroy
  # We cannot simply cascade destroy or nullify associated AdvisoryCredits
  # because they may also be attached to global advisories. Instead use an
  # after_commit hook to trigger a background job that will decide whether to
  # destroy or nullify.
  has_many :credits,
    -> { order(id: :asc) },
    class_name: "AdvisoryCredit"
  after_commit :destroy_or_nullify_advisory_credits, on: :destroy
  has_many :affected_products,
    class_name: "RepositoryAdvisoryAffectedProduct"
  destroy_dependents_in_background :affected_products
  has_many :reactions,
    as: :subject,
    dependent: :destroy

  accepts_nested_attributes_for :credits, allow_destroy: true
  accepts_nested_attributes_for :affected_products, allow_destroy: true

  alias_attribute :user_id, :author_id
  def user
    author
  end

  def async_user
    async_author
  end

  scope :published, -> { where(state: "published") }
  scope :unpublished, -> { where.not(state: "published") }
  scope :private_to_org, -> (organization) { unpublished.where(workspace_repository_id: organization.org_repositories.pluck(:id)) }
  scope :newest_first, -> { order(id: :desc) }
  scope :open_untriaged, -> { open.where(external: true, accepted: false) }
  scope :open_triaged, -> { open.where(external: false).or(open.where(accepted: true)) }
  scope :open_source, -> { where(repo_advisory_type: "open_source") }
  scope :innersource, -> { where(repo_advisory_type: "innersource") }

  # VALIDATIONS

  validates :repository, presence: true
  validates :author, presence: true
  validates :title, presence: true, length: { maximum: 1024 }
  validates :description, presence: true, if: :published?
  validates :severity, presence: true, if: :published?
  validates :cve_id, format: { with: CVE_ID_PATTERN, allow_blank: true }
  validates :cvss_v3, format: { with: CVSS_V3_PATTERN, allow_blank: true }, length: { maximum: 255 }, cvss_vector_string: true
  validates :cvss_v4, format: { with: CVSS_V4_PATTERN, allow_blank: true }, length: { maximum: 255 }, cvss_vector_string: true
  validate :affected_products_must_have_affected_versions, if: :published?
  validate :description_does_not_match_template?, unless: [:open?, :closed?]
  validate :cannot_set_cvss_v3_and_cvss_v4_together

  # CALLBACKS

  before_validation :set_ghsa_id!, on: :create, unless: :ghsa_id?
  before_validation :set_owner_id!, on: :create
  before_create :set_repo_advisory_type!
  before_save :set_only_one_cvss_version!
  after_commit :subscribe_repository_admins_and_notify, on: :create
  after_commit :instrument_open_event, on: :create
  after_commit :instrument_update_event, on: :update, if: :instrument_update_event?
  after_commit :update_subscriptions_and_notify, on: :update
  after_commit :instrument_reopen_event, if: [:open?, :state_previously_changed?]
  after_commit :instrument_close_event, if: [:closed?, :state_previously_changed?]

  # This overrides the callback in NotificationsContent::WithCallbacks so the callback
  # can run without an associated repository.
  after_commit :destroy_notification_summary, on: :destroy

  attr_readonly :ghsa_id, :owner_id

  # HANDLING USER CONTENT {

  include GitHub::UserContent
  # These two methods are injected into the async_body_context which informs
  # how the description is rendered and which mentions are authorized.
  #
  # See: GitHub::UserContent
  # See also: #async_organization
  def async_body_context_user
    async_author
  end

  def async_entity
    async_repository
  end
  # } HANDLING USER CONTENT

  # ABILITY INTERFACE {
  include Ability::Subject

  def viewer_can_report(user = nil)
    async_viewer_can_report?(user).sync
  end

  def viewer_relationship(user = nil)
    async_viewer_relationship(user).sync
  end

  def stafftools_url
    UrlHelpers.stafftools_repository_repository_advisory_path(T.must(repository).owner, T.must(repository).name, id)
  end

  # Hardcoded to maintain a shared interface with other comment types, which assume compatability with the
  # EmailReceivable interface.
  def created_via_email
    false
  end

  # Hardcoded to maintain a shared interface with other comment types, which assume compatability with the
  # GitHub::MinimizeComment interface.
  def minimized?
    false
  end

  def self.multiple_target_for_conditional_access(advisories)
    ConditionalAccess::Filter.ensure_with_class(advisories, RepositoryAdvisory)

    repositories = Repository.where(id: advisories.map { |advisory| advisory.repository_id })
    repository_to_target = Repository.multiple_target_for_conditional_access(repositories)

    repository_id_to_target = repository_to_target.transform_keys { |k| k.id }
    advisories.each_with_object({}) { |v, h| h[v] = repository_id_to_target[v.repository_id] }
  end

  def target_for_conditional_access
    T.must(repository).target_for_conditional_access
  end

  def async_target_for_conditional_access
    async_repository.then { |x| T.must(x).async_target_for_conditional_access }
  end

  def adminable_by?(actor)
    async_adminable_by?(actor).sync
  end

  # An Advisory permits admin abilities by an actor who
  # can admin its parent Repository
  def async_adminable_by?(actor)
    async_repository.then do |repository|
      next false unless repository

      # Check `manage_security_products` if the user isn't a bot
      next SecurityProduct::Permissions::RepoAuthz.new(repository, actor:).async_can_manage_security_products? if actor.is_a?(User) && actor.user?

      # Check repository_advisories write permissions if the actor is a bot
      next repository.resources.repository_advisories.writable_by?(actor) if actor&.can_have_granular_permissions?

      repository.async_adminable_by?(actor)
    end
  end

  def workspace_openable_by?(actor)
    return false unless writable_by?(actor)

    repository&.advisory_management_authorized_for?(actor) || user_is_pvd_submitter?(actor)
  end

  def writable_by?(actor)
    async_writable_by?(actor).sync
  end

  # An actor may have a direct write ability -or-
  # be an admin of the parent repository
  def async_writable_by?(actor)
    async_permit?(actor, :write).then do |permitted|
      next true if permitted

      async_adminable_by?(actor)
    end
  end

  def viewer_can_update?(user = nil)
    # this does not support multiple viewers currently
    return @viewer_can_update if defined? @viewer_can_update
    return false if user.nil?

    @viewer_can_update = async_viewer_can_update?(user).sync
  end

  def safe_user
    user || User.ghost
  end

  def async_viewer_can_update?(viewer)
    async_viewer_cannot_update_reasons(viewer).then(&:empty?)
  end

  def async_viewer_can_delete?(viewer)
    async_viewer_can_update?(viewer)
  end

  def viewer_can_delete?(user = nil)
    return @viewer_can_delete if defined?(@viewer_can_delete)
    return false if user.nil?

    @viewer_can_delete = async_viewer_can_delete?(user).sync
  end

  def async_viewer_cannot_update_reasons(viewer)
    return Promise.resolve([:login_required]) unless viewer

    async_writable_by?(viewer).then do |writable|
      writable ? [] : [:insufficient_access]
    end
  end

  def async_readable_by?(actor)
    if published?
      async_repository.then do |repository|
        next false unless repository

        repository.async_readable_by?(actor)
      end
    else
      async_permit?(actor, :read).then do |readable|
        next true if readable

        async_writable_by?(actor)
      end
    end
  end

  # An actor may have a direct read ability -or-
  # be an admin of the parent repository
  def readable_by?(actor)
    async_readable_by?(actor).sync
  end

  def unpublished_and_viewer_readable_only?(actor)
    !published? && !writable_by?(actor) && readable_by?(actor)
  end

  # Returns the correct title for the advisory based on the actor's permissions
  # When an author of a PVD is removed and the advisory is unpublished, the title
  # that needs to be displayed is the title frozen when the author was removed.
  #
  # Generally PVD author = a viewer that still has read rights but not write rights
  #
  # If an actor is not provided and the advisory is unpublished, the title will be the frozen title
  # if it exists or the current title otherwise. The frozen title is only set when an author is removed.
  def get_title(actor)
    if frozen_title && ((!actor && !published?) || unpublished_and_viewer_readable_only?(actor))
      frozen_title
    else
      title
    end
  end

  # Returns the correct description for the advisory based on the actor's permissions
  # When an author of a PVD is removed and the advisory is unpublished, the description
  # that needs to be displayed is the description frozen when the author was removed.
  #
  # Generally PVD author = a viewer that still has read rights but not write rights
  #
  # If an actor is not provided and the advisory is unpublished, the description will be the frozen description
  # if it exists or the current description otherwise. The frozen description is only set when an author is removed.
  def get_description(actor)
    if frozen_description && ((!actor && !published?) || unpublished_and_viewer_readable_only?(actor))
      frozen_description
    else
      description
    end
  end

  # Grants a collaborator write permissions on an Advisory
  # if they can :read the originating Repository.
  #
  # It will also grant on the workspace if it exists.
  def add_collaborator(subject, actor: author)
    return false unless T.must(repository).readable_by?(subject)

    grant(subject, :write)
    grant_on_workspace(subject, actor, :write)
    add_collaborator_added_event(subject, actor)
  end

  # Revokes a collaborator write permissions on an Advisory and
  # its Workspace if it exists
  sig { params(subject: T.any(User, Team), actor: T.nilable(T.any(User, Team))).void }
  def remove_collaborator(subject, actor: author)
    actor = author if actor.nil?

    # Always revoke user access to private fork/workspace and unsubscribe them from notifications.
    revoke_on_workspace(subject, actor)
    unsubscribe_collaborator(subject)

    # No-op if a user does not currently have access to the advisory (PVR author or collaborator).
    return unless user_is_pvd_submitter?(subject) || collaborator?(subject)

    if user_is_pvd_submitter?(subject)
      freeze_report!
      grant(subject, :read)
    else
      revoke(subject)
    end

    add_collaborator_removed_event(subject, actor)
  end

  def collaborator?(actor)
    actor_id_list = Authorization.service.direct_abilities_on_subject(subject: self, actor_type: actor.class.name, action: :write).pluck(:actor_id)

    actor_id_list.include?(actor.id)
  end

  def collaborators(actor_type:)
    actor_id_list = Authorization.service.direct_abilities_on_subject(subject: self, actor_type: actor_type, action: :write).pluck(:actor_id)
    case actor_type
    when "User"
      User.where(id: actor_id_list)
    else
      Team.where(id: actor_id_list)
    end
  end

  def collaborating_users
    collaborators(actor_type: "User")
  end

  def collaborating_teams
    collaborators(actor_type: "Team")
  end

  def collaborating_teams_visible_to_user(user)
    collaborating_teams.map { |team| team.visible_to?(user) ? team : nil }.compact
  end

  def user_is_pvd_submitter?(user)
    external? && user && user.id == author_id
  end
  # } ABILITY INTERFACE

  def freeze_report!
    update!(frozen_description: description, frozen_title: title)
  end

  delegate :nwo, :owner, :name_with_display_owner, :innersource_advisories_enabled?, to: :repository

  def global_id
    ghsa_id
  end

  def async_path_uri
    return @async_path_uri if defined?(@async_path_uri)

    @async_path_uri = async_repository.then { |x| T.must(x).async_owner }.then do
      URI_TEMPLATE.expand(
        owner:   T.must(T.must(repository).owner).display_login,
        name:    T.must(repository).name,
        ghsa_id: ghsa_id,
      )
    end
  end

  def to_param
    ghsa_id
  end

  enum :repo_advisory_type, %i{
    innersource
    open_source
  }

  def set_repo_advisory_type!
    return if repository.nil?
    self.repo_advisory_type = AdvisoryDB::Innersource.repo_authorized?(repo: repository) ? 0 : 1
  end

  # ADVISORY STATE HANDLING {
  enum :state, %i{
    open
    closed
    published
  }

  def set_accepted(actor: author)
    return if accepted?
    update!(accepted: true)
    add_report_accepted_event(actor)
  end

  def set_published(actor: author)
    return false unless open?
    return false if T.must(repository).empty?

    # set attribute directly,
    # in order for validations to trigger
    self.state = "published"

    if update(publisher: actor, published_at: Time.current)
      instrument_publish_event
      deliver_credit_notifications

      transaction do
        add_publish_event(actor)
        cleanup_workspace(actor)
      end

      true
    else
      self.state = "open"
      false
    end
  end

  def set_closed
    return false unless open?

    update(state: "closed",
           closed_at: Time.current)
  end

  def set_open
    return false unless closed?

    update(state: "open",
           closed_at: nil)
  end

  sig { returns(T::Boolean) }
  def form_filled_out?
    affected_products.size > 0 && affected_products.all? { |affected_product| affected_product.affected_versions.present? } && description.present? && !description_matches_template? && severity.present?
  end

  def publishable?
    open? &&
      form_filled_out? &&
      workspace_clean? &&
      !T.must(repository).empty? &&
      !innersource_advisories_enabled? # TODO(hawaiigal): Remove once we support publishing innersource advisories.
  end

  # } ADVISORY STATE HANDLING

  def async_permalink(include_host: true)
    async_repository.then do |repo|
      if repo
        "#{repo.permalink(include_host: include_host)}/security/advisories/#{ghsa_id}"
      else
        nil
      end
    end
  end

  def permalink(include_host: true)
    async_permalink(include_host: include_host).sync
  end

  FIELDS_FOR_REMOVED_PVR_AUTHOR = %i(
    ghsa_id
    url
    html_url
    summary
    description
    severity
    author
    identifiers
    state
    created_at
    submission
  ).freeze

  # Adjusts API payload to only display information relevant for a removed PVR author
  sig { params(payload: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
  def self.adjust_payload_fields_for_removed_pvr_author(payload)
    payload.each do |key, _value|
      payload[key] = nil unless FIELDS_FOR_REMOVED_PVR_AUTHOR.include?(key)
    end

    payload[:identifiers] = payload[:identifiers].select { |identifier| identifier[:type] == "GHSA" }
    payload
  end

  sig { params(payload: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
  def self.adjust_payload_for_innersource(payload)
    # cve_id and vulnerabilities.vulnerable_functions are required fields for the API response so just set them to blank.
    payload[:cve_id] = ""
    payload[:vulnerabilities]&.each { |vuln| vuln[:vulnerable_functions] = [] }

    payload
  end

  ADVISORY_DESCRIPTION_TEMPLATE =
    <<~DEFAULT
    ### Impact
    _What kind of vulnerability is it? Who is impacted?_

    ### Patches
    _Has the problem been patched? What versions should users upgrade to?_

    ### Workarounds
    _Is there a way for users to fix or remediate the vulnerability without upgrading?_

    ### References
    _Are there any links users can visit to find out more?_
    DEFAULT

  PVR_DESCRIPTION_TEMPLATE =
    <<~DEFAULT
    ### Summary
    _Short summary of the problem. Make the impact and severity as clear as possible. For example: An unsafe deserialization vulnerability allows any unauthenticated user to execute arbitrary code on the server._

    ### Details
    _Give all details on the vulnerability. Pointing to the incriminated source code is very helpful for the maintainer._

    ### PoC
    _Complete instructions, including specific configuration details, to reproduce the vulnerability._

    ### Impact
    _What kind of vulnerability is it? Who is impacted?_
    DEFAULT

  def self.description_template(pvr: false)
    if pvr
      PVR_DESCRIPTION_TEMPLATE
    else
      ADVISORY_DESCRIPTION_TEMPLATE
    end
  end

  def description_or_template(pvr: false)
    if description.blank?
      self.class.description_template(pvr: external? || pvr)
    else
      description
    end
  end

  def description_matches_template?
    # If the only changes are whitespace characters, it essentially matches the description template
    description&.delete(" \n\r") == self.class.description_template(pvr: external?)&.delete(" \n\r")
  end

  def description_does_not_match_template?
    errors.add(:description, "Description must have a different value than the template!") if description_matches_template?
  end

  def cannot_set_cvss_v3_and_cvss_v4_together
    errors.add(:base, "Only one CVSS vector can be saved") if !(cvss_v3.nil? || cvss_v4.nil?) && cvss_v3_changed? && cvss_v4_changed?
  end

  # event handling {
  def add_rename_event(actor, value_was, value_is)
    events.create(event: "renamed",
                  actor: actor,
                  changed_attribute: "title",
                  value_was: value_was,
                  value_is: value_is)

  end

  def add_state_event(actor, event)
    events.create(event: event,
                  actor: actor,
                  changed_attribute: "state")
  end

  def add_close_event(actor)
    add_state_event(actor, "closed")
  end

  def add_reopen_event(actor)
    add_state_event(actor, "reopened")
  end

  def add_publish_event(actor)
    add_state_event(actor, "published")
  end

  def add_report_accepted_event(actor)
    events.create(event: "accepted",
                  actor: actor,
                  changed_attribute: "report_state")
  end

  # Creates an event on the pseudo-attribute `review_state` that records
  # a decision by the security review team to publish, reject or withdraw
  # this advisory in our public security data.
  def add_review_state_event(event)
    events.create!(event: event,
                   actor: User.staff_user,
                   changed_attribute: "review_state")
  end

  def add_cve_requested_event(actor)
    events.create!(
      event: "cve_requested",
      actor: actor,
      changed_attribute: "cve_id",
    )
  end

  def add_cve_assigned_event(comment: nil)
    transaction do
      events.create!(
        event: "cve_assigned",
        actor: User.staff_user,
        changed_attribute: "cve_id",
        value_is: cve_id,
      )

      if comment.present?
        comments.create!(
          user: User.staff_user,
          body: comment,
        )
      end
    end
  end

  def add_cve_not_assigned_event(comment: nil)
    transaction do
      events.create!(
        event: "cve_not_assigned",
        actor: User.staff_user,
        changed_attribute: "cve_id",
      )

      if comment.present?
        comments.create!(
          user: User.staff_user,
          body: comment,
        )
      end
    end
  end

  def add_collaborator_added_event(subject, actor)
    events.create!(
      event: "collaborator_added",
      actor: actor,
      subject: subject,
      changed_attribute: "collaborator",
    )
  end

  def add_collaborator_removed_event(subject, actor)
    events.create!(
      event: "collaborator_removed",
      actor: actor,
      subject: subject,
      changed_attribute: "collaborator",
    )
  end

  def add_workspace_created_event(workspace_repository, actor = nil)
    events.create!(
      event: "workspace_created",
      actor: actor || User.staff_user,
      subject: workspace_repository,
      changed_attribute: "workspace_repository_id",
    )
  end

  def add_workspace_deleted_event(workspace_repository, actor = nil)
    events.create!(
      event: "workspace_deleted",
      actor: actor || User.staff_user,
      subject: workspace_repository,
      changed_attribute: "workspace_repository_id",
    )
  end
  # } event handling

  # WORKSPACE HELPERS {
  def recently_touched_branches(recent_threshold = 24.hours)
    ws_repository = workspace_repository
    return [] unless ws_repository && !ws_repository.creating?
    return @branches if defined?(@branches)

    ws_repository_id = ws_repository.id
    pushes = if ws_repository_id.present?
      GitHub.dogstats.time("repository_advisory.recently_touched_branches.pushes_query") do
        repositories_domain.pushes.latest(repository_id: ws_repository_id, pushed_at: recent_threshold.ago).to_a
      end
    else
      []
    end
    pushes.uniq!(&:ref)
    pushes.select! { |push| push.ref_is_branch? && push.after != GitHub::NULL_OID }

    branches = pushes.map { |p| { name: p.branch_name, pushed_at: p.pushed_at } }
    possible_ref_names = Git::Ref.permutations(branches.map { |b| b[:name] })
    with_existing_pulls = pull_requests.where(head_ref: possible_ref_names).
      collect(&:display_head_ref_name)

    @branches = branches.reject { |b| with_existing_pulls.include?(b[:name]) }
  end

  def pull_requests
    ws_repository = workspace_repository
    return [] unless ws_repository

    @pull_requests ||= ws_repository.pull_requests.joins(:issue).where(<<~SQL)
        issues.state = 'open'
        OR pull_requests.merged_at IS NOT NULL
      SQL
  end

  def open_pull_requests
    ws_repository = workspace_repository
    return [] unless ws_repository

    @open_pulls ||= ws_repository.pull_requests.open_pulls
  end

  def build_batch_merge(actor:)
    merge_method = open_pull_requests.first&.default_merge_method_for(actor) || T.must(repository).default_merge_method_for(actor)

    PullRequest::BatchMerge.new(
      repository,
      open_pull_requests,
      actor,
      message_title: pull_merge_message,
      method: merge_method,
    )
  end

  def enqueue_mergeable_updates
    open_pull_requests.each(&:enqueue_mergeable_update)
  end

  def cleanup_workspace(actor)
    ws_repository = workspace_repository
    ws_repository.remove(actor, instrument: false) if ws_repository
  end

  def workspace_clean?
    open_pull_requests.empty?
  end

  def pull_merge_message
    "Merge commit from fork"
  end
  # } WORKSPACE HELPERS

  # NOTIFICATION INTERFACE {
  # Used by Newsies to generate the Message-ID email header, which gives email
  # clients hints for how to thread related emails.
  def message_id
    MESSAGE_ID_TEMPLATE % {
      repo: name_with_display_owner,
      id: ghsa_id,
      host: GitHub.urls.host_name,
    }
  end

  # Used by Newsies to identify the NotificationSummary that describes the thread
  # containing email notifications for this repository advisory.
  #
  # Required for: NotificationsContent
  def get_notification_summary
    list = Newsies::List.new("Repository", repository_id)
    GitHub.newsies.web.find_rollup_summary_by_thread(list, self)
  end

  # as defined in Issue, RepositoryVulnerabilityAlert
  def destroy_notification_summary
    repo = repository || Repository.new.tap { |r| r.id = repository_id }
    GitHub.newsies.async_delete_all_for_thread(repo, self)
  end

  # Used by Newsies to update the rollup summary when specific attributes change
  # on the repository advisory. Implementation is taken directly from the
  # Summarizable module, modified only to include this model's particular
  # attributes of interest.
  #
  # Overridden for: NotificationsContent
  def update_notification_rollup(summary)
    suffix = summarizable_changed?(:title, :body) ? :changed : :unchanged
    GitHub.dogstats.increment("newsies.rollup", tags: ["type:#{suffix}"])

    summary.summarize_repository_advisory(self)
  end

  # Used by Newsies to allow users to unsubscribe from notifications for a
  # particular repository advisory.
  #
  # Required for: NotificationsContent
  def notifications_thread
    self
  end

  # Used by Newsies to set the From address for outgoing email notifications and
  # to prevent delivery to the author. This is how Issue notifications behave.
  #
  # Required for: NotificationsContent
  def notifications_author
    author
  end

  # Used by Newsies as a secondary grouping mechanism for notifications.
  # Currently, a notifications list may either point to a repository or a team.
  #
  # Required for: NotificationsContent
  def async_notifications_list
    async_repository
  end

  # Rather than using NotificationsContent#subscribe_and_notify as an
  # after_commit on: :create callback, we call this method instead because we
  # want to explicitly subscribe the original repository's admins rather than
  # any users or teams that are mentioned in the body of the repository
  # advisory.
  def subscribe_repository_admins_and_notify
    SubscribeAndNotifyJob.perform_later(self, {
      subscriber_reasons_and_ids: {
        manual: admin_user_ids_to_subscribe,
      },
      mentioned_user_ids: mentioned_admin_user_ids,
      mentioned_team_ids: mentioned_admin_team_ids,
      deliver_notifications: ::GitHub.send_notifications?,
    })
  end

  def unsubscribe_collaborator(subject)
    case subject
    when Team
      subscribable_team_members(subject).find_each(batch_size: GitHub.subscribed_users_batch_size) do |user|
        unsubscribe_user(user)
      end
    when User
      unsubscribe_user(subject)
    end
  end

  def unsubscribe_user(user)
    # We don't use the standard Newsies unsubscribe as we may be sending notifications to unsubscribed PVD sumbitters
    newsies_list = Newsies::List.to_object(repository)
    newsies_thread = Newsies::Thread.to_object(self, list: newsies_list)
    Newsies::ThreadSubscription.for_user(user.id).for_thread(newsies_thread).excluding_ignored.destroy_all
    Newsies::ThreadSubscriptionManager.async_notify_subscription_status_change(user.id, newsies_list, newsies_thread)
  end

  # This is automatically added to the context by which we parse the repository
  # advisory's description to detect mentioned users and teams. Along with
  # async_entity and async_body_context_user, the async_organization is merged
  # into the context and informs which mentioned users and teams are allowed to
  # be recognized and linked.
  #
  # See: GitHub::UserContent
  def async_organization
    async_repository.then { |x| T.must(x).async_organization }
  end

  def organization
    async_organization.sync
  end

  # Overrides: NotificationsContent#unsubscribable_users
  def unsubscribable_users(users)
    user_ids_to_preserve = admin_user_ids

    users.reject { |user| user_ids_to_preserve.include?(user.id) }
  end

  # Although Newsies will ultimately prevent notification delivery to users who
  # don't have read access to the repository advisory, here we're preventing
  # subscription in the first place by checking for read access proactively.
  #
  # Extends: SubscribableThread#subscribable_by?
  def subscribable_by?(user, *args)
    readable_by?(user) && super
  end

  def markdown_description
    MarkdownBody.new(description)
  end

  def mentionable_users_for(actor)
    admins = User.where(id: admin_user_ids)
    filter = Suggester::BlockedUserFilter.new(viewer: actor)
    (admins + collaborating_users).uniq.reject(&filter)
  end
  # } NOTIFICATION INTERFACE

  def timeline_for(viewer)
    timeline = if writable_by?(viewer)
      events + comments
    else
      events.after_publication + comments.after_publication
    end

    timeline.sort_by(&:created_at)
  end

  def create_comment(actor, body)
    comment = comments.build(user: actor, body: body)
    # Trigger custom validation to check whether the comment may be created
    # after the advisory publication.
    comment.save(context: :form_submission)
    comment
  end

  def comment_and_close(actor, body)
    comment = nil
    instrument = T.let(false, T::Boolean)

    if body.present?
      comment = comments.build(user: actor, body: body)
    end

    transaction do
      if set_closed
        instrument = true
        comment.save(context: :form_submission) if comment
        add_close_event(actor)
      end
    end

    if instrument
      GlobalInstrumenter.instrument("repository_advisory.close", {
        repository_advisory: self,
        actor: actor,
      })
    end

    comment
  end

  def comment_and_reopen(actor, body)
    comment = nil
    instrument = T.let(false, T::Boolean)

    if body.present?
      comment = comments.build(user: actor, body: body)
    end

    transaction do
      if set_open
        instrument = true
        comment.save(context: :form_submission) if comment
        add_reopen_event(actor)
      end
    end

    if instrument
      GlobalInstrumenter.instrument("repository_advisory.reopen", {
        repository_advisory: self,
        actor: actor,
      })
    end

    comment
  end

  def handle_update(actor, params)
    update_successful = T.let(false, T::Boolean)

    transaction do
      title_was = self.title
      description_was = self.description

      saved = self.update(params)

      if saved
        if self.title != title_was
          saved = self.add_rename_event(actor, title_was, self.title)

          # rollback transaction if event creation fails
          raise ActiveRecord::Rollback unless saved
        end

        add_user_content_edit!(description_was, self.description, actor)

        update_successful = true
      end
    end

    update_successful
  end

  def deliver_credit_notifications
    credits.preload(:recipient).each(&:deliver_notifications)
  end

  def instrument_publish_event
    instrument :publish
  end

  def instrument_open_event
    instrument :open

    #instrument webhook for pvr reporting only
    instrument :report if external? && !accepted?
  end

  def instrument_reopen_event
    instrument :reopen
  end

  def instrument_close_event
    instrument :close
  end

  def instrument_add_cwe(cwe)
    payload = event_payload
    payload[:added_cwe] = cwe.cwe_id

    instrument :update, payload
  end

  def instrument_remove_cwe(cwe)
    payload = event_payload
    payload[:removed_cwe] = cwe.cwe_id

    instrument :update, payload
  end

  EVENT_PAYLOAD_FIELDS = [:title, :body, :severity, :description, :cvss_v3, :cvss_v4, :cve_id].freeze

  def instrument_update_event
    payload = event_payload

    EVENT_PAYLOAD_FIELDS.each do |field|
      old_value, current_value = previous_changes[field]
      payload.merge!("#{field}_was": old_value, "#{field}": current_value) if previous_changes.include?(field)
    end

    instrument :update, payload
  end

  def instrument_update_event?
    EVENT_PAYLOAD_FIELDS.any? do |field|
      changes.include?(field) || previous_changes.include?(field)
    end
  end

  def event_context(prefix: "repository_advisory")
    {
      "#{prefix}".to_sym    => ghsa_id,
      "#{prefix}_id".to_sym => id,
    }
  end

  def event_payload
    payload = {
      repository_advisory: self,
      repo: repository,
    }

    if repository&.in_organization?
      payload[:org] = T.must(repository).organization
    end

    payload
  end

  def html_url
    "#{GitHub.url}#{async_path_uri.sync}"
  end

  def api_url
    return @api_url if defined?(@api_url)

    api_path_uri = async_repository.then { |x| T.must(x).async_owner }.then do
      API_URI_TEMPLATE.expand(
        owner:   T.must(T.must(repository).owner).display_login,
        name:    T.must(repository).name,
        ghsa_id: ghsa_id,
      )
    end
    @api_url = "#{GitHub.api_url}#{api_path_uri.sync}"
  end

  def identifiers
    array = T.let([{ value: ghsa_id, type: "GHSA" }], T::Array[Hash])
    if cve_id
      array << { value: cve_id, type: "CVE" }
    end
    array
  end

  def api_state
    return "withdrawn" if withdrawn_at
    return "triage" if in_triage?
    return "draft" if open?

    state
  end

  # TODO: rthorpeii - update to check scope field when that's added.
  def api_scope
    return "innersource" if T.must(repository).innersource_advisories_enabled?

    "open_source"
  end

  def in_triage?
    external? && !accepted? && open?
  end

  # This is NOT the inverse of the :external attribute! This is for GraphQL.
  def internal?
    true
  end

  # Typically, if a record is viewable by some user, that user also has access
  # to see that record's edit history. But repository advisories require some
  # special handling. While the repository advisory itself may be published and
  # viewable widely, the body attribute is treated as an initial, *internal*
  # comment. So the edit history of that internal comment should likewise be
  # kept internal, only viewable by collaborators on the repository advisory
  # itself.
  def async_viewer_can_read_user_content_edits?(viewer)
    async_writable_by?(viewer)
  end

  def viewer_can_read_user_content_edits?(viewer)
    return @viewer_can_read_user_content_edits if defined? @viewer_can_read_user_content_edits
    return false if viewer.nil?
    @viewer_can_read_user_content_edits = async_viewer_can_read_user_content_edits?(viewer).sync
  end

  def cve_request_pending!
    AdvisoryDB::RepositoryAdvisories::KV.store.set(cve_request_pending_key, "pending", expires: 72.hours.from_now)
  end

  def cve_request_pending?
    !!AdvisoryDB::RepositoryAdvisories::KV.store.get(cve_request_pending_key).value { nil }
  end

  def reset_cve_request
    AdvisoryDB::RepositoryAdvisories::KV.store.del(cve_request_pending_key)
  end

  def notify_socket_subscribers
    data = {
      timestamp: Time.now.to_i,
      wait: default_live_updates_wait,
      reason: "RepositoryAdvisory ##{id} updated",
    }

    channel = GitHub::WebSocket::Channels.repository_advisory(self)
    GitHub::WebSocket.notify_repository_advisory_channel(self, channel, data)
  end

  def body_version
    Digest::SHA256.hexdigest(body_version_attributes)
  end

  def og_image_url
    open_graph = OpenGraph.new(self,
      cache_key_parts: [
        updated_at,
        T.must(repository).owner_id,
        T.must(repository).private?,
        affected_products.to_json(only: [
          :affected_versions,
          :ecosystem,
          :id,
          :package,
          :patches,
          :repository_advisory_id
        ])
      ]
    )
    open_graph.og_image_url
  end

  def label
    if external? && !accepted?
      "vulnerability report"
    elsif !published?
      "draft advisory"
    else
      "advisory"
    end
  end

  class ApiInvalidInputError < StandardError; end
  class ApiForbbidenActionError < StandardError; end

  def self.build_from_params(data, repo:, actor:, external: false)
    return unless data && repo && actor

    # check severity vs. CVSS
    if data["severity"].present? && data["cvss_vector_string"].present?
      raise ApiInvalidInputError.new("Cannot define both severity and cvss_vector_string")
    end

    # set up basic parameters in new advisory
    advisory = repo.repository_advisories.new(
      author_id: actor.id,
      title: data["summary"],
      description: data["description"],
      cve_id: data["cve_id"],
      external: external,
    )

    if data["cvss_vector_string"].present?
      # Rigorous CVSS vector check will be done in the model validation.
      if data["cvss_vector_string"] =~ CVSS_V4_PATTERN
        advisory.cvss_v4 = data["cvss_vector_string"]
      else
        advisory.cvss_v3 = data["cvss_vector_string"]
      end
    end

    severity = if data.key?("cvss_vector_string")
      advisory.severity_from_cvss(data["cvss_vector_string"])
    else
      data["severity"] == "medium" ? "moderate" : data["severity"]
    end

    advisory.severity = severity

    # create CWEs
    advisory.cwes = CWE.where(cwe_id: data["cwe_ids"])

    # create vulnerabilities
    advisory.affected_products = data["vulnerabilities"]&.map do |product|
      RepositoryAdvisoryAffectedProduct.new({
        ecosystem: product.dig("package", "ecosystem"),
        package: product.dig("package", "name"),
        affected_versions: product["vulnerable_version_range"],
        patches: product["patched_versions"],
      })
    end&.compact

    # Create credits, unless innersource advisories is enabled on the repo, in which case ignore them.
    unless repo.innersource_advisories_enabled?
      credits = data["credits"]&.map do |credit|
        recipient = User.find_by(login: credit["login"])

        unless recipient
          raise ApiInvalidInputError.new("User '#{credit["login"]}' not found, credit cannot be created")
        end

        unless recipient.user?
          raise ApiInvalidInputError.new("Cannot create credit for '#{credit["login"]}', credits can only be given to users")
        end

        {
          creator_id: actor.id,
          recipient_id: recipient.id,
          credit_type: credit["type"],
        }
      end&.compact
    end

    # Wrapped in a transaction so we can avoid running advisory after-commit callbacks until
    # credits are saved for a clean advisory POST
    RepositoryAdvisory.transaction do
      advisory.save!
      advisory.credits.create!(credits) if credits
      advisory.add_and_credit_pvr_author(actor) if external
    end

    advisory.api_dogstats_increment :create

    advisory
  rescue ActiveRecord::RecordInvalid => e
    RepositoryAdvisory.raise_api_invalid_input_error(e)
  end

  def update_from_params(data, actor:)
    if data["severity"].present? && data["cvss_vector_string"].present?
      raise ApiInvalidInputError.new("Cannot define both severity and cvss_vector_string")
    end

    filtered_metadata = data.slice("description", "cve_id")
    filtered_metadata["title"] = data["summary"] if data.key?("summary")

    if data.key?("cvss_vector_string")
      # Rigorous CVSS vector check will be done in the model validation.
      if data["cvss_vector_string"] =~ CVSS_V4_PATTERN
        filtered_metadata["cvss_v4"] = data["cvss_vector_string"]
        filtered_metadata["cvss_v3"] = nil
      else
        filtered_metadata["cvss_v3"] = data["cvss_vector_string"]
        filtered_metadata["cvss_v4"] = nil
      end
      filtered_metadata["severity"] = severity_from_cvss(data["cvss_vector_string"])
    end

    if data.key?("severity")
      filtered_metadata["severity"] = data["severity"] == "medium" ? "moderate" : data["severity"]
      filtered_metadata["cvss_v3"] = nil
      filtered_metadata["cvss_v4"] = nil
    end

    state_change = T.let(nil, T.nilable(Symbol))

    transaction do
      if filtered_metadata
        handle_update(actor, filtered_metadata)
      end

      self.cwes = CWE.where(cwe_id: data["cwe_ids"]) if data["cwe_ids"]

      if data["vulnerabilities"]
        if data["vulnerabilities"].empty?
          raise ApiInvalidInputError.new("Advisory must have at least one vulnerability")
        end

        vulns = data["vulnerabilities"].map do |product|
          {
            ecosystem: product.dig("package", "ecosystem"),
            package: product.dig("package", "name"),
            affected_versions: product["vulnerable_version_range"],
            patches: product["patched_versions"],
          }
        end.compact

        self.affected_products.destroy_all
        self.affected_products.create!(vulns)
      end

      # Skip credits if innersource advisories are enabled on the repository.
      bulk_update_credits(data["credits"], actor: actor) if data["credits"] unless innersource_advisories_enabled?

      bulk_update_collaborators(data["collaborating_users"], actor: actor) if data["collaborating_users"]
      bulk_update_collaborators(data["collaborating_teams"], actor: actor, collaborator_type: :team) if data["collaborating_teams"]

      state_change = api_state_change(data["state"], actor: actor) if data["state"]
    end

    api_dogstats_increment state_change if state_change
    api_dogstats_increment :update

    self
  rescue ActiveRecord::RecordInvalid => e
    RepositoryAdvisory.raise_api_invalid_input_error(e)
  end

  def self.raise_api_invalid_input_error(error)
    error_message = case error.message
    when /cvss v3/i
      "Not a valid CVSS 3 vector string"
    when /cvss v4/i
      "Not a valid CVSS 4 vector string"
    when /CVE identifier/i
      "Not a valid CVE ID"
    when /Affected versions/i
      "Must have valid affected versions on published advisory"
    else
      "There was a problem validating the advisory"
    end

    raise ApiInvalidInputError.new(error_message)
  end

  def api_dogstats_increment(key)
    GitHub.dogstats.increment("repository_advisory.api.#{key}")
  end

  # Adds a pvr author as collaborator, and creates a reporter credit for them
  # Recommended to be run in a RepositoryAdvisory.transaction block
  def add_and_credit_pvr_author(author)
    # `add_collaborator` may return false or nil for acceptable
    # reasons, but the underlying model will raise an exception
    # (triggering a rollback) if the read ability cannot be granted
    self.add_collaborator(author, actor: author)

    self.credits.create!(
      creator_id: author,
      recipient: author,
      credit_type: :reporter
    )
  end

  def actor_can_collaborate?(actor)
    return false unless T.must(repository).readable_by?(actor)

    case actor
    when Team
      # The team being added must belong to the current organization.
      organization && (organization == actor.organization)
    when User
      # Any user can be added (so long as they can see the repository).
      true
    else
      # We shouldn't get here; only a team or user can be a collaborator.
      false
    end
  end

  private

  def body_version_attributes
    EVENT_PAYLOAD_FIELDS.map { |field| public_send(field) }.to_s
  end

  def set_ghsa_id!
    self.ghsa_id = AdvisoryDB::GhsaIdGenerator.generate_unique_ghsa_id
  end

  def set_owner_id!
    self.owner_id = T.must(repository).owner_id
  end

  def set_only_one_cvss_version!
    if cvss_v4_changed?
      self.cvss_v3 = nil
    elsif cvss_v3_changed?
      self.cvss_v4 = nil
    end
  end

  def revoke_on_workspace(subject, actor)
    ws_repository = workspace_repository
    return unless ws_repository

    if subject.is_a?(Team)
      ws_repository.remove_team(subject)
    else
      ws_repository.remove_vulnerability_reporter(subject)
      ws_repository.remove_member(subject)

      repository_invitation = RepositoryInvitation.find_by(invitee_id: subject.id, repository_id: ws_repository.id)
      repository_invitation.cancel!(actor: actor) if repository_invitation
    end
  end

  def grant_on_workspace(subject, actor, action)
    ws_repository = workspace_repository
    return unless ws_repository

    if user_is_pvd_submitter?(subject)
      ws_repository.add_vulnerability_reporter(subject)
    elsif subject.is_a?(Team)
      ws_repository.add_team(subject, action: action)
    elsif subject == actor
      ws_repository.add_member(subject, action: action)
    else
      RepositoryInvitation.invite_to_repo(subject, actor, ws_repository, action: action)
    end
  end

  # Get IDs of all users with admin access to the original repository. This
  # admin access may be granted directly on the repository or indirectly via a
  # team or the repository's organization. If the repository is personally
  # owned, the owner's ID is included as well.
  def admin_user_ids
    T.must(repository).user_ids_with_privileged_access(min_action: :admin)
  end

  def admin_user_ids_to_subscribe
    SecurityAlert.user_ids_subscribed_to_security_alerts(repository, admin_user_ids)
  end

  # Get IDs of all users mentioned in the description of this repository
  # advisory, so long as those mentioned users are *also* authorized to see the
  # repository advisory. Currently, that means that the user must also be an
  # admin on the repository advisory's parent repository.
  #
  # In reality, Newsie's internals would _eventually_ block notifications for
  # mentioned users that that lack admin access to the repository advisory via
  # Newsies::PolicyManager#reason_to_stop_delivery? returning
  # :thread_unreadable, but we want to be especially certain for sensitive
  # security information that no user is ever subscribed without having access.
  def mentioned_admin_user_ids
    T.must(repository).user_ids_with_privileged_access(
      min_action: :admin,
      actor_ids_filter: mentioned_users.map(&:id),
    )
  end

  # Get IDs of all teams mentioned in the description of this repository
  # advisory, so long as those mentioned teams are *also* authorized to see the
  # repository advisory. Currently, that means that the team must also have
  # admin access to the repository advisory's parent repository.
  def mentioned_admin_team_ids
    T.must(repository).actor_ids(
      type: Team,
      min_action: :admin,
      actor_ids_filter: mentioned_teams.map(&:id),
    )
  end

  def cve_request_pending_key
    "repository_advisory:#{ghsa_id}:cve_request_pending"
  end

  def affected_products_must_have_affected_versions
    if affected_products.any? { |affected_product| affected_product.affected_versions.blank? }
      errors.add(:affected_products, "all must have affected versions")
    end
  end

  def destroy_or_nullify_advisory_credits
    DestroyOrNullifyAdvisoryCreditsJob.perform_later(id)
  end

  def bulk_update_collaborators(data, collaborator_type: :user, actor:)
    unless adminable_by?(actor)
      raise ApiForbbidenActionError.new("Cannot update advisory collaborators unless you have administrative/security management rights")
    end

    collaborators = []
    data.each do |login|
      if collaborator_type == :user
        collaborator = User.find_by(login: login)
      else
        collaborator = organization.teams.where(slug: login).first
      end

      unless collaborator && actor_can_collaborate?(collaborator)
        collaborator_class_name = collaborator_type == :team ? "Team" : "User"
        collaborator_field_name = collaborator_type == :team ? "collaborating_teams" : "collaborating_users"
        raise ApiInvalidInputError.new("#{collaborator_class_name} '#{login}' not found, #{collaborator_field_name} cannot be modified")
      end

      collaborators.append(collaborator)
    end

    requested_collaborators = Set.new(collaborators)
    existing_collaborators = Set.new(collaborator_type == :team ? self.collaborating_teams : self.collaborating_users)

    new_collaborators = requested_collaborators - existing_collaborators
    removed_collaborators = existing_collaborators - requested_collaborators

    new_collaborators.each do |collaborator|
      self.add_collaborator(collaborator, actor: actor)
    end

    removed_collaborators.each do |collaborator|
      self.remove_collaborator(collaborator, actor: actor)
    end
  end

  def bulk_update_credits(data, actor:)
    # A hash of recipient ids to credit types that is used for easily
    # updating and creating new advisory credits
    user_id_to_credit_type = {}

    data.each do |credit|
      recipient = User.find_by(login: credit["login"])

      unless recipient
        raise ApiInvalidInputError.new("User '#{credit["login"]}' not found, credits cannot be modified")
      end

      unless recipient.user?
        raise ApiInvalidInputError.new("Cannot create credit for '#{credit["login"]}', credits can only be given to users")
      end

      user_id_to_credit_type[recipient.id] = credit["type"]
    end

    new_recipient_ids = Set.new(user_id_to_credit_type.keys)
    existing_recipient_ids = Set.new(self.credits.pluck(:recipient_id))

    change = new_recipient_ids & existing_recipient_ids
    add = new_recipient_ids - existing_recipient_ids
    delete = existing_recipient_ids - new_recipient_ids

    self.credits.where(recipient_id: delete).destroy_all

    add.each do |id|
      self.credits.create!(
        creator_id: actor.id,
        recipient_id: id,
        credit_type: user_id_to_credit_type[id]
      )
    end

    change.each do |id|
      advisory_credit = self.credits.find_by(recipient_id: id)

      next if !advisory_credit || advisory_credit.credit_type == user_id_to_credit_type[id]

      advisory_credit.update(credit_type: user_id_to_credit_type[id])
    end
  end

  # This method returns a key after a successful state change describing the action
  # done by this state change. We then use it to increment datadog metrics after the transaction is complete.
  def api_state_change(state, actor:)
    unless adminable_by?(actor)
      raise ApiForbbidenActionError.new("Cannot update advisory state unless you have administrative/security management rights")
    end

    case state
    when "draft"
      if published?
        raise ApiInvalidInputError.new("Cannot return published advisory to draft state")
      end

      if in_triage?
        set_accepted(actor: actor)
        :pvr_accepted
      else
        comment_and_reopen(actor, nil)
        :reopened
      end
    when "published"
      unless publishable?
        raise ApiInvalidInputError.new("Advisory is not publishable. Must be open with at least one affected product, a description, a severity, and a workspace with no open pull requests.")
      end

      set_published(actor: actor)
      :published
    when "closed"
      if published?
        raise ApiInvalidInputError.new("Cannot close published advisory")
      end

      comment_and_close(actor, nil)
      :closed
    end
  end
end
