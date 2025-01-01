# typed: true
# frozen_string_literal: true

class IssueType < ApplicationRecord::Domain::IssuesPullRequests
  include Issues::IIssueType
  include GitHub::UTF8
  include GitHub::BatchedScope
  include GitHub::Validations
  include MemexProjectColumn::Interface::Groupable::Metadata
  include MemexProjectColumn::Interface::Sliceable::Metadata
  include MemexProjectColumn::Interface::Serializable

  COLORS = {
    gray: 0,
    blue: 1,
    green: 2,
    yellow: 3,
    orange: 4,
    red: 5,
    pink: 6,
    purple: 7,
  }.freeze

  RESERVED_NAMES = [
    "issue",
    "pull request",
    "pr",
    "pull-request",
  ].freeze

  enum :color, COLORS, prefix: true

  belongs_to :owner, class_name: "User"

  has_many :repository_issue_types, inverse_of: :issue_type
  destroy_dependents_in_background :repository_issue_types

  has_many :issues, inverse_of: :issue_type

  NAME_LENGTH_LIMIT = 64
  DESCRIPTION_LENGTH_LIMIT = 256
  ORGANIZATION_ISSUE_TYPES_LIMIT = 10

  DEFAULTS = [
    { name: "Task", description: "A specific piece of work", color: :yellow },
    { name: "Bug", description: "An unexpected problem or behavior", color: :red },
    { name: "Feature", description: "A request, idea, or new functionality", color: :blue },
  ]

  before_validation :set_type_and_color
  before_validation :strip_whitespace
  validates_presence_of :owner_id, :name
  validates_inclusion_of :enabled, in: [true, false], message: "can't be blank"
  validates_inclusion_of :color, in: COLORS.keys.map(&:to_s), message: "is not a valid color"

  validates :name,
    length: { maximum: NAME_LENGTH_LIMIT },
    uniqueness: { scope: :owner, case_sensitive: false },
    unicode: true
  validates :description, length: { maximum: DESCRIPTION_LENGTH_LIMIT }, unicode: true
  validate :reserved_name
  validate :issue_type_can_be_created, on: :create
  after_commit :reindex_issues, on: [:update, :destroy] # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_hydro_create_event, on: :create # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_hydro_update_event, on: :update # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_hydro_destroy_event, on: :destroy # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  def self.create_default_issue_types_for(orgs)
    orgs = Array.wrap(orgs)

    # Get the default types the org already has
    default_types = IssueType.select(:name, :owner_id)
      .where(owner: orgs, name: IssueType::DEFAULTS.pluck(:name))
      .group_by(&:owner_id)

    # Build a list of inserts using the defaults without the existing types
    inserts = orgs.map do |org|
      existing = default_types[org.id]&.map(&:name) || []
      DEFAULTS.map do |default|
        unless existing.include?(default[:name])
          {
              name: default[:name],
              issue_type: 0,
              color: default[:color],
              private: 0,
              enabled: 1,
              description: default[:description],
              owner_id: org.id,
          }
        end
      end
    end.flatten.compact

    # Bulk insert
    ActiveRecord::Base.connected_to(role: :writing) do
      IssueType.insert_all!(inserts)
    end
  end

  sig { returns(T::Hash[T.untyped, T.untyped]) }
  def memex_column_hash
    {
      id: id,
      name: name,
      description: description,
      color: color.upcase,
    }
  end
  alias_method :group_metadata, :memex_column_hash
  alias_method :slice_metadata, :memex_column_hash

  def memex_suggestion_hash(selected:)
    memex_column_hash.merge(selected: selected)
  end

  def issue_type
    :custom
  end

  # This matrix is created by the method `Organization.async_readable_issue_types_matrix`
  # We do this to prevent having to call this multiple times `
  def readable?(matrix = { private_allowed: false, disabled_allowed: false })
    return true if !private? && enabled?
    return false if !enabled? && !matrix[:disabled_allowed]
    return false if private? && !matrix[:private_allowed]
    true
  end

  sig { override.returns(String) }
  def csv_column_value
    name
  end

  private

  def reserved_name
    errors.add(:name, "is reserved") if name.present? && RESERVED_NAMES.include?(name.downcase)
  end

  def reindex_issues
    should_update = if transaction_include_any_action?([:update])
      self.previous_changes["name"].present? || self.previous_changes["enabled"].present?
    elsif transaction_include_any_action?([:destroy])
      true
    else
      false
    end

    Issues::ReindexIssuesForAssociationJob.enqueue(:issue_type, self.id) if should_update
  end

  def issue_type_can_be_created
    owner = self.owner
    is_owned_by_org = owner&.organization? || false

    if !is_owned_by_org
      errors.add(:owner, "Owner must be an organization")
      return is_owned_by_org
    end

    is_limit_reached = owner.issue_types.length >= ORGANIZATION_ISSUE_TYPES_LIMIT
    errors.add(:base, "Maximum number of issue types is reached for this organization") if is_limit_reached

    !is_limit_reached
  end

  # TODO: https://github.com/github/issues/issues/9372
  #   Currently the `IssueType.color` and `IssueType.issue_type` columns on the `IssueTypes` table
  #   are marked as not null, so we need to set a value. Eventually we'll either use these fields
  #   or remove them from the table, this method can then be removed if needed
  def set_type_and_color
    self.issue_type = 0
    # if the color isn't provided, set a default
    self.color = 0 if self.color.nil?
  end

  def strip_whitespace
    self.name = name.strip if name.present?
  end

  def modifying_user
    User.find_by(id: GitHub.context[:actor_id]) || User.ghost
  end

  def instrument_hydro_create_event
    GlobalInstrumenter.instrument "issue_type.create", {
      actor: modifying_user,
      issue_type: self,
    }
  end

  def instrument_hydro_update_event
    GlobalInstrumenter.instrument "issue_type.update", {
      actor: modifying_user,
      issue_type: self,
    }
  end

  def instrument_hydro_destroy_event
    GlobalInstrumenter.instrument "issue_type.destroy", {
      actor: modifying_user,
      issue_type: self,
    }
  end
end
