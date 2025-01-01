# typed: false
# frozen_string_literal: true

# MigratableResource is used when exporting or importing to or from a GitHub
# instance. Each record maps a model and it's url to a migration guid and
# model_type, and eventually it's model_id and target_url.
class MigratableResource < ApplicationRecord::Domain::Migrations
  include GitHub::Relay::GlobalIdentification

  self.table_name = "migratable_resources_v2"

  validates :guid, presence: true
  validates :model_type, presence: true
  validates :source_url, presence: true

  # Public: Scope to guid.
  scope :for_guid, ->(guid) { where(guid: guid) } do

    # Public: Find or initialize MigratableResource for source_url and
    # optionally yield block with record if given a block.
    #
    # source_url - String url
    #
    # Returns a MigratableResource.
    def by_source_url(source_url)
      migratable_resource = begin
        where(source_url: source_url).first || new(source_url: source_url)
      rescue ActiveRecord::RecordNotUnique
        retry # rubocop:disable GitHub/UnboundedRetries https://github.com/github/github/issues/134037
      end

      yield(migratable_resource) if block_given?

      migratable_resource
    end

    # Public: Find a migratable_resource by the model it represents.
    #
    # model - Instance of a github model.
    #
    # Returns a MigratableResource.
    def by_model(model)
      where({
        model_type: model.class.name.underscore,
        model_id: model.id,
      }).first
    end

    # Public: Update state for a group of migratable resources in one query.
    #
    # state - Symbol of state to set.
    # migratable_resources - Array of migratable resources.
    # warning - Optional warning message to set.
    #
    # Returns an Integer.
    def set_state!(state, migratable_resources, warning = nil)
      attributes = {
        state: state
      }

      attributes[:warning] = warning if warning.present?

      where({
        id: migratable_resources.map(&:id),
      }).update_all(attributes)
    end

    # Public: Return the guid being used in the scope.
    #
    # Returns a String.
    def guid
      where_values_hash["guid"]
    end

    # Public: Return true if migratable resource states are all considered final.
    # Otherwise return false.
    #
    # Returns a Boolean.
    def in_progress?
      not_final.any?
    end
  end

  # Public: Scope to model_type.
  scope :by_model_type, ->(model_type) { where(model_type: model_type) }

  # Public: Scope to states.
  scope :by_states, ->(*states) { where(state: MigratableResource.states.values_at(*states.flatten)) }

  # Public: Scope to records that are in a :import or :rename state.
  scope :will_create_model, -> {
    by_states(:import, :rename)
  }

  # Public: Scope to records that are in a good final state (except :exported).
  scope :migrated, -> {
    by_states(:imported, :mapped, :renamed, :merged)
  }

  # A MigratableResource has state. Migratable resources move from a pending
  # state to an optimal or failed state during export and import processes.
  #
  # Examples:
  #  :export => :exported
  #  :rename => :failed_rename
  #
  # At this time there is no support for moving from a failed state back to a
  # pending state.
  #
  # NOTE: State scopes all start with `state_`, e.g. `state_map` and `state_export`.
  # Required because states like `map` and `merge` conflict with methods defined by Arel
  # and ActiveRecord
  enum :state, {
    # pending states
    export:         0,
    import:         1,
    map:            2,
    rename:         3,
    merge:          4,
    conflict:       5,
    skip:           6,
    # optimal (final) states
    exported:       10,
    imported:       11,
    mapped:         12,
    renamed:        13,
    merged:         14,
    skipped:        15,
    # failed (final) states
    failed_export:  20,
    failed_import:  21,
    failed_map:     22,
    failed_rename:  23,
    failed_merge:   24,
    failed_skip:    25,
  }, prefix: true

  # Due to the `prefix` option above, helper methods are actually prefixed with `state_` (`state_conflict?`).
  # To help keep as much existing code as possible, fix these methods back to the non prefixed version
  # where we don't conflict.
  MigratableResource.states.each_key do |key|
    alias_method "#{key}?", "state_#{key}?"
    alias_method "#{key}!", "state_#{key}!"

    # Allow state-machine-like state methods to set the
    # state by method name.
    define_method(key) do
      self.state = key
    end
  end

  FINAL_STATES = %w(
    exported imported mapped renamed merged skipped failed_export failed_import
    failed_map failed_rename failed_merge failed_skip
  ).freeze

  SUCCEEDED_STATES = %w(exported imported mapped renamed merged skipped).freeze

  FAILED_STATES = %w(
    failed_export failed_import failed_map failed_rename failed_merge
    failed_skip
  ).freeze

  MAPPED_STATES = %w(map rename merge skip).freeze

  scope :succeeded, -> { where(state: states.values_at(*SUCCEEDED_STATES)) }
  scope :failed, -> { where(state: states.values_at(*FAILED_STATES)) }
  scope :not_mapped, -> { where("state not in (?)", states.values_at(*MAPPED_STATES)) }
  scope :not_final, -> { where("state not in (?)", states.values_at(*FINAL_STATES)) }

  # Public: Finds and returns the model instance.
  def model
    return unless model_type && model_id

    klass = model_type.camelcase.constantize
    klass.find(model_id)
  end

  # Public: Should the source be imported?
  #
  # Returns a TrueClass or FalseClass.
  def should_import?(with_model = model)
    %w(import rename failed_import failed_rename).include?(state) && with_model.blank?
  end

  # Public: Should the source be merged with the target?
  #
  # Returns a TrueClass or FalseClass.
  def should_merge?(with_model = model)
    merge? && with_model.present?
  end

  # Public: Should the source be mapped to the target?
  #
  # Returns a TrueClass or FalseClass.
  def should_map?(with_model = model)
    map? && with_model.present?
  end

  # Public: Is in a failed state?
  #
  # Returns a TrueClass or FalseClass.
  def failed?
    FAILED_STATES.include?(state)
  end

  # Public: Is in a succeeded state?
  #
  # Returns a TrueClass or FalseClass.
  def succeeded?
    SUCCEEDED_STATES.include?(state)
  end

  # Public: Support migrating the owners team. Remove this and the code where
  # it is used as soon as direct-org membership has shipped.
  def should_merge_owners_team?
    model_type == "team"   and
    model.present?         and
    model.name == "Owners" and
    import?
  end

  # Public: Find models for migratable_resources and return them in an Array
  #
  # Raises a RuntimeError if all MigratableResources don't have the same model type.
  #
  # migratable_resources    - Array of MigratableResources. Must have the same model type.
  # scope                   - An ActiveRecord or ActiveRecord::Relation to find the models,
  #                           usually obtained from a child class implementation of
  #                           BaseSerializer#scope. If nil, will use a class object derived
  #                           from the model name of the first MigratableResource.
  #
  # Returns an Array of ActiveRecords
  def self.models_for_migratable_resources(migratable_resources, scope: nil)
    model_types = migratable_resources.map(&:model_type).uniq
    raise "migratable resources must have same model_type" if model_types.size > 1

    if scope.nil?
      scope = model_types.first.camelize.constantize
    end
    # sort by the order of the migratable_resources if type is team to ensure
    # the parents team are serialized first
    if model_types.first == "team"
      scope.where(id: migratable_resources.map(&:model_id).compact).sort_by do |model|
        migratable_resources.find { |migratable_resource| migratable_resource.model_id == model.id }.id
      end
    else
      scope.where(id: migratable_resources.map(&:model_id).compact)
    end
  end
end
