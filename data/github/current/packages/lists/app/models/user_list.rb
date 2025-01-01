# typed: false
# frozen_string_literal: true

class UserList < ApplicationRecord::Collab
  include GitHub::Relay::GlobalIdentification
  include GitHub::Validations
  include Instrumentation::Model
  include PreloadableAttributes

  class UnauthorizedError < StandardError; end
  class ItemNotFoundError < StandardError; end

  MAX_PER_USER = 32
  NAME_BYTESIZE_LIMIT = 128
  DESCRIPTION_BYTESIZE_LIMIT = 640
  NAME_HTML_CACHE_KEY_PREFIX = "user_list:name"
  DESCRIPTION_HTML_CACHE_KEY_PREFIX = "user_list:description"

  NONWORD_RX = /[^\p{Alnum}]+/
  LEADING_TRAILING_HYPHEN_RX = /\A-*|-*\z/

  DEFAULT_SUGGESTIONS = [
    "🔮 Future ideas",
    "🚀 My stack",
    "✨ Inspiration"
  ].freeze

  belongs_to :user, inverse_of: :lists

  has_many :items, -> { order(created_at: :asc) },
    foreign_key: :user_list_id,
    class_name: "UserListItem",
    inverse_of: :user_list,
    dependent: :destroy
  has_many :repositories, through: :items, source: :repository, disable_joins: true

  before_validation :strip_name
  before_validation :generate_slug, if: :name_changed?

  validates :user, presence: true
  validates :name, presence: true, bytesize: { maximum: NAME_BYTESIZE_LIMIT }
  validates :slug, uniqueness: { scope: :user_id, case_sensitive: false }
  validates :description, bytesize: { maximum: DESCRIPTION_BYTESIZE_LIMIT }

  validate :ensure_name_includes_non_emoji
  validate :ensure_user_has_less_than_max_lists, on: :create

  before_create :set_initial_last_added_at

  after_commit :instrument_creation, on: :create
  after_commit :instrument_audit_log_update, on: :update
  after_commit :instrument_deletion, on: :destroy
  after_commit :user_created_list_kv, on: :create

  after_validation :normalize_slug_errors_to_name

  scope :owned_by, ->(user) { where(user: user) }
  scope :with_item, ->(item) { joins(:items).where(items: { repository: item }) }
  scope :with_colliding_name, ->(name) { where(slug: UserList.slug_for_name(name)) }
  scope :recently_added_first, -> { order(last_added_at: :desc) }
  scope :public_scope, -> { where(private: false) }
  scope :private_scope, -> { where(private: true) }

  def to_param
    slug_in_database
  end

  def self.slug_for_name(name)
    name.downcase.gsub(NONWORD_RX, "-").gsub(LEADING_TRAILING_HYPHEN_RX, "")
  end

  def self.has_created_lists?(user_id)
    GitHub.kv.exists("user:#{user_id}:created_user_list").value! # rubocop:todo GitHub/DoNotUseGlobalKv
  rescue GitHub::KV::UnavailableError
    false
  end

  def self.name_character_limit
    # Consistent with the way bytesize is converted to characters for the validation error message in the bytesize
    # validator. See lib/github/validations/bytesize.rb.
    NAME_BYTESIZE_LIMIT / 4
  end

  def self.description_character_limit
    DESCRIPTION_BYTESIZE_LIMIT / 4
  end

  # Public: Get the HTML markup to render a given list name. Will include HTML tags to render emoji in the name with
  # a fallback image in case the viewer's browser doesn't support that emoji.
  #
  # skip_cache - Boolean flag to bypass the cache and force a fresh rendering
  #
  # Returns a Promise<String>.
  def self.async_name_html_for(list_name, skip_cache: false)
    renderer = EmojiHtmlStringRenderer.new(list_name, skip_cache: skip_cache,
      cache_key_prefix: NAME_HTML_CACHE_KEY_PREFIX)
    renderer.async_to_html
  end

  def self.with_each_default_suggestion
    DEFAULT_SUGGESTIONS.each do |suggested_name|
      suggested_name_html = async_name_html_for(suggested_name).sync
      yield suggested_name, suggested_name_html
    end
  end

  def last_added_at
    super || created_at
  end

  def to_s
    name
  end

  attr_preloadable :preloaded_name_html

  def user_login
    user&.display_login
  end

  def async_name_html(skip_cache: false)
    self.class.async_name_html_for(name, skip_cache: skip_cache).then do |name_as_html|
      @name_html = name_as_html
    end
  end

  def async_description_html(skip_cache: false)
    renderer = EmojiHtmlStringRenderer.new(description, skip_cache: skip_cache,
      cache_key_prefix: DESCRIPTION_HTML_CACHE_KEY_PREFIX)
    renderer.async_to_html.then do |description_as_html|
      @description_html = description_as_html
    end
  end

  # Public: Get the HTML markup to render this list's name. Includes HTML tags to render emoji in the name with
  # a fallback image in case the viewer's browser doesn't support that emoji.
  #
  # skip_cache - Boolean flag to bypass the cache and force a fresh rendering
  #
  # Returns a String.
  def name_html(skip_cache: false)
    return @preloaded_name_html if defined?(@preloaded_name_html)
    return @name_html if defined?(@name_html)
    @name_html = async_name_html(skip_cache: skip_cache).sync
  end

  # Public: Get the HTML markup to render this list's description. Includes HTML tags to render emoji in the
  # description with a fallback image in case the viewer's browser doesn't support that emoji.
  #
  # skip_cache - Boolean flag to bypass the cache and force a fresh rendering
  #
  # Returns a String.
  def description_html(skip_cache: false)
    return @preloaded_description_html if defined?(@preloaded_description_html)
    return @description_html if defined?(@description_html)
    @description_html = async_description_html(skip_cache: skip_cache).sync
  end

  # Public: Return true if a user is the owner of this list.
  #
  # user - A User or nil.
  #
  # Returns true or false.
  def owned_by?(user)
    user && user_id == user.id
  end

  # Public: Generate a descriptive title for this list.
  #
  # viewer - A User or nil.
  #
  # Returns a String.
  def title_for(viewer)
    prefix = if owned_by?(viewer)
      "Your list"
    else
      "#{user_login}'s list"
    end

    "#{prefix} / #{self}"
  end

  # Public: Enumerate the Repositories on this list that are visible to an actor. This includes public repositories and
  # any private repositories that the actor has access to.
  #
  # viewer - The User that is requesting the items. Nil for an anonymous viewer.
  # cap_filter - ConditionalAccess::Filter used to screen out repositories based on criteria like SSO/IP filtering.
  #
  # Returns an Array of preloaded Repositories.
  def item_repositories_visible_to(viewer:, cap_filter:)
    promises = repositories.map do |repo|
      repo.async_readable_by?(viewer).then { |is_readable| is_readable ? repo : nil }
    end
    visible_item_repositories = Promise.all(promises).sync.compact

    cap_filter.authorized_resources(visible_item_repositories)
  end

  def update_item_count
    return if destroyed?
    update(item_count: items.size)
  end

  # Internal: Ensures that the user has less than the maximum number of lists.
  #   Modifies the errors object if the user has too many lists
  #
  # Returns nothing
  def ensure_user_has_less_than_max_lists
    if self.class.owned_by(user).count >= MAX_PER_USER
      errors.add(:base, "cannot have more than #{MAX_PER_USER} lists")
    end
  end

  def ensure_name_includes_non_emoji
    if name.present? && slug.blank?
      errors.add(:name, "must include at least one alphanumeric character")
    end
  end

  # Instrumentation::Model overrides

  def event_prefix
    :user_list
  end

  def event_context(prefix: event_prefix)
    {
      "#{prefix}_id": id,
      "#{prefix}_name": name
    }
  end

  def event_payload
    {
      "#{event_prefix}": self,
      user: user,
    }
  end

  # Public: Count the number of items in each of a collection of UserLists that are visible to a specific user.
  #
  # viewer - A User or nil.
  # list_ids - Enumerable collection of IDs of UserLists to count items for.
  # cap_filter - ConditionalAccess::Filter used to screen repositories included in each count based on SSO sessions,
  #   IP filtering, etc.
  #
  # Returns a Hash of { Integer => Integer } mapping each list ID to the count of visible repositories on that list.
  def self.visible_item_counts(viewer:, list_ids:, cap_filter:)
    items = UserListItem.in_list(list_ids).includes(:repository).reject { |item| item.repository.nil? }

    all_repos = Set.new
    list_ids_by_repo_id = Hash.new { |h, k| h[k] = [] }
    items.each do |item|
      all_repos << item.repository
      list_ids_by_repo_id[item.repository_id] << item.user_list_id
    end

    repo_promises = all_repos.map do |repo|
      repo.async_readable_by?(viewer).then { |is_readable| is_readable ? repo : nil }
    end
    visible_repos = Promise.all(repo_promises).sync.compact
    visible_repos = cap_filter.authorized_resources(visible_repos)

    visible_repos.each_with_object(Hash.new(0)) do |repo, counts_by_list_id|
      list_ids_by_repo_id[repo.id].each { |list_id| counts_by_list_id[list_id] += 1 }
    end
  end

  # Public: Declaratively replace the set of UserLists belonging to a user that contain a specific repository. Any lists
  # owned by this user that are included in `lists` that do not already contain the repository will have an item added.
  # Any lists owned by this user that are not included in `lists` that do contain the repository will have the
  # repository's item removed. All other lists will be untouched. The `item_count` and `last_added_at` timestamps of
  # this user's lists will be recomputed.
  #
  # user_id - ID or User owning the lists to update.
  # repository_id - ID or a Repository to update list membership for.
  # list_ids - Enumerable collection of UserLists or IDs belonging to this user that should contain an item for
  #   the repository.
  #
  # Returns nothing.
  def self.replace_all(user_id:, repository_id:, list_ids:)
    transaction do
      list_ids_repo_added_to = UserListItem.bulk_insert(user_id: user_id, repository_id: repository_id,
        list_ids: list_ids)
      list_ids_repo_removed_from = UserListItem.bulk_delete(user_id: user_id, repository_id: repository_id,
        list_ids_to_keep: list_ids)

      modified_list_ids = list_ids_repo_added_to | list_ids_repo_removed_from
      recalculate_item_counts_and_last_added_at_times(user_id: user_id, list_ids: modified_list_ids)
    end
  end

  # Public: Update `item_count` and `last_added_at` timestamps for multiple UserLists.
  #
  # user_id - ID of the User owning the lists to update
  # list_ids - Array of UserList IDs whose item counts and and last-added-at timestamps should be recalculated
  #
  # Returns nothing.
  def self.recalculate_item_counts_and_last_added_at_times(user_id:, list_ids:)
    aggregate_sql = UserListItem
      .select(:user_list_id, "COUNT(*) AS new_item_count", "MAX(user_list_items.created_at) AS new_last_added_at")
      .owned_by(user_id)
      .group(:user_list_id)
      .where(user_list_id: list_ids)
      .to_sql
    user_lists_to_update = owned_by(user_id)
      .joins("LEFT JOIN (#{aggregate_sql}) AS aggregation ON aggregation.user_list_id = id")
      .where(id: list_ids)
    user_lists_to_update.update_all <<~SQL
        item_count = COALESCE(aggregation.new_item_count, 0),
        last_added_at = GREATEST(
          COALESCE(
            aggregation.new_last_added_at,
            last_added_at,
            user_lists.created_at
          ),
          last_added_at
        )
      SQL
  end

  # Public: Construct and return a data structure to efficiently enumerate the UserLists belonging to an owning
  # user, grouped by whether or not a specific repository belongs to each list, then ordered by most recent addition
  # time.
  #
  # user_id - ID or User owning the lists to enumerate.
  # repository_ids - Enumerable collection of IDs of Repositories to preload list membership for.
  #
  # Returns a populated UserList::AppliedSet.
  def self.applied_to(user_id:, repository_ids:)
    lists = owned_by(user_id).order(last_added_at: :desc)
    items = UserListItem.for_repository(repository_ids).in_list(lists)
    AppliedSet.new(lists, repository_ids: repository_ids, items: items)
  end

  def permalink(include_host: true)
    if include_host
      "#{GitHub.url}/stars/#{user_login}/lists/#{slug}"
    else
      "/stars/#{user_login}/lists/#{slug}"
    end
  end

  def og_image_url
    return user.primary_avatar_url(400) if self.private?

    open_graph = OpenGraph.new(self,
      cache_key_parts: [
        updated_at,
        last_added_at,
      ]
    )
    open_graph.og_image_url
  end

  # Public: Create a Hydro event for this list having its name or description changed. This is done separately from
  # audit logging so that we don't emit these events every time an item is added or removed from the list, since that
  # causes the list's `item_count` to change.
  #
  # old_list - the UserList as it was before the change
  #
  # Returns nothing.
  def instrument_hydro_update(old_list:)
    GlobalInstrumenter.instrument("user_list.update", old_user_list: old_list, new_user_list: self)
  end

  # Public: Returns target for conditional access used in the CAP
  # policies.
  #
  # Returns a User object that owns the user list
  def target_for_conditional_access
    user
  end

  private

  def strip_name
    self.name = name&.strip
  end

  def generate_slug
    return unless name.valid_encoding?
    self.slug = self.class.slug_for_name(name)
  end

  def set_initial_last_added_at
    self.last_added_at = attributes["last_added_at"] || created_at || Time.current
  end

  def normalize_slug_errors_to_name
    slug_error = errors.find { |error| error.attribute == :slug }
    if slug_error
      errors.add(:name, slug_error.type, **slug_error.options)
      errors.delete(:slug)
    end
  end

  # Instrumentation callbacks

  def instrument_creation
    # Audit log
    instrument :create

    # Hydro
    GlobalInstrumenter.instrument("user_list.create", user_list: self)
  end

  def instrument_audit_log_update
    instrument :update
  end

  def instrument_deletion
    # Audit log
    instrument :destroy

    # Hydro
    GlobalInstrumenter.instrument("user_list.delete", user_list: self)
  end

  def user_created_list_kv
    begin
      # Update a marker in the KV store to indicate that the user has created a list.
      GitHub.kv.setnx("user:#{user_id}:created_user_list", "1") # rubocop:todo GitHub/DoNotUseGlobalKv
    rescue GitHub::KV::UnavailableError
      # Pass, it's fine, the user will see suggestions until the next time this works.
    end
  end

  # Private: UserLists, efficiently grouped for retrieval based on whether or not a specific repository belongs to
  # each list, then ordered by most recent addition time.
  #
  # Construct these with the UserList.applied_to method.
  class AppliedSet
    def initialize(lists, repository_ids:, items:)
      @lists = lists

      @containing_repo = {}
      repository_ids.each { |repo_id| @containing_repo[repo_id] = Set.new }
      items.each { |item| @containing_repo[item.repository_id].add(item.user_list_id) }
    end

    # Public: Determine whether or not the user has any lists at all.
    def empty?
      # Use .to_a to load the full relation and avoid a redundant query when there are lists to report.
      @lists.to_a.empty?
    end

    # Public: Return a collection of UserLists that contain the given repository, ordered by most recent addition time.
    #
    # repository_id - ID of a repository to find lists for. Must have been provided in the repository_id: argument to
    #   the UserList.applied_to method, or a KeyError will be raised.
    #
    # Returns an Array<UserList>.
    def containing(repository_id)
      containment_set = @containing_repo.fetch(repository_id)
      @lists.select { |list| containment_set.include?(list.id) }
    end

    # Public: Return a collection of UserLists that belong to the queried owner, but do not contain the given
    # repository, ordered by most recent addition time.
    #
    # repository_id - ID of a repository to find lists for. Must have been provided in the repository_id: argument to
    #   the UserList.applied_to method, or a KeyError will be raised.
    #
    # Returns an Array<UserList>.
    def not_containing(repository_id)
      containment_set = @containing_repo.fetch(repository_id)
      @lists.reject { |list| containment_set.include?(list.id) }
    end

    # Public: Return the total count of lists in the AppliedSet
    #
    # Returns a number
    def size
      # Use .to_a to load the full relation and avoid a redundant query when there are lists to report.
      @lists.to_a.size
    end
  end
end
