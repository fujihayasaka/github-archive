# typed: true
# frozen_string_literal: true

class PreReceiveHookTarget < ApplicationRecord::Domain::PreReceive
  include Instrumentation::Model

  HOOKABLE_TYPES = %w(Repository User Business).freeze
  ALLOWED_SORT_STRINGS = %w(hook.id id hook.name priority)

  enum :enforcement, {
    disabled: GitHub::PreReceiveHookEntry::DISABLED,  # 0
    testing: GitHub::PreReceiveHookEntry::TESTING,    # 1
    enabled: GitHub::PreReceiveHookEntry::ENABLED,    # 2
  }

  belongs_to :hook, class_name: "PreReceiveHook"
  belongs_to :hookable, polymorphic: true
  validates_presence_of :hook
  validates_presence_of :hookable
  validates_inclusion_of :hookable_type, in: HOOKABLE_TYPES
  validates_uniqueness_of :hook_id, scope: [:hookable_id, :hookable_type]

  validates :enforcement, presence: true
  validates :enforcement, inclusion: { in: %w(disabled enabled) }, unless: -> do
    T.bind(self, PreReceiveHookTarget)
    hookable_type == "Business"
  end
  validates :enforcement, inclusion: { in: %w(disabled enabled testing) }, if: -> do
    T.bind(self, PreReceiveHookTarget)
    hookable_type == "Business"
  end

  accepts_nested_attributes_for :hook, update_only: true

  after_commit :instrument_enforcement_update, on: :update
  after_commit :instrument_enforcement_create, on: :create

  # Raised when an upstream target is :final => true
  class NotAllowedByUpstreamError < StandardError
  end

  scope :global, -> {
    where(hookable_id: GitHub.global_business.configuration_entry_id,
          hookable_type: GitHub.global_business.configuration_entry_type)
  }

  # Narrows scope to just the targets for the given hook_id
  scope :for_hook, -> (hook_id) { where(hook_id: hook_id) }

  # Sort by id, hook.id, hook.name and priority.  The first three are self-explanitory.  Sorting by priority sorts
  # targets in the order of enforcement priority.  Enforcement priority is based on the type of hookable and goes in
  # the order Business -> User -> Repository
  scope :sorted_by, -> (order, direction = nil) {
    direction = "DESC" == "#{direction}".upcase ? "DESC" : "ASC"
    order = "hook.id" unless ALLOWED_SORT_STRINGS.include?(order)
    select(<<-SQL)
      #{table_name}.*,
      CASE hookable_type
        WHEN 'Business'   THEN 0
        WHEN 'User'       THEN 1
        WHEN 'Repository' THEN 2
      END AS priority
    SQL
      .joins("JOIN pre_receive_hooks hook ON hook_id = hook.id")
      .readonly(false)
      .order(Arel.sql([order, direction].join(" ")))
  }

  # Limits scope to targets for the given hookable and that hookables parental lineage.
  scope :for_hookable_and_parents, -> (hookable) {
    hookable_query = where(hookable_id: hookable.configuration_entry_id,
                           hookable_type: hookable.configuration_entry_type)
    hookable.configuration_owners.uniq.compact.reduce(hookable_query) do |query, ancestor|
      query.or(where(hookable_id: ancestor.configuration_entry_id,
                     hookable_type: ancestor.configuration_entry_type))
    end
  }

  # Filters to just the targets that are visible to the hookable.  Meaning the targets that are either enabled or configurable.
  scope :visible_for_hookable, -> (hookable) {
    rel_types = -> (hookable1, child = false) {
      types = child ? HOOKABLE_TYPES : HOOKABLE_TYPES.reverse
      types.take(T.must(types.index(hookable1.configuration_entry_type)))
    }
    targets = for_hookable_and_parents(hookable)
    targets = targets.reject do |candidate|
      hook_targets = targets.find_all { |target| target.hook_id == candidate.hook_id }
      parent_targets = hook_targets.find_all { |t| rel_types.call(candidate.hookable).include?(t.hookable_type) }
      # Get rid of targets with final parents
      next true if parent_targets.any? { |target| target.final? }
      # Keep final targets because no children can override them
      next false if candidate.final?
      # Get rid of targets with children
      next true if hook_targets.any? { |t| rel_types.call(candidate.hookable, true).include?(t.hookable_type) }
      # Keep everything else
      false
    end
    effective_target_ids = targets.map(&:id)
    where(id: effective_target_ids)
      .where(
        "NOT (hookable_type IN (?) AND enforcement = (?) AND final = 1)",
        rel_types.call(hookable), PreReceiveHookTarget.enforcements[:disabled]
      )
  }

  def instrument_enforcement_create
    instrument :enforcement
  end

  def instrument_enforcement_update
    instrument :enforcement
  end

  def event_payload
    payload = {
      pre_receive_hook: hook,
      enforcement: GitHub::PreReceiveHookEntry::DESCRIPTIONS[self.class.enforcements[enforcement]],
      final: final ? "Enforced for #{hookable}" : "Can be overridden at lower level",
      repo: T.must(hook).repository,
      pre_receive_environment: T.must(hook).environment,
    }

    payload.merge!(hookable.event_context) if hookable.respond_to?(:event_context)
    payload
  end

  def hookable=(val)
    raise ArgumentError.new("Only hookable types are allowed") unless self.class.valid_hookable?(val)
    self.hookable_id = val.configuration_entry_id
    self.hookable_type = val.configuration_entry_type
  end

  def enforcement=(val)
    case val
    when /\A\d+\z/
      super(val.to_s.to_i)
    else
      super
    end
  end

  def enforcement_display
    enforcement.to_s
  end

  # allow_downstream_configuration is the opposite of final.  This is just for the convenience of making the api mirror the UI
  def allow_downstream_configuration
    !final
  end

  def allow_downstream_configuration=(val)
    write_attribute(:final, !val)
  end

  def event_prefix
    :pre_receive_hook
  end

  # For the given hookable and hook, this returns the target with the lowest granularity level that doesn't have a
  # final target upstream
  def self.enforcement_target(hookable, hook_id)
    raise ArgumentError.new("Only hookable types are allowed") unless valid_hookable?(hookable)
    chain = PreReceiveHookTarget.for_hook(hook_id).for_hookable_and_parents(hookable).sorted_by("priority")
    final_targets = chain.where(final: true)
    return chain.last if final_targets.blank?
    final_targets.first
  end

  # Find or create a target with the specified hook and hookable. If a new one is created it will be duplicated
  # from an upstream hookable if any exist. Attributes can optionally be updated using update_attributes
  def self.override_upstream_target(hookable, hook, update_attributes = {})
    tries = 2
    begin
      raise ArgumentError.new("Only hookable types are allowed") unless valid_hookable?(hookable)
      enforcement_target = PreReceiveHookTarget.enforcement_target(hookable, hook)
      raise ArgumentError.new("Only hooks with valid enterprise account targets are allowed") if enforcement_target.nil?
      if hookable == enforcement_target.hookable
        target = enforcement_target
        target.update! update_attributes
      elsif enforcement_target.allow_downstream_configuration
        target = enforcement_target.dup
        target.hookable = hookable
        target.update! update_attributes
      else
        raise NotAllowedByUpstreamError
      end
      target
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      retry if (tries -= 1) > 0
      raise e
    end
  end

  # Determines whether a potential hookable is actually a valid hookable based on its configuration_entry_type
  # To be a valid hookable, it must be a Configurable and have a configuration_entry_type of "Repository", "User" or "Business"
  def self.valid_hookable?(hookable)
    hookable.is_a? Configurable and HOOKABLE_TYPES.include? hookable.configuration_entry_type
  end
end
