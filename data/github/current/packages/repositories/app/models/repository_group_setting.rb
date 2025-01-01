# typed: true
# frozen_string_literal: true

class RepositoryGroupSetting < ApplicationRecord::Domain::Repositories
  extend T::Helpers
  abstract!

  # column :value is the setting hash for this specific path only
  attr_accessor :inherited # hash values of that parent node this node inherits from
  attr_accessor :composite # composite hash value of inherited + local value

  belongs_to :repository_group
  belongs_to :orchestration, class_name: "SettingOrchestration"
  delegate :group_path, to: :repository_group
  delegate :owner, to: :repository_group

  after_initialize :populate_attributes
  validates_presence_of :repository_group

  def group
    repository_group
  end

  def populate_attributes
    # for sub classes to initialize their value attribute
  end

  # Apply a bunch of settings to all repositories in the group
  def self.orchestrate_all(actor, settings)
    raise ArgumentError, "No settings provided" if settings.empty?

    # all settings must be in the same group
    group = settings.first.group
    settings.each do |setting|
      raise ArgumentError, "All settings must be in the same group" unless setting.group == group
    end

    # we want to queue a single orchestration for all settings
    orchestration = SettingOrchestration.from_group(actor.id, group, settings.map(&:class).map(&:to_s))

    # record the orchestration before kicking it off
    settings.each do |setting|
      setting.orchestration_id = orchestration.id
      setting.save
    end

    orchestration.execute!
    orchestration.reload
  end

  # apply a specific setting to all repositories in the group
  def orchestrate(actor)
    RepositoryGroupSetting.orchestrate_all(actor, [self])
  end

  # Apply a specific setting to a specific repository
  # Subclasses must define how to apply their setting to a repository
  sig do
    abstract.params(actor: User, repository: Repository)
    .returns(T.untyped)
  end
  def apply(actor:, repository:); end

  # Create a new setting and add it to the group.
  # Create the group if it does not exist.
  sig do
    params(owner: User, group_path: String, value: T.untyped)
    .returns(T.attached_class)
  end
  def self.add(owner, group_path, value = nil)
    repository_group = RepositoryGroup.find_or_create_group(owner:, group_path:)
    setting = self.find_or_create_by!(repository_group:, type: self)
    if value
      setting.value = value
      setting.save!
    end
    T.cast(setting, T.attached_class)
  end

  # Load the settings for the repository
  sig { params(repository: T.nilable(Repository)).returns(T.nilable(T.attached_class)) }
  def self.for_repository(repository)
    return nil unless repository&.owner&.feature_enabled?(:repos_groups)
    return nil unless repository&.group
    settings = load_all_by_group(repository.group)
    T.cast(settings[T.must(self.name)], T.nilable(T.attached_class))
  end

  sig do
    params(repository_group: T.nilable(RepositoryGroup))
    .returns(T.nilable(T.attached_class))
  end
  def self.load_by_group(repository_group)
    settings = self.load_all_by_group(repository_group)
    T.cast(settings[T.must(self.name)], T.nilable(T.attached_class))
  end

  sig do
    params(repository_group: T.nilable(RepositoryGroup))
    .returns(T::Hash[String, RepositoryGroupSetting])
  end
  def self.load_all_by_group(repository_group)
    return {} unless repository_group
    path = repository_group.group_path

    where_type = self == RepositoryGroupSetting ? "" : "WHERE gs.type = :type"

    # always load the settings at the root, where group_path = ""
    text = <<-SQL
      SELECT gs.type, gs.*, rg.group_path
      FROM  repository_group_settings gs
      JOIN  repository_groups rg
      ON    rg.id = gs.repository_group_id
      AND   rg.owner_id = :owner_id
      AND   rg.group_path = ""
      #{where_type}
    SQL
    unless path.blank?
      # if path is not blank, then load all settings that are in or above the path
      text += <<-SQL
        UNION ALL
        SELECT gs.type, gs.*, rg.group_path
        FROM  repository_group_settings gs
        JOIN  repository_groups rg
        ON    rg.id = gs.repository_group_id
        AND   rg.owner_id = :owner_id
        AND   :group_path LIKE CONCAT(rg.group_path, "/%")
        #{where_type}
        ORDER BY group_path ASC
      SQL
    end

    query = Arel.sql(text, owner_id: repository_group.owner_id, group_path: path + "/", type: self.name)

    all_records = RepositoryGroupSetting.find_by_sql(query)

    # convert from a flat array to a hash of arrays by setting type
    settings_ancestry = {}
    all_records.each do |setting|
      settings_ancestry[setting.type] ||= []
      settings_ancestry[setting.type] << setting
    end

    # aggregate the settings ancestry into a hash, one aggregated setting per type
    settings = {}
    settings_ancestry.each do |type, ancestors|
      settings[type] = aggregate_records(repository_group, ancestors)
    end

    settings
  end

  sig { returns(T.untyped) }
  def reload_values
    new_object = T.must(self.class.load_by_group(self.group))
    self.value = new_object.value
    self.inherited = new_object.inherited
    self.composite = new_object.composite
    new_object
  end

  # aggregate the inherited and local value into a single class with composite/effective settings
  sig do
    params(repository_group: RepositoryGroup, records: T::Array[RepositoryGroupSetting])
    .returns(T.nilable(RepositoryGroupSetting))
  end
  def self.aggregate_records(repository_group, records)
    all_values = records.map(&:value)

    # find our specific record
    setting = records.find { |r| r.repository_group_id == repository_group.id }

    if setting.nil?
      # There is no setting defined for this exact query path
      # If we have 0 records, that means we inherit nothing, so we should return nil
      return nil if records.blank?

      # otherwise we inherit settings and we should return those
      klass = records[0].class
      setting = T.unsafe(klass).new(repository_group:, value: {})
    end

    T.must(setting).composite = aggregate_settings(all_values)
    all_values.delete(T.must(setting).value)
    T.must(setting).inherited = aggregate_settings(all_values)
    setting
  end

  # Aggregate a list of settings into a single hash
  # Settings are ordered by group_path, starting with the root and working down to the leaf node
  sig do
    params(settings: T::Array[T::Hash[String, T.untyped]])
    .returns(T::Hash[String, T.untyped])
  end
  def self.aggregate_settings(settings)
    hash = {}
    settings.each do |setting|
      setting.each do |k, v|
        if v.is_a?(Hash)
          hash[k] ||= {}
          v.each do |kk, vv|
            combine_hash(hash[k], kk, vv)
          end
        else
          combine_hash(hash, k, v)
        end
      end
    end
    hash
  end

  # Combine key/value pairs into a hash by adding the values of the same key together, and removing duplicates
  # So if the input hash has { color: ["red"] } and we pass in { color: ["red", "blue"] }
  # the hash will become { color: ["red", "blue"] }
  sig do
    params(hash: T::Hash[String, T.untyped], key: String, value: T.untyped)
    .returns(T::Hash[String, T.untyped])
  end
  def self.combine_hash(hash, key, value)
    hash[key] ||= []
    hash[key] << value
    hash[key] = hash[key].flatten.uniq
    hash
  end

  class ForbiddenError < StandardError
    attr_reader :message

    def initialize(message)
      @message = message
    end
  end
end
