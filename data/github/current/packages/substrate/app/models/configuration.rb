# typed: true
# frozen_string_literal: true

# Object representing arbitrary entity-specific configuration values.
#
# Configuration respects a chain of priority from repository to repository
# owner, all the way up to a global entity. For example, if a repository has no
# configuration entry, we look for one on its owner. A "final" flag is
# available to force always reading a configuration entry from a lower-priority
# entity (such as an organization instead of a repository).
#
# Values are stored as strings, so users must encode/decode in their config
# implementation, if necessary.
class Configuration
  FALSE = "false".freeze
  TRUE  = "true".freeze

  class ConflictingRecordError < ArgumentError
    attr_reader :setting_name

    def initialize(setting_name:)
      @setting_name = setting_name
    end
  end

  # Internal: Minimal AR class to persist the configuration values
  # Consider this an implementation detail
  class Entry < ApplicationRecord::Domain::ConfigurationEntries
    self.table_name = "configuration_entries"

    include GitHub::Validations
    KEY_MAX_LENGTH = 80
    VALUE_MAX_LENGTH = 255

    # keys for attributes that don't constitute a functional change to the
    # configuration entry
    NON_VALUE_ATTRIBUTES = %w(updater_id).freeze

    belongs_to :target, polymorphic: true
    belongs_to :updater, class_name: "User", optional: false

    validates_length_of :name, maximum: KEY_MAX_LENGTH
    validates_length_of :value, maximum: VALUE_MAX_LENGTH

    validates :name, unicode3: true
    validates :value, unicode3: true

    scope :targeting_type, ->(type) { where(target_type: type) }
    scope :global, -> { targeting_type("global").for_target_id(0) }
    scope :targeting_users, -> { targeting_type("User") }
    scope :targeting_repositories, -> { targeting_type("Repository") }
    scope :targeting_businesses, -> { targeting_type("Business") }
    scope :targeting_memex_projects, -> { targeting_type("MemexProject") }
    scope :for_target_id, ->(target_id) { where(target_id: target_id) }
    scope :targeting_user_ids, ->(user_ids) { targeting_users.for_target_id(user_ids) }
    scope :targeting_repository_ids, ->(repo_ids) { targeting_repositories.for_target_id(repo_ids) }
    scope :targeting_business_ids, ->(business_ids) { targeting_businesses.for_target_id(business_ids) }
    scope :named, ->(name) { where(name: name) }
    scope :memex_project_org_wide_role, -> { named(MemexProject::ORGANIZATION_WIDE_ROLE_CONFIG_KEY) }
    scope :with_value, ->(value) { where(value: value) }
    scope :with_true_value, -> { with_value(TRUE) }
    scope :with_value_less_than, ->(value) { where("CONVERT(`value`, SIGNED INTEGER) < CONVERT(?, SIGNED INTEGER)", value) }

    sig { params(targets: T::Enumerable[Configurable]).returns(ActiveRecord::Relation) }
    def self.prioritized_for_targets(targets)
      return none if targets.none?

      target_conditions =
        Arel::Nodes::Or.new(
          targets.map do |target|
            id, type = target.configuration_entry_id, target.configuration_entry_type
            Arel.sql("(target_id = :id AND target_type = :type)", id:, type:)
          end.uniq
        )

      select(<<~SQL).
          name, value, final, target_type, target_id,
          CASE target_type
          WHEN 'global'     THEN 0
          WHEN 'Business'   THEN 1
          WHEN 'User'       THEN 2
          WHEN 'Repository' THEN 3
          END AS priority
          SQL
        where(target_conditions).
        order("priority ASC")
    end

    def target
      return GitHub if target_type == "global"
      super
    end

    include Instrumentation::Model

    def event_prefix() :config_entry end

    # If we're destroying the record, actor in #event_payload is superseded by the actor passed in
    # #instrument_destroy, which if we're being called from a cascading destroy will be nil. So we can avoid
    # loading the updater association
    private def actor
      destroyed? ? destroyer : updater
    end

    def event_payload
      payload = {
        target_type: target_type,
        target_id: target_id,
        name: name,
        value: value,
        final: final,
        actor: actor,
      }

      payload[target.event_key] = target if target.try(:event_key)

      if %w[User Organization Repository Business].include?(target_type)
        payload.merge!(target.event_context)
      end

      payload
    end

    after_create_commit  :instrument_create
    after_update_commit  :instrument_update
    after_destroy_commit :instrument_destroy

    def instrument_create
      instrument :create
    end

    def instrument_update
      instrument :update, old_value: value_before_last_save
    end

    # Used for :destroy instrumentation, to keep track of who's removing the entry
    attr_accessor :destroyer
    def instrument_destroy
      instrument :destroy, actor: destroyer
    end

    def value_attributes_changed?
      (changed_attribute_names_to_save - NON_VALUE_ATTRIBUTES).any?
    end
  end

  # Internal: Bulk-load configuration entries for a collection of Configurable model instances with a small number
  # of database queries. For public-facing access to this functionality, see Configurable.preload_configuration().
  #
  # Returns a Hash mapping target instances to Hashes of Configuration::Entries for each instance.
  def self.fetch_entries_for_targets(targets)
    entries_by_target = Hash.new { |h, k| h[k] = {} }
    return entries_by_target if targets.empty?

    # Load all configuration owner chains with the least number of queries. If "targets" includes many repos with the
    # same organization as an owner, for example, this will only fetch it once.
    owner_chains = Promise.all(targets.map(&:async_configuration_owners)).sync

    # Hash used to map which entries_by_target collections to update for any given entry based on its target info.
    #
    # Because we fetch entries associated with all targets and each *unique* entry in their ownership chains, a single
    # entry result may be associated with multiple targets. For example, given two repositories r0 and r1 within the
    # same org o0, we'll query entries that target (r0, r1, o0), then apply the results for r0 to r0, r1 to r1, and o0
    # to both r0 and r1.
    #
    # The keys of this Hash are Strings of the form "#{target_id}\0#{target_type}" and its values are Arrays of
    # Configurable entries found in `targets`.
    targets_for_entry = Hash.new { |h, k| h[k] = [] }

    # Gather all distinct targets, including owners. Used to generate the query SQL.
    all_targets = Set.new

    targets.zip(owner_chains) do |target, owner_chain|
      (owner_chain + [target]).each do |owner|
        targets_for_entry["#{owner.configuration_entry_id}\0#{owner.configuration_entry_type}"] << target
        all_targets.add(owner)
      end
    end

    # Iterate over each configuration entry in reverse priority order and populate the entries Hash corresponding to
    # each matching target. Halt early if a lower-priority entry has a "final" flag (indicating we should ignore
    # higher-priority entries).
    Entry.prioritized_for_targets(all_targets).each do |entry|
      targets_for_entry["#{entry.target_id}\0#{entry.target_type}"].each do |target|
        entries = entries_by_target[target]
        current = entries[entry.name]
        next if current&.final?
        entries[entry.name] = entry
      end
    end

    entries_by_target
  end

  def initialize(target, entries: nil)
    @target = target
    @entries = entries
  end

  # Internal: Get a snapshot of the current configuration
  # Handles whatever cascading or overridding is appropriate
  #
  # Returns a Hash of name => value pairs,
  # where name is a String and value is a Configuration::Entry object (with partial data)
  def entries
    return @entries if @entries

    next_entries = async_load_entries.sync

    # memoization is sketchy on the global object, so don't use it
    if @target != GitHub
      @entries = next_entries.freeze
    end

    next_entries
  end

  def async_load_entries
    entries = {}

    @target.async_configuration_owners.then do |configuration_owners|
      targets = [*configuration_owners, @target].compact.uniq

      # Iterate over each configuration entry in reverse priority order, halting
      # early if a lower-priority entry has a "final" flag (indicating we should
      # ignore higher-priority entries).
      Entry.prioritized_for_targets(targets).each do |entry|
        current = entries[entry.name]
        next if current && current.final?
        entries[entry.name] = entry
      end

      entries
    end
  end

  # Internal: Reset the snapshot of the current configuration
  # The next call to `#entries` will get an updated snapshot
  #
  # Returns nothing
  def reset
    @entries = nil
  end

  # Public: Has this configuration's entries been lazily populated yet?
  #
  # Returns true if the entries have been populated already, false otherwise
  def loaded?
    !@entries.nil?
  end

  # Public: Get a hash representation of the current configuration snapshot
  #
  # Returns a Hash of name => value pairs, where both name and value are Strings
  def to_hash
    result = {}
    configs = entries  # memoization can only do so much
    configs.each_key { |k| result[k] = configs[k].value }
    result
  end

  # Public: Enable a configuration flag by setting the value to "true".
  #
  # name    - String entry name
  # updater - User setting the value
  #
  # Returns true if the configuration changed, false otherwise
  def enable(name, updater)
    set(name, TRUE, updater)
  end

  # Public: Enable a configuration flag by setting the value to "true",
  # but use set! to override lower values.
  #
  # name    - String entry name
  # updater - User setting the value
  # final   - Boolean determining if this overrides lower values (default: true)
  #
  # Returns true if the configuration changed, false otherwise
  def enable!(name, updater, final = true)
    set!(name, TRUE, updater, final)
  end

  # Public: Is this entry enabled?
  #
  # name - String entry name
  #
  # Returns true or false.
  def enabled?(name)
    get(name) == TRUE
  end

  # Public: Disable a configuration flag by setting the value to "false".
  # To remove the flag completely use delete.
  #
  # name    - String entry name
  # updater - User setting the value
  #
  # Returns true if the configuration changed, false otherwise
  def disable(name, updater)
    set(name, FALSE, updater)
  end

  # Public: Disable a configuration flag by setting the value to "false" using
  # set! to override lower values.  To remove the flag completely use delete.
  #
  # name    - String entry name
  # updater - User setting the value
  # final   - Boolean determining if this overrides lower values (default: true)
  #
  # Returns true if the configuration changed, false otherwise
  def disable!(name, updater, final = true)
    set!(name, FALSE, updater, final)
  end

  # Public: Get the configuration value for a given key
  #
  # name - String entry name
  #
  # Note: Translates a value of "false" to false
  #
  # Returns a String, nil, or false
  def get(name)
    # BUG: Linter false positive using different raw() helper.
    value = raw(name) # rubocop:disable Rails/OutputSafety
    return false if value == FALSE

    value
  end

  # Public: Get the configuration value for a given key as an integer
  #
  # name - String entry name
  #
  # Returns a Integer or nil
  def int(name)
    get(name).try(:to_i)
  end

  # Public: Get the raw configuration value for a given key
  #
  # name - String entry name
  #
  # Returns a String or nil
  def raw(name)
    entry = entries[name.to_s]
    entry && entry.value
  end

  # Public: Check if the configuration for the given key is final
  #
  # name - String entry name
  #
  # Returns a Boolean
  def final?(name)
    entry = entries[name.to_s]
    entry && entry.final?
  end

  # Public: Check if the configuration entry can be written to on this object
  #
  # name - String entry name
  #
  # Returns a Boolean
  def writable?(name)
    !inherited?(name) || !final?(name)
  end

  # Public: Check if the configuration for the given key is set on the current object
  #
  # name - String entry name
  #
  # Returns a Boolean
  def local?(name)
    entry = entries[name.to_s]
    # check using the non-association `target_*` data to
    # avoid n+1 and issues loading the target association in async contexts
    entry &&
      entry.target_id == @target.configuration_entry_id &&
      entry.target_type == @target.configuration_entry_type
  end

  # Public: Check if the configuration for the given key is set on another object
  #
  # name - String entry name
  #
  # Returns a Boolean
  def inherited?(name)
    entry = entries[name.to_s]
    # check using the non-association `target_*` data to
    # avoid n+1 and issues loading the target association in async contexts
    entry &&
      (entry.target_id != @target.configuration_entry_id ||
        entry.target_type != @target.configuration_entry_type)
  end

  # Public: The object a given key was set on
  #
  # name - String entry name
  #
  # Returns a Configurable
  def source(name)
    entry = entries[name.to_s]
    entry && entry.target
  end

  # Public: Set a configuration value for a given key
  #
  #   name    - String for the entry name
  #   value   - String for the entry value
  #   updater - User setting the value
  #
  # Returns true if the configuration changed, false otherwise
  def set(name, value, updater, &block)
    entry = find_or_initialize_entry_by_name(name)

    entry.final = false
    entry.value = value
    entry.updater = updater

    yield entry if block

    # If the only changes were non-functional, the configuration entry
    # wasn't really updated, reset the configuration and move along.
    unless entry.value_attributes_changed?
      reset
      return false
    end

    begin
      entry.save!
    rescue ActiveRecord::RecordNotUnique
      # If in the time between when we've attempted to find an existing entry and persist a new entry,
      # an entry with the same target and name has already been created in a competing process, reset
      # the entry cache and check the value of the existing entry. If the value is the same as the
      # one we're attempting to persist, return false, otherwise raise a ConflictingRecordError.
      reset

      if raw(name) == value # rubocop:disable Rails/OutputSafety
        return false
      else
        raise ConflictingRecordError.new(setting_name: name)
      end
    else
      reset
    end

    true
  end

  # Public: Set a configuration value for a given key, which by default will
  # override lower values instead of being overridden.
  #
  # Uses the overly-clever block argument, which will not be discussed further.
  #
  #   name    - String for the entry name
  #   value   - String for the entry value
  #   updater - User setting the value
  #   final   - Boolean determining if this overrides lower values (default: true)
  #
  # Returns true if the configuration changed, false otherwise
  def set!(name, value, updater, final = true)
    set(name, value, updater) { |e| e.final = final }
  end

  # Public: Remove a configuration value for a given key
  #
  #   name    - String entry name
  #   deleter - User removing the value
  #             (optional, for now)
  #
  # Returns true if the entry was deleted, false otherwise
  def delete(name, deleter = nil)
    entry = find_entry_by_name(name)
    return false unless entry

    entry.destroyer = deleter
    entry.destroy!

    true
  ensure
    reset
  end

  private

  def find_entry_by_name(name)
    @target.configuration_entries.find_by(name: name.to_s)
  end

  def find_or_initialize_entry_by_name(name, &)
    @target.configuration_entries.find_or_initialize_by(name: name.to_s, &)
  end
end
