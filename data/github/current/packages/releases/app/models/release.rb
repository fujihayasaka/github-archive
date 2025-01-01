# typed: true
# frozen_string_literal: true
#
# A flexible method for distributing a piece of software. A Release can be
# many things:
#
# - A mini blog post, describing new features, bug fixes, etc.
# - ... coupled with a Git Ref object representing the Tag.
# - ... optionally coupled with several downloadable files (.pkg, .jar, etc)
#
# - A way to highlight important Tags. Once they're promoted to a Release they
#   can be highlighted and broadcasted.
#
# - An alternative to PGP for identifying an author + tag as authentic.
#
class Release < ApplicationRecord::Domain::Repositories # rubocop:todo GitHub/DatabaseModelsShouldHaveTests
  extend GitHub::Encoding

  include GitHub::Relay::GlobalIdentification
  include GitHub::UserContent
  include GitHub::UTF8
  include Instrumentation::Model
  include NotificationsContent::WithoutCallbacks
  include Reaction::Subject::RepositoryContext
  include Reactable
  include LegacyImportable
  include Releases::IRelease

  include ::Permissions::Attributes::Wrapper
  self.permissions_wrapper_class = ::Permissions::Attributes::Release

  PER_PAGE = 10
  COMMITS_LIMIT = 5_000
  GIT_TAGS_BATCH_SIZE = 50
  MENTION_LIMIT = 200
  BODY_CHAR_LIMIT = 125_000
  RELEASE_PIPELINE_CACHE_VERSION = 1
  DEFAULT_SHORT_DESCRIPTION_LENGTH = 200
  UPLOADED_ASSET_DISPLAY_LIMIT = 10

  belongs_to :repository
  destroy_in_background_with :repository

  def entity
    repository
  end

  def async_entity
    async_repository
  end

  belongs_to :author, class_name: "User"
  has_one :repository_action_release, dependent: :destroy
  has_one :repository_action, through: :repository_action_release

  has_one :repository_stack_release, dependent: :destroy
  has_one :repository_stack, through: :repository_stack_release
  has_one :discussion, dependent: :destroy

  has_many :reactions, as: :subject

  has_many :release_assets, inverse_of: :release
  destroy_dependents_in_background :release_assets

  has_many :uploaded_assets, -> { T.bind(self, T.untyped); uploaded }, class_name: "ReleaseAsset", inverse_of: :release

  has_many :package_versions, class_name: "Registry::PackageVersion"
  has_many :packages, through: :package_versions

  has_many :release_mentions
  destroy_dependents_in_background :release_mentions
  has_many :mentions, through: :release_mentions, disable_joins: true, source: :user
  before_save :populate_mentions # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  has_one :repository_latest_release, dependent: :destroy

  accepts_nested_attributes_for :release_assets,
    reject_if: proc { |attributes| attributes[:id].blank? },
    allow_destroy: true

  accepts_nested_attributes_for :package_versions,
    reject_if: proc { |attributes| attributes[:id].blank? },
    allow_destroy: true

  accepts_nested_attributes_for :repository_action_release, update_only: true
  accepts_nested_attributes_for :repository_action, update_only: true

  accepts_nested_attributes_for :repository_stack_release, update_only: true
  accepts_nested_attributes_for :repository_stack, update_only: true

  validates_presence_of :tag_name
  validates_uniqueness_of :tag_name, scope: :repository_id, allow_nil: true, case_sensitive: true
  validate :tag_name_is_well_formed
  validate :author_access, on: :create, unless: :importing?
  validate :published_releases_are_tagged
  validate :target_commitish_is_valid, unless: :importing?
  validate :tag_is_well_formed
  validates :name, bytesize: { maximum: 1024 }
  validates_length_of :body, maximum: BODY_CHAR_LIMIT
  validate :valid_for_latest, if: :make_latest

  before_save :backdate_if_tagged # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  before_validation :create_tag_on_publish
  before_validation :fake_tag_if_draft

  before_save  :set_published_at # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_publish, if: :trigger_publish_event? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_first_publish, if: :trigger_first_publish_event?  # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_creation, on: :create # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_update, on: :update # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_destroy, on: :destroy # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_unpublish, on: :update # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_prerelease, on: [:create, :update] # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_release_create, on: :create # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_release_update, on: :update # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :synchronize_search_index, on: [:create, :update] # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :remove_from_search_index, on: :destroy # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :clear_latest_if_no_longer_valid, on: [:create, :update] # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :set_as_latest, on: [:create, :update], if: :make_latest # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  before_destroy :generate_webhook_payload # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :queue_webhook_delivery, on: :destroy # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  after_destroy :destroy_notification_summary # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  enum :state, {
    published: 0,
    draft: 1,
  }

  def draft
    draft?
  end

  scope :drafted, -> { draft }
  scope :latest, -> { order("created_at DESC, updated_at DESC") }

  attribute :name, StringFromBinary.new
  attribute :tag_name, StringFromBinary.new
  attribute :pending_tag, StringFromBinary.new

  validates :pending_tag, bytesize: { maximum: 1024 }
  validates :tag_name, bytesize: { maximum: 1024 }

  attr_accessor :reflog_data, :discussion_category_id
  attr_writer :actor
  attr_reader :generated_notes_state
  attr_accessor :make_latest
  attr_accessor :is_body_truncated

  GENERATED_RELEASE_NOTE_STATES = %w(INITIAL GENERATED GENERATED-AND-EDITED).freeze

  def generated_notes_state=(value)
    value = value.to_s.upcase
    return unless GENERATED_RELEASE_NOTE_STATES.include?(value)
    @generated_notes_state = value
  end

  # Public: list releases, given a repo id.
  def self.for_repo(repo_id, include_drafts: false, limit: 30)
    releases = where(repository_id: repo_id).limit(limit)
    releases = releases.published unless include_drafts
    releases
  end

  sig { params(repository: ::Repository, tag_ref: String).returns(T.nilable(::Releases::IRelease)) }
  def self.build_tag_ref(repository, tag_ref)
    tag = repository.tags.find(tag_ref)
    from_tag tag
  end

  # Public: Retrieve a page of tags as releases.
  #
  # options - Hash of paging options:
  #   :after - Optional string tag name of the last tag on the previous page.
  #   :limit - Optional number of releases in a single page (default: 10).
  #
  # Returns an Array of Release objects for the given page in the order requested.
  def self.page_tags(repository, options = {})
    options = { limit: PER_PAGE }.merge(options)
    tags = repository.sorted_tags.page(options)

    from_tags(repository, tags)
  end

  def self.pagination_for_tags(repository, after, limit, num_releases)
    repository.sorted_tags.paginate(after, limit, num_releases)
  end

  # Public: Retrieve a page of releases.
  #
  # options - Hash of options:
  #   :page - Optional base-1 number of the page to display (default: 1).
  #   :limit - Optional number of releases in a single page (default: 10).
  #   :filter_phrase - Optional string to filter releases that include that text somewhere.
  #   :allow_drafts - Optional boolean to include draft releases. By default, drafts are not included.
  #
  # Returns a Search Results object that contains the items and details for the given page.
  def self.query_releases(repository, current_user, options = {})
    options = { limit: PER_PAGE, page: 1 }.merge(options)

    filter_phrase = Search::Queries::ReleaseQuery.stringify(
      Search::Queries::ReleaseQuery.normalize(
      Search::Queries::ReleaseQuery.parse(options[:filter_phrase])))

    query = ::Search::Queries::ReleaseQuery.new \
      repository: repository,
      current_user: current_user,
      phrase: filter_phrase,
      page: options[:page],
      per_page: options[:limit],
      highlight: true,
      allow_drafts: options[:allow_drafts]

    query.execute
  end

  # Internal: Convert a list of tags to Release objects for the given repository.
  #
  # repository - The Repository.
  # refs       - A Git::Ref::Collection of the Repository's tags.
  #
  # Returns an Array of Release objects in the order the refs are given.
  def self.from_tags(repository, refs)
    cache = {} # "tag name" => Release.new(....)

    prefill_from_releases(cache, repository, refs)
    prefill_from_tags(cache, repository, refs)
    prefill_verification_status(refs.map(&:target))

    refs.map do |ref|
      release = cache[ref.name]
      release.set_tag(ref)
      release
    end
  end

  # Preload signature verification and status for tags/commits.
  def self.prefill_verification_status(refs)
    targets = refs.group_by(&:class)

    # Prefill signatures on tags and commits separately to avoid GitSigning::NPlusOne error
    Promise.all(targets[Tag].map(&:async_signature)).sync if targets.key?(Tag)
    Promise.all(targets[Commit].map(&:async_signature)).sync if targets.key?(Commit)
    tags_and_commits = targets.values_at(Tag, Commit).flatten.compact
    Promise.all(tags_and_commits.map(&:async_verification_status)).sync
  end

  def self.prefill_from_releases(cache, repository, refs)
    filtered_refs = refs.map(&:name)
    releases = repository.releases.published.
      where(tag_name: filtered_refs)

    releases.each do |rel|
      cache[rel.tag_name.b] = rel
    end
  end

  def self.prefill_from_tags(cache, repository, refs)
    # get the refs that don't have releases already
    tags = refs.select { |ref| ref.exist? && !cache[ref.name] }
    return if tags.blank?

    # dereference the ref to its commit or tag object
    target_oids = tags.map(&:target_oid)
    targets = repository.objects.read(target_oids)

    # get the author emails for a bulk user query
    author_emails = targets.map { |t| t.try(:author_email).to_s.strip }
    author_emails.delete_if(&:blank?)

    business = repository.enterprise_managed_business if repository.is_enterprise_managed?
    users = User.find_by_emails(author_emails, business: business)

    # build the Release from the tag ref and target.
    tags.each_with_index do |tag, idx|
      target = targets[idx]
      email = target.try(:author_email).to_s.downcase
      cache[tag.name] = from_ref_and_target(tag, target, users[email])
    end
  end

  # Preload users for releases and release assets.  Do both since they are
  # usually loaded right by each other.
  #
  # prefill_assets_downloads_counters - Whether to prefill downloads from slotted counters table or not.
  #   We don't necessarily need them everywhere, for example we don't show them in the UI at all.
  #   So we can save some DB queries.
  def self.prefill_releases_and_assets(repository, releases, assets, prefill_assets_downloads_counters: true)
    GitHub::PrefillAssociations.prefill_associations(releases, [:author, :discussion, :repository], available_records: [repository])
    SlottedCounterService.prefill(assets) if prefill_assets_downloads_counters
    GitHub::PrefillAssociations.prefill_associations(assets, [:repository, :uploader], available_records: [repository])
  end

  # Internal: Initialize the tag property of the releases in a gitrpc batch operation.
  #
  # releases - An Array of Release objects.
  # repository - The Repository to which the releases belong.
  def self.prefill_tags(releases, repository)
    # using async_find in a promise to batch the requests to gitrpc
    Promise.all(releases.map do |release|
      if release.tag_name.present?
        repository.tags.async_find(release.tag_name).then do |tag|
          release.set_tag(tag) if tag
        end
      end
    end).sync
  end

  # Build a new, unsaved Release from a tag Ref object.
  #
  # ref - Ref object.
  #
  # Returns a Release.
  def self.from_tag(ref)
    return unless ref && ref.exist?

    target = ref.target
    from_ref_and_target(ref, target, target.try(:author))
  end

  def self.from_ref_and_target(ref, target, author)
    name, body = tag_title_and_body(ref, target: target)

    target_date = target.try(:date)
    Release.new(
      repository: ref.repository,
      name: prefix_with_tag_name(name, ref.name),
      body: body.to_s,
      author: author,
      tag_name: ref.name,
      created_at: target_date && target_date.localtime,
    )
  end

  def self.prefix_with_tag_name(title, tag_name)
    if !title.b[tag_name.b]
      "#{tag_name.b}: #{title.b}".dup
    else
      title
    end.force_encoding("utf-8").scrub!
  end

  def self.tag_title_and_body(ref, target: nil)
    return if ref.nil?
    target ||= ref.target
    name, body = if target.respond_to?(:message_body_text)
      if target.message_body_text? && !target.truncated?
        [target.short_message_text, target.message_body_text]
      else
        [ref.name, target.short_message_text]
      end
    else
      ref.name
    end
  end

  # Only non-negative emotions are allowed through the Reactable interface for a release
  UNSUPPORTED_EMOTIONS = ["-1", "thinking_face"]
  def self.emotions
    @emotions ||= super.reject { |e| UNSUPPORTED_EMOTIONS.include?(e.content) }
  end

  def can_link_discussion?
    repository&.discussions_active? &&
     (self.new_record? || self.draft?)
  end

  def is_latest?(user)
    T.must(repository).latest_release(user) == self
  end

  def created_at_for_display
    self.created_at || self.target_commit.created_at
  end

  def date_for_display
    # this class is sometimes used to represent a tag, and tags can be missing both of these values
    ((published? && published_at) || created_at)&.utc
  end

  # Public: Updates the model's attributes from a release params hash in a
  # Rails controller.
  #
  #     def update
  #       @release = Release.find params[:id]
  #       @release.with_params params[:release]
  #       @release.save!
  #     end
  #
  # params - A Hash of parameters.  Could be a StrongParams with nothing permitted
  #          since the keys are accessed by name.
  #
  # Returns nothing.
  def with_params(params)
    params.slice(:draft, :tag_name, :name, :body, :prerelease, :target_commitish, :generated_notes_state, :make_latest).each do |key, value|
      send("#{key}=", value) unless value.nil?
    end

    if attribs = params[:release_assets_attributes]
      update_attribs = attribs.map do |release_asset|
        release_asset.slice("name", "id", "_destroy")
      end
      self.release_assets_attributes = update_attribs
    end

    if attribs = params[:package_versions_attributes]
      update_attribs = attribs.map do |registry_package_version|
        registry_package_version.slice("id", "_destroy")
      end
      self.package_versions_attributes = update_attribs
    end

    if attribs = params[:repository_action_release_attributes]
      if repo_action = repository&.action_at_root
        attribs[:repository_action_id] = repo_action.id
        self.repository_action = repo_action
      end

      self.repository_action_release_attributes = attribs.slice(:repository_action_id, :published_on_marketplace)

      if action_attribs = params[:repository_action_attributes]
        self.repository_action_attributes = action_attribs.slice(:security_email)
      end
    end

    if attribs = params[:repository_stack_release_attributes]
      self.repository_stack_release_attributes = attribs.slice(:repository_stack_id, :published_on_marketplace)

      if stack_attribs = params[:repository_stack_attributes]
        self.repository_stack_attributes = stack_attribs.slice(:security_email)
      end
    end

  end

  def can_add_discussion?(repo)
    !self.discussion && !self.draft?
  end

  def async_readable_by?(actor)
    async_repository.then do |repo|
      if draft?
        repo&.resources.contents.async_writable_by?(actor)
      else
        repo&.resources.contents.async_readable_by?(actor)
      end
    end
  end

  # Public: Whether the given user can see this release.
  def readable_by?(actor)
    async_readable_by?(actor).sync
  end

  # Public: Is this Release tagged as well?
  #
  # force - Force a check of the tag despite cache.
  #
  # Returns a boolean.
  def tagged?(force = false)
    !tag(force).nil?
  end

  # Public: The Git tag ref association.
  #
  # force - Force a check despite cache
  #
  # Returns a Ref object.
  def tag(force = false)
    return nil if tag_name.blank?
    return @tag if defined?(@tag) && @tag && !force

    set_tag T.must(repository).tags.find((draft? && pending_tag) ? pending_tag.b : tag_name.b)
  end

  # Public: Gets the annotated tag if it exists.
  def annotated_tag
    tag.target if tag&.target.is_a?(::Tag)
  end

  # Public: Gets the tag's target if it exists.
  #
  # Returns a Commit/Tag, or nil.
  def tag_target
    tag.target if tag
  end

  def tag_name=(value)
    set_tag(nil)
    self.pending_tag = value if published?
    write_attribute(:tag_name, value)
  end

  def tag_name
    self[:tag_name].dup.force_encoding("UTF-8").scrub! if self[:tag_name]
  end

  # Internal: Set the tag Ref object for this release
  # This is used by Release.page_tags as an optimization to prevent
  # potentially hitting rpc/cache yet again even though we already
  # have the tag Ref object loaded and ready to use.
  #
  # tag - The tag Ref object for this release
  #
  # Returns nothing.
  def set_tag(tag)
    @tag_title = @tag_body = nil
    @tag = tag
  end

  def tag_name_or_target_commitish
    tag_name || abbreviated_target_commitish
  end

  # Public: Gets the default title from the tag.
  def tag_title
    @tag_title ||= begin
      title, body = self.class.tag_title_and_body(tag)
      @tag_body = body.to_s
      title.to_s
    end
  end

  # Public: Gets the default body from the tag.
  def tag_body
    @tag_body ||= begin
      title, body = self.class.tag_title_and_body(tag)
      @tag_title = title.to_s
      body.to_s
    end
  end

  # Draft releases are not yet published to the world. They can be
  # viewed/edited by repo owners only.
  def draft=(value)
    value = (value.to_i > 0) if value.is_a?(String)
    self.state = value ? :draft : :published
  end

  # Public: Does this Release have release notes? This is a good way to know
  # that the Release is persisted in the DB.
  #
  # Returns true if Release if there are notes to view.
  def notes?
    !new_record? && !body.blank?
  end

  # Public: Should this release be displayed, or rendered as just a tag?
  def viewable?
    !new_record?
  end

  # Public: Absolute permalink URL for this release.
  #
  # include_host - Turn off the `GitHub.url` host in the url. (default true)
  #                release.permalink(include_host: false) => `/github/github/releases/tag/v0.0.1`
  #
  # Returns a String
  def permalink(include_host: true)
    return nil unless tag_name && repo = repository
    "#{repo.permalink(include_host: include_host)}/releases/tag/#{UrlHelper.escape_branch(tag_name)}"
  end

  def target_commitish
    return read_attribute(:target_commitish) if destroyed?
    read_attribute(:target_commitish) || write_attribute(:target_commitish, T.must(repository).default_branch)
  end

  def abbreviated_target_commitish
    c = target_commitish.to_s
    GitRPC::Util.valid_full_oid?(c) ? c[0, 7] : c
  end

  def target_commitish=(value)
    write_attribute(:target_commitish, value.present? ? value.to_s : nil)
  end

  # Ref to the release target.
  # Tag name if the release is linked to an existing tag,
  # falls back to target commitish is there is no tag (i.e. a draft release)
  def current_target
    self.tag&.name || target_commitish
  end

  def target_commit
    if @target_commit.nil?
      @target_commit = target_commit! || false
    end
    @target_commit || nil
  end

  def target_commit!
    return unless repo = repository

    if ref = repo.heads.find(target_commitish)
      ref.target
    else
      repo.commits.find(target_commitish)
    end
  rescue RepositoryObjectsCollection::InvalidObjectId, GitRPC::ObjectMissing
  end

  # Public: Gets the most recent commits from the target commit.
  #
  # limit - The Integer max number of commits to return.
  #
  # Returns an Array of Commit objects.
  def target_commits(limit = 10)
    return [] unless oid = target_commit&.oid
    T.must(repository).commits.history(oid, limit)
  end

  def async_tag_commit
    async_repository.then do |repository|
      repository.async_network.then do
        tag&.commit
      end
    end
  end

  def comparison
    return unless tagged?
    return unless base_branch = target_commitish
    return unless base_oid = target_commit.try(:oid)
    return unless tag_oid = tag.target_oid

    repo = T.must(repository)
    ab = repo.rpc.ahead_behind(base_oid, tag_oid)
    return unless ab[tag_oid]

    ahead, behind = ab[tag_oid]
    return if ahead == 0 && behind == 0

    {
      "base_branch" => base_branch,
      "commit_range" => "#{tag_name}...#{base_branch}",
      "ahead" => ahead,
      "behind" => behind,
    }
  end

  # Public: The name to present people for this release. Tries name ->
  # annotated message -> tag name.
  #
  # Returns a String
  def display_name
    return name unless name.blank?
    return "Draft" unless published?
    return if !tagged?

    self.class.prefix_with_tag_name(tag_title, tag_name)
  end

  def display_body
    return body unless body.blank?
    if name.blank? || name.b[tag_title.b]
      tag_body
    else
      "#{tag_title.b}\n\n#{tag_body.b}"
    end.dup.force_encoding("utf-8").scrub!
  end

  def repository_never_pushed_to?
    repository.try(:empty?)
  end

  def notifications_author
    author
  end

  def notifications_thread
    self
  end

  def async_notifications_list
    async_repository
  end

  # Public: Gets the NotificationSummary for this Comment's thread.
  # See Summarizable.
  #
  # Returns Newsies::Response instance.
  def get_notification_summary
    list = Newsies::List.new("Repository", repository_id)
    GitHub.newsies.web.find_rollup_summary_by_thread(list, self)
  end

  def destroy_notification_summary
    # if we don't have the repository anymore, fake it.
    # this eventually needs to be fixed up to pass the ID directly.
    repo = repository || Repository.new.tap { |r| r.id = repository_id }
    GitHub.newsies.async_delete_all_for_thread(repo, self)
  end

  def deliver_notifications?
    !draft?
  end

  # Unique identifier for this issue used in email messages.
  def message_id
    "<#{T.must(repository).name_with_display_owner}/releases/#{id}@#{GitHub.urls.host_name}>"
  end

  # The reactable module requires the subject of the reaction to define the user that owns the subect. Reactable
  # refers to this owner by referencing subject.user. In this case, the owner of the release is the author,
  # so we will alias user to author. The reactable module will do things like check to see if the author has
  # blocked reactions on this particular release.
  alias_attribute :user_id, :author_id

  def user
    author
  end

  def async_user
    async_author
  end

  # Public: Gets the author of a Release.  Falls back to the repository owner
  # for Tags commited by a user without matching GitHub account.
  def author_or_owner
    return author if author
    return nil unless repo = repository
    owner = T.must(repo.owner)
    if owner.organization?
      repo.created_by
    else
      owner
    end
  end

  # Internal: Backdate the Release to the Tag date if if it's been tagged.
  def backdate_if_tagged
    if tagged? && tag.target.respond_to?(:date) && tag.target.date
      self.created_at = tag.target.date.localtime
    end
  end

  # Internal: Store a pending tag name, or create a fake tag name if it's a
  # draft.
  #
  # In order to prevent collisions with real tags, we prefix fake tags with
  # untagged-. If you create a real tag starting with untagged, you deserve
  # bad things to happen to you.
  def fake_tag_if_draft
    return unless draft?

    if tag_name.present?
      self.pending_tag = self.tag_name
    end

    if !untagged_name?
      self.tag_name = "untagged-#{SecureRandom.hex(10)}"
    end
  end

  # Internal: Create a Git Tag if we're publishing this thing.
  def create_tag_on_publish
    return unless published?
    self.tag_name = pending_tag if pending_tag.present?
    return nil if repository_never_pushed_to? || tag_name.blank?
    begin
      errors.add(:tag_name, "is not a valid tag") unless new_tag = ensure_published_tag
    rescue Git::Ref::HookFailed, Git::Ref::InvalidName => e
      errors.add(:pre_receive, e.message)
    rescue Git::Ref::ProtectedBranchUpdateError => e
      errors.add(:pre_receive, e.message)
    rescue Git::Ref::RepositoryRuleViolationError => e
      errors.add(:pre_receive, e.detailed_message)
    end

    # Update tag_name to normalize it. This will remove "refs/tags" prefix if present
    self.tag_name = tag.name if tagged?
    set_tag(new_tag) if new_tag.is_a? Git::Ref
  end

  def untagged_name?
    self.class.untagged_name?(tag_name)
  end

  def only_tag?
    new_record? && tagged?
  end

  def potential_github_action?
    T.must(repository).listable_action?
  end

  def deletable?
    return true unless new_record?
    tagged?
  end

  def protected_tag_deletable_by?(user)
    self.class.protected_tags_deletable_by?(user, [self]).include?(self)
  end

  # Public: Return the subset of a collection of Releases that have tags deletable by the given user.
  #
  # user - The User to check deletability for.
  # releases - The collection of Releases to check.
  #
  # Returns an Array of Releases that the user is permitted to delete.
  def self.protected_tags_deletable_by?(user, releases)
    return [] if user.nil? || releases.empty?
    GitHub::PrefillAssociations.prefill_associations(releases, :repository)
    ref_updates = releases.map do |release|
      Git::Ref::Update.new(
        repository: release.repository,
        refname: release.tag.qualified_name,
        before_oid: release.tag.sha,
        after_oid: GitHub::NULL_OID,
      )
    end

    releases.group_by(&:repository).flat_map do |repo, _repo_releases|
      rule_suites = RuleEngine::Evaluator.evaluate_rules(repo, ref_updates, user, dry_run: true)
      check_bypass = GitHub.flipper[:tag_delete_check_bypass].enabled?(repo)
      rule_suites.zip(releases).filter_map { |rule_suite, release| release if check_bypass ? rule_suite.action_permitted? : rule_suite.rules_fulfilled? }
    end
  end

  def tag_protected?
    T.must(repository).tag_protected?(tag.name)
  end

  sig { returns(T::Boolean) }
  def tag_protected_by_ruleset?
    evaluator = BranchRuleEvaluator.for_repository_with_tag_name(T.must(repository), tag.name)
    evaluator&.block_deletions_enabled? || false
  end

  def delete_tag(commit_oid, deleter, reflog_data = {})
    repo = T.must(repository)

    return if !repo.tags.exist?(tag_name.b)
    ref = repo.tags.build(tag_name.b, commit_oid)
    ref.delete(deleter, reflog_data: reflog_data)
    true
  rescue Git::Ref::ComparisonMismatch, TypeError
    nil
  end

  def exposed_tag_name
    draft? ? pending_tag.to_s : tag_name
  end

  def self.untagged_name?(name)
    name && name.starts_with?(UNTAGGED_PREFIX)
  end

  UNTAGGED_PREFIX = "untagged-"

  def actor
    async_actor.sync
  end

  # Reactable relies on a call to async_actor instead of just actor
  def async_actor
    # The user who performed the action as set in the GitHub request context. If
    # the context doesn't contain an actor, fallback to the ghost user.
    @actor ||= User.find_by(id: GitHub.context[:actor_id]) || User.ghost
    Promise.resolve(@actor)
  end

  # The reactions UI component uses async_reactable_by to see if the current user can react
  # to the given subject
  alias_method :async_reactable_by?, :async_viewer_can_react?

  # Only published releases can be reacted to, and only by users that can view them.
  def async_viewer_can_react?(viewer)
    return Promise.resolve(false) unless published?

    repo = T.must(repository)
    return Promise.resolve(false) unless repo.public? || repo.resources.contents.readable_by?(viewer)

    super
  end

  def target_for_conditional_access
    T.must(repository).target_for_conditional_access
  end

  def async_target_for_conditional_access
    async_repository.then(&:async_target_for_conditional_access)
  end

  # Commits since the previous release, limited to 10_000
  def commits
    return [] unless self.tag
    return @commits if defined?(@commits)

    oids = commit_oids

    GlobalInstrumenter.instrument("release.commits_fetched", {
      since: previous_release? ? :PREVIOUS_RELEASE : :BEGINNING,
      commits_fetched: oids.count,
      total_commits: T.must(repository).rpc.fast_commit_count(tag.target_oid, nil, timeout: 2),
      repository: repository,
      release: self,
      previous_release: previous_release? && previous_release,
    })

    oids = oids.first(COMMITS_LIMIT)

    @commits = Platform::Loaders::GitObject
      .load_all(repository, oids, expected_type: :commit)
      .sync
  end

  def commit_oids
    if previous_release?
      commit_oids_since_previous_release
    else
      commit_oids_since_the_beginning
    end
  end

  def previous_release
    return @previous_release if defined?(@previous_release)

    @previous_release = Release::FindPreviousRelease.for(self)
  end

  def previous_release?
    !(only_release? || first_release?)
  end

  def body_pipeline
    GitHub::Goomba::ReleasePipeline
  end

  # See the description of Release::ReleaseNotes initialize and generate for descriptions of
  # the parameters and return values.
  sig do
    params(
      previous_tag_name: T.nilable(String),
      template: T.nilable(String),
      configuration_file_path: T.nilable(String),
    ).returns(Releases::IReleaseNotes)
  end
  def generate_release_notes(previous_tag_name: nil, template: nil, configuration_file_path: nil)
    Release::ReleaseNotes.new(
      self,
      previous_tag_name: previous_tag_name,
      template: template,
      configuration_file_path: configuration_file_path
    ).generate
  end

  batch_method :short_description_info do |releases, opts|
    results = releases.map { |r| r.async_short_description_html_info(**opts) }
    results = Promise.all(results).sync

    releases.zip(results).to_h
  end

  batch_method(:mentions_count) do |releases|
    mention_counts = ReleaseMention.where(release_id: releases.map(&:id)).group(:release_id).count
    releases.index_with { |r| mention_counts[r.id] || 0 }
  end

  def short_description_html(**kwargs)
    short_description_html_info(**kwargs)[:html]
  end

  def short_description_html_info(**kwargs)
    async_short_description_html_info(**kwargs).sync
  end

  def async_short_description_html_info(length: DEFAULT_SHORT_DESCRIPTION_LENGTH, preview_img_filter: {})
    return Promise.resolve({ html: GitHub::HTMLSafeString::EMPTY, truncated?: false, preview_img_path: nil }) unless body.present?

    async_body_html.then do |body_html|
      truncator = HTMLTruncator.new(body_html, length, strip_block_elements: false, preview_img_filter: preview_img_filter)
      {
        html: truncator.to_html(wrap: false) || GitHub::HTMLSafeString::EMPTY,
        truncated?: truncator.remaining.content.present?,
        preview_img_path: truncator.preview_img_path
      }
    end
  end

  # Method to parse the Release body looking for @mentions and construct the mentions array
  def populate_mentions
    self.mentions = mentioned_users[0...MENTION_LIMIT]
  end

  def is_searchable?(log_reason: false)
    # If the repository is missing, then we have a rogue release
    if repository.nil?
      GitHub.dogstats.increment("release.is_searchable", tags: ["value:false", "reason:repository_nil"]) if log_reason
      return false
    end
    # If the repository is not searchable, its releases shouldn't be either
    unless T.must(repository).repo_is_searchable?
      GitHub.dogstats.increment("release.is_searchable", tags: ["value:false", "reason:!repo_is_searchable"]) if log_reason
      return false
    end
    # If a published release has lost its tag, it shouldn't be searchable
    # The expected way to index back an untagged published release is:
    # 1) create the tag again in the repo,
    # 2) try to create a release from the tag,
    # 3) it will find the orphan release and provide a link to it,
    # 4) from the release edit page, save it, which will re-index it.
    if published? && !tagged?
      GitHub.dogstats.increment("release.is_searchable", tags: ["value:false", "reason:published_not_tagged"]) if log_reason
      return false
    end

    true
  end

  def og_image_url
    repo = T.must(repository)
    open_graph = OpenGraph.new(self, cache_key_parts: [updated_at, repo.name, repo.owner_id])
    open_graph.og_image_url
  end

  def body_cache_key_prefix(key)
    [super, "pipeline_v#{RELEASE_PIPELINE_CACHE_VERSION}"].compact.join(":")
  end

  def async_discussion
    async_repository.then do |repo|
      repo.async_discussions_on?.then do |discussions_on|
        discussions_on ? super : nil
      end
    end
  end

  private

  def commit_oids_since_previous_release
    return [] unless previous_release?

    GitHub::Comparison.from_range(
      repository,
      "#{previous_release.tag_name}...#{current_target}"
    ).rev_list.first(COMMITS_LIMIT)
  end

  def commit_oids_since_the_beginning
    repo = T.must(repository)
    sha = self.tag&.target_oid || repo.ref_to_sha(self.target_commitish)
    repo.rpc.list_revision_history(sha, limit: COMMITS_LIMIT)
  end

  # Validation: Ensure that the author has access to create this Release.
  def author_access
    if !author
      errors.add :author_id, "is not a valid User"
    elsif !repository
      errors.add :repository_id, "is not a valid repository"
    else
      a = author
      if a.is_a?(Bot)
        # Because we might be building from just a user id, the installation
        # attribute will not be present for bots. Perhaps `writable_by?` should
        # handle this instead?
        a.async_load_installation_for(repository).sync
      end
      repo = T.must(repository)
      if !repo.resources.contents.writable_by?(user)
        errors.add :author_id, "does not have push access to #{repo.name_with_owner}"
      end
    end
  end

  # Validation: Make sure we don't let people enter bad target_commitish values
  def target_commitish_is_valid
    return if published? && !target_commitish_changed?
    return if target_commit || (draft? && target_commitish == repository.try(:default_branch))

    errors.add :target_commitish, "is invalid"
  end

  # Validation: Make sure we don't let people create Releases with names that
  # Git doesn't like.
  def tag_name_is_well_formed
    return if published? && !tag_name_changed?
    return if T.must(repository).tags.build(tag_name).well_formed?

    errors.add :tag_name, "is not well-formed"
  end

  # Validation: Ensure that all published Releases correspond to an existing
  # tag.
  def published_releases_are_tagged
    return unless published?
    if repository_never_pushed_to?
      errors.add(:base, "Repository is empty.")
    elsif !tagged?
      errors.add :base, "Published releases must have a valid tag"
    end
  end

  # Validation: Ensures the tag name is a valid format
  def tag_is_well_formed
    if published? && (tag && !tag.well_formed?)
      errors.add :base, "Tag is not well formed"
    end
  end

  def ensure_published_tag
    return true if tagged?(force = true)
    repo = T.must(repository)

    tag = repo.tags.build(tag_name)
    return unless tag.well_formed? && target_commit
    tag.create(target_commit, actor, reflog_data: reflog_data)
  rescue Git::Ref::ExistsError
    true
  end

  # Sets the published_at timestamp if this Release is published.
  def set_published_at
    if published?
      if state_changed?
        self.published_at = Time.zone.now
      else
        self.published_at ||= Time.zone.now
      end
    end
  end

  # Synchronize this release with its representation in the search index.
  def synchronize_search_index
    Search.add_to_search_index("release", self.id)
  end

  # Removes this release from the search index upon deletion.
  def remove_from_search_index
    RemoveFromSearchIndexJob.perform_later("release", self.id)
  end

  # used to guard #instrument_publish
  def trigger_publish_event?
    # because the state enum defaults to published, the state field doesn't
    # "change" if a release is published on creation; for this reason,
    # we check the trigger_first_publish_event? as well.
    !importing? && (trigger_first_publish_event? || (repository && published? && state_previously_changed?))
  end

  # Triggers publish related events if the release is published.
  #
  # Returns nothing.
  def instrument_publish
    # intentionally uses GitHub.instrument to override the full payload
    GitHub.instrument "release.published", webhook_event_payload

    GlobalInstrumenter.instrument("release.published", {
      release: self,
      actor: author,
      repository: repository,
      owner: T.must(repository).owner,
    })
  end

  # used to guard #instrument_first_publish
  def trigger_first_publish_event?
    !importing? && repository && published? && published_at_previously_was.nil?
  end

  # Triggers publish related events if the release is published for the first time.
  def instrument_first_publish
    deliver_notifications(event_time: published_at)

    GlobalInstrumenter.instrument("release.first_published", {
      release: self,
      actor: author,
      repository: repository,
      owner: T.must(repository).owner,
    })
  end

  def async_body_context
    super.then do |context|
      context.merge(
        path: "",
        committish: tag_name_or_target_commitish,
        mention_limit: MENTION_LIMIT,
      )
    end
  end

  def body_version
    super + ":#{Digest::SHA256.hexdigest(tag_name_or_target_commitish.to_s)}"
  end

  def instrument_creation
    instrument :create, actor: author

    # intentionally uses GitHub.instrument to override the full payload
    GitHub.instrument "release.create_webhook", webhook_event_payload.merge(actor: author)
  end

  def generate_webhook_payload
    if actor&.spammy?
      @delivery_system = nil
      return
    end

    event = Hook::Event::ReleaseEvent.new(
      action: :deleted,
      release_id: self.id,
      actor_id: actor.id,
      triggered_at: Time.now,
    )

    @delivery_system = Hook::DeliverySystem.new(event)
    @delivery_system.generate_hookshot_payloads
  end

  def queue_webhook_delivery
    unless defined?(@delivery_system)
      raise "`generate_webhook_payload` must be called before `queue_webhook_delivery`"
    end

    @delivery_system&.deliver_later
  end

  def instrument_update
    instrument_update_audit_log
    instrument_update_webhook
  end

  # Instruments an update for the audit log (NOT webhooks). The actual body is intentionally
  # not included to prevent logging too much info.
  def instrument_update_audit_log
    return if previous_changes.empty? unless make_latest

    changes = {}.tap do |hash|
      hash[:old_name] = previous_changes["name"].first if previous_changes["name"].present?

      # tag_name is a temp tag starting with untagged- for all draft releases, with the actual target stored in
      # pending_tag
      if previous_changes["tag_name"].present?
        if being_published? || draft?
          hash[:old_tag_name] = previous_changes["pending_tag"].first if previous_changes["pending_tag"].present?
        else
          hash[:old_tag_name] = previous_changes["tag_name"].first
        end
      end

      hash[:old_state] = previous_changes["state"].first if previous_changes["state"].present?
      hash[:old_prerelease] = previous_changes["prerelease"].first if previous_changes["prerelease"].present?
      hash[:old_target_commitish] = previous_changes["target_commitish"].first if previous_changes["target_commitish"].present?
      hash[:make_latest] = true if make_latest

      # do not update to include the actual body
      hash[:body_changed] = true if previous_changes["body"].present?
    end

    return if changes.empty?
    instrument :update, changes: changes
  end

  # This version is only used for webhooks.
  def instrument_update_webhook
    return if previous_changes.empty? unless make_latest
    return if being_prereleased?

    changes = {}.tap do |hash|
      hash[:old_name] = previous_changes["name"].first if previous_changes["name"].present?
      hash[:old_body] = previous_changes["body"].first if previous_changes["body"].present?
      # Newly published releases default to make_latest: true and would trigger an update event
      # each time releases are published/released if we didn't exclude them here.
      hash[:make_latest] = make_latest if make_latest && !being_published? && !being_released?
    end

    return if changes.empty?

    # intentionally uses GitHub.instrument to override the full payload
    GitHub.instrument "release.update_webhook", webhook_event_payload.merge(changes: changes)
  end

  def instrument_destroy
    instrument :destroy
  end

  def instrument_unpublish
    return unless being_unpublished?

    # intentionally uses GitHub.instrument to override the full payload
    GitHub.instrument "release.unpublish", webhook_event_payload
  end

  def being_unpublished?
    return false unless previous_changes && previous_changes["state"]
    previous_changes["state"].first == "published" && state == "draft"
  end

  def being_published?
    return false if state != "published"
    previous_changes.key?("state")
  end

  def instrument_prerelease
    return unless being_prereleased?

    # intentionally uses GitHub.instrument to override the full payload
    GitHub.instrument "release.prerelease", webhook_event_payload
  end

  def being_released?
    return false if state == "draft"
    previous_changes.key?("prerelease")
  end

  def being_prereleased?
    return false unless previous_changes && previous_changes["prerelease"]
    previous_changes["prerelease"].first != true && self.prerelease == true
  end

  def instrument_release_update
    return if prerelease == true
    return unless being_published? || being_released?

    # intentionally uses GitHub.instrument to override the full payload
    GitHub.instrument "release.release", webhook_event_payload
  end

  def instrument_release_create
    # This is separate from `instrument_release_update` because when a release is
    # created in a `finalized` state, the state field defaults to `published`
    # if unspecified and as a result is not in the `previous_changes` hash. As such
    # it's more convenient to have separate callbacks for the `release` event for
    # create and update
    return unless state == "published" && prerelease == false

    # intentionally uses GitHub.instrument to override the full payload
    GitHub.instrument "release.release", webhook_event_payload
  end

  def webhook_event_payload
    {
      event_prefix => self,
      :author      => author,
      :repository  => repository,
      :actor       => actor,
      :spammy      => actor != User.ghost && actor.spammy?,
    }
  end

  def event_payload
    {
      event_prefix      => self,
      :author           => author,
      :repo             => repository,
      :name             => name,
      :tag_name         => exposed_tag_name,
      :target_commitish => target_commitish,
      :state            => state,
      :prerelease       => prerelease,
      :actor            => actor,
    }
  end

  def first_release?
    return @is_first_release if defined?(@is_first_release)
    @is_first_release = previous_release.nil?
  end

  def only_release?
    return @is_only_release if defined?(@is_only_release)
    @is_only_release = !Release.where(repository: repository).where.not(id: self.id).exists?
  end

  def valid_for_latest
    return unless make_latest
    # Call .destroy on this model after creating it to avoid auto saving a duplicate when #save is called on the release.
    # RepositoryLatestReleases are saved via upsert, not via ActiveRecord association autosave.
    model = RepositoryLatestRelease.new(release: self, repository: repository).destroy
    errors.add(:base, model.errors.full_messages.join(", ")) unless model.valid?
  end

  # Removes the stored repository_latest_release record for this release if it should no longer be the latest.
  def clear_latest_if_no_longer_valid
    latest_release = repository_latest_release
    latest_release.destroy if latest_release&.invalid?
  end

  # Set the stored latest release for this repository to this release.
  def set_as_latest
    return unless make_latest
    T.must(repository).set_latest_release(self)
  end
end
