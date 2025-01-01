# typed: true
# frozen_string_literal: true

require "branch_sorter"

class Label < ApplicationRecord::Domain::IssuesPullRequests
  include Issues::ILabel
  include GitHub::Relay::GlobalIdentification
  include Instrumentation::Model
  include Labelable
  include PreloadableAttributes
  include Label::IssuesGraphDependency
  include MemexProjectColumn::Interface::Groupable::Metadata
  include MemexProjectColumn::Interface::Sliceable::Metadata
  include MemexProjectColumn::Interface::Serializable
  include Repositories::BelongsToRepository

  attribute :name, StringFromBinary.new
  attribute :lowercase_name, StringFromBinary.new
  attribute :description, StringFromBinary.new

  include Label::DiscussionsDependency

  URI_TEMPLATE = Addressable::Template.new("/{owner}/{name}/labels/{label_name}").freeze
  NAME_HTML_CACHE_KEY_PREFIX = "label"

  validates :name, length: { maximum: NAME_MAX_LENGTH }

  validates_with CreateLabelValidator, fields: [:name], on: :create

  validates :description, length: { maximum: DESCRIPTION_MAX_LENGTH }, allow_blank: true

  belongs_to_repository_via_domain
  delete_in_background_with :repository

  attr_preloadable :preloaded_name_html

  scope :for_milestone, -> (milestone) {
    includes(:issues).where("issues.milestone_id = ?", milestone).references(:issues)
  }

  scope :for_issue_ids, -> (ids) {
    includes(:issues).where("issues.id IN(?)", ids).references(:issues)
  }

  scope :on_open_issues,   -> { includes(:issues).where("issues.state = ?", "open").references(:issues) }
  scope :on_closed_issues, -> { includes(:issues).where("issues.state = ?", "closed").references(:issues) }

  # Public: Find labels with any of the given names, case insensitive.
  scope :with_name, ->(names) do
    if names.is_a?(String)
      where(lowercase_name: names.downcase)
    else
      where(lowercase_name: names.map(&:downcase))
    end
  end

  # Public: Find labels whose name starts with the given string, case insensitive.
  scope :with_name_like, ->(name) {
    sanitized_name = ActiveRecord::Base.sanitize_sql_like(name.downcase)
    where(arel_table[:lowercase_name].matches("#{sanitized_name}%"))
  }
  # Do we need to do something here for default scope
  has_many :issues_labels, class_name: "IssuesLabels"
  has_many :issues, through: :issues_labels

  has_many :applied_discussion_labels
  has_many :discussions, through: :applied_discussion_labels

  before_validation :normalize_name, :normalize_description, :expand_color_shorthand,
  :set_lowercase_name

  before_create :set_label_name # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  before_update :set_label_name, if: :name_changed? # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  validates_presence_of   :name
  validates_format_of     :name,  with: NAME_REGEXP
  validate :uniqueness_of_name
  validate :name_has_more_than_emoji
  validates_format_of     :color, with: COLOR_REGEXP

  after_commit :synchronize_search_index # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :update_issues, on: :update # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :update_discussions, on: :update # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_update, on: :update # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  after_commit :unlabel_associated_issues_deferred, on: :destroy # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  before_destroy :generate_hook_payload # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_destruction, on: :destroy # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_creation, on: :create # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  attr_accessor :already_performed_authorization

  # Public: Look up a label by name, case insensitive.
  #
  # name - String name of a label
  #
  # Returns a Label or nil.
  def self.find_by_name(name) # rubocop:disable GitHub/FindByDef
    with_name(name).first
  end

  # Public: Find a label whose name is exactly 'help wanted', case insensitive.
  def self.help_wanted
    where(lowercase_name: HELP_WANTED_NAME).first
  end

  # Public: Find a label whose name begins with 'help wanted', case insensitive.
  def self.similar_to_help_wanted
    with_name_like(HELP_WANTED_NAME).first
  end

  # Public: Find a label whose name is exactly 'good first issue', case insensitive.
  def self.good_first_issue
    where(lowercase_name: GOOD_FIRST_ISSUE_NAME).first
  end

  # Public: Find a label whose name begins with 'good first issue', case insensitive.
  def self.similar_to_good_first_issue
    with_name_like(GOOD_FIRST_ISSUE_NAME).first
  end

  def to_s
    name
  end

  # The user who performed the action as set in the GitHub request context. If
  # the context doesn't contain an actor, fallback to the ghost user.
  def actor
    @actor ||= (User.find_by(id: GitHub.context[:actor_id]) || User.ghost)
  end

  def self.by_issues_count(repo:, limit:)
    sql = Arel.sql(<<-SQL, repo_id: repo.id, limit: Arel.sql(limit.to_s))
      select label_id, count(1) as issues_count
      from issues_labels inner join issues on issues.id = issues_labels.issue_id
      where issues.repository_id = :repo_id
      and issues.state = 'open'
      group by label_id
      order by issues_count desc
      limit :limit
    SQL

    label_ids = ApplicationRecord::Domain::IssuesPullRequests.connection.select_rows(sql).map { |(label_id)| label_id } # domain-isolation-query-violation:ignore:packages/issues (select)

    Label.where(id: label_ids)
  end

  batch_method(:batch_issue_counts) do |labels, repo_id|
    sql = Arel.sql(<<-SQL, repo_id: repo_id)
      select label_id, issues.pull_request_id, count(1)
      from issues_labels inner join issues on issues.id = issues_labels.issue_id
      where issues.repository_id = :repo_id
      and issues.state = 'open'
      group by label_id, pull_request_id
    SQL

    issues_counts = Hash.new(0)
    non_pr_issues_counts = Hash.new(0)

    ApplicationRecord::Domain::IssuesPullRequests.connection.select_rows(sql).each do |(label_id, pr_id, count)| # domain-isolation-query-violation:ignore:packages/issues (select)
      issues_counts[label_id] += count
      non_pr_issues_counts[label_id] += count if pr_id.nil?
    end

    labels.index_with do |label|
      { total: issues_counts[label.id], without_pull_requests: non_pr_issues_counts[label.id] }
    end
  end

  # Public: The number of associated open issues that may or may not be tied to
  # pull requests.
  #
  # Returns the Integer issues count.
  def issues_count
    if has_attribute?(:issues_count)
      attributes["issues_count"]
    else
      batch_issue_counts(repository_id)[:total]
    end
  end

  def pull_requests_count
    if has_attribute?(:pull_requests_count)
      attributes["pull_requests_count"]
    else
      issues_count - issues_without_pull_requests_count
    end
  end

  # Public: The number of associated open issues that are not tied to pull requests.
  #
  # Returns an integer.
  def issues_without_pull_requests_count
    if has_attribute?(:issues_without_pull_requests_count)
      attributes["issues_without_pull_requests_count"]
    else
      batch_issue_counts(repository_id)[:without_pull_requests]
    end
  end

  # Internal: Require Issue#repository_id and Label#repository_id to match.
  # Returns an ActiveRecord Issue scope.
  def repository_restricted_issues
    issues.where(repository_id: repository_id)
  end

  def readable_by?(actor)
    T.cast(repository, Repository).readable_by?(actor) # rubocop:todo GitHub/AvoidCast
  end

  # Sort labels and optionally group by issue count.
  #
  # labels          - an Array or association collection of labels
  # by_issues_count - Whether to put labels without issues at the bottom (default: false).
  #                   This relies on the `issues_count` attribute.
  #
  # returns - a one-dimension sorted (and/or grouped) array of labels
  def self.smart_sort(labels, by_issues_count = false)
    sorted_labels = BranchSorter.new(labels) { |label| label.name.downcase }

    if by_issues_count
      labels_without_issues, labels = sorted_labels.partition { |label| label.issues_count.zero? }
      labels.concat labels_without_issues
    else
      sorted_labels.to_a
    end
  end

  DEFAULT_LABEL_NAMES = Set.new(initial_labels.map { |l| l[:name] })

  def default?
    DEFAULT_LABEL_NAMES.include?(name)
  end

  def to_param
    name
  end

  # Public: Synchronize this label with its representation in the search index. If the label is
  # newly created or modified in some fashion, then it will be updated in the search index. If the
  # label has been destroyed, then it will be removed from the search index. This method handles
  # both cases.
  def synchronize_search_index
    if self.destroyed?
      RemoveFromSearchIndexJob.perform_later("label", id, repository_id)
    else
      Search.add_to_search_index("label", id)
    end

    self
  end

  # Returns the name of the label in a search-friendly format.
  #
  # For labels with no spaces (`bug`), it just returns the label: bug.
  # For labels with spaces (`big bug`), it quotes the value: "big bug".
  #
  # Returns a String.
  def to_search_slug
    name.match(" ") ? "\"#{name}\"" : name
  end

  # Internal: If the name of the label has changed, then we need to
  # update the search records for all the issues and pull requests associated
  # with this label.
  def update_issues
    return unless self.previous_changes["name"].present?

    # TODO: This needs to happen in a batched background job
    repository_restricted_issues.each do |issue| # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      if !issue.pull_request?
        issue.update_repo_community_profile!
      end
    end

    Issues::ReindexIssuesForAssociationJob.enqueue(:labels, self.id)

    self
  end

  # Internal: If the name of the label has changed, reindex search records for
  # all labelled discussions.
  def update_discussions
    return unless self.previous_changes["name"].present?
    discussions.each(&:synchronize_search_index)
  end

  def unlabel_associated_issues_deferred
    DestroyIssuesLabelsJob.perform_later(actor.id, Time.now.utc, id, name, color, repository_id)
  end

  def async_path_uri
    return @async_path_uri if defined?(@async_path_uri)
    @async_path_uri = async_repository.then { path_uri }
  end

  def path_uri
    URI_TEMPLATE.expand(
      owner: T.must(repository).owner_display_login,
      name: T.must(repository).name,
      label_name: name,
    )
  end

  def url
    return unless repository = self.repository
    encoded_name = ERB::Util.url_encode(name)
    GitHub.url + "/#{repository.owner_display_login}/#{repository.name}/labels/#{encoded_name}"
  end

  # Internal: Returns a non-persisted instance if the label is found
  #
  # name: The name of the label
  #
  # Returns a Label or nil
  def self.default_for(name)
    return unless data = initial_labels.find { |hash| hash[:name] == name }
    Label.new(data)
  end

  def async_name_html(skip_cache: false)
    renderer = EmojiHtmlStringRenderer.new(name, skip_cache: skip_cache, cache_key_prefix: NAME_HTML_CACHE_KEY_PREFIX)
    renderer.async_to_html.then do |name_as_html|
      @name_html = name_as_html
    end
  end

  def name_html(skip_cache: false)
    return @preloaded_name_html if defined?(@preloaded_name_html)
    return @name_html if defined?(@name_html)
    @name_html = async_name_html(skip_cache: skip_cache).sync
  end

  sig { override.returns(T::Hash[T.untyped, T.untyped]) }
  def memex_column_hash
    MemexProjectColumnValue::Label.new(
      color: color,
      id: id,
      name: name,
      name_html: name_html,
      url: url,
    ).to_hash
  end
  alias_method :group_metadata, :memex_column_hash
  alias_method :slice_metadata, :memex_column_hash

  def memex_suggestion_hash(selected:)
    memex_column_hash.merge(selected: selected)
  end

  def async_target_for_conditional_access
    async_repository.then { |x| T.must(x).async_target_for_conditional_access }
  end

  sig { override.returns(String) }
  def csv_column_value
    name || ""
  end

  private

  # Used in uniqueness_of_name validation
  def sibling_labels_with_same_name
    T.cast(repository, Repository).labels.where(lowercase_name: lowercase_name) # rubocop:todo GitHub/AvoidCast
  end

  # Used in uniqueness_of_name validation
  def owner
    repository
  end

  def event_payload
    {
      label_id: id,
      actor_id: actor.try(:id),
    }
  end

  def set_label_name
    self.label_name = name
  end

  def generate_hook_payload
    if actor&.spammy?
      @delivery_system = nil
      return
    end

    payload = event_payload.merge(action: :deleted, triggered_at: Time.now)
    event = Hook::Event::LabelEvent.new(payload)
    @delivery_system = Hook::DeliverySystem.new(event)
    @delivery_system.generate_hookshot_payloads
  end

  def instrument_creation(issue_id: nil)
    instrument :create, event_payload

    GlobalInstrumenter.instrument("label.create",
      actor: actor,
      label: self,
      issue_id: issue_id,
    )
  end

  def instrument_update
    return if previous_changes.empty?

    changes_payload = {
      old_name: previous_changes["name"].try(:first),
      old_color: previous_changes["color"].try(:first),
      old_description: previous_changes["description"].try(:first),
    }

    GitHub.instrument "label.update", event_payload.merge(changes: changes_payload)

    actor = User.find_by(id: GitHub.context[:actor_id])
    GlobalInstrumenter.instrument("label.update",
      actor: actor,
      label: self,
    )
  end

  def instrument_destruction
    actor = User.find_by(id: GitHub.context[:actor_id])
    GlobalInstrumenter.instrument("label.delete",
      actor: actor,
      label: self,
    )

    unless defined?(@delivery_system)
      raise "`generate_hook_payload' must be called before the webhook can be delivered"
    end

    @delivery_system&.deliver_later
  end
end
