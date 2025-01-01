# typed: true
# frozen_string_literal: true

class IntegrationVersion < ApplicationRecord::Domain::Integrations
  include GitHub::UserContent
  include GitHub::Validations

  extend GitHub::Encoding

  belongs_to :integration
  validates :integration_id, presence: true, on: :update

  # This attribute is used to indicate when this version is being
  # used to construct a scoped installation. Currently only used
  # to apply mandatory permissions
  attr_accessor :parent_installation

  # DefaultIntegrationPermissions representing the default permissions
  # that this integration requests at installation time.
  has_many :default_permission_records,
    class_name: "DefaultIntegrationPermission",
    dependent:  :destroy,
    autosave:   true,
    extend:     DefaultIntegrationPermission::AssociationExtension

  # HookEventSubscriptions representing the default event types that this
  # integration requests at installation time.
  has_many :default_event_records,
    as:         :subscriber,
    class_name: "HookEventSubscription",
    autosave:   true,
    extend:     HookEventSubscription::AssociationExtension

  # DEPRECATED, see: https://github.com/github/platform-ux/issues/1050
  #
  # IntegrationContentReferences representing the content references
  # that this integration requests to be notified of and have permission
  # to create content reference attachments for.
  has_many :content_references,
    class_name:   "IntegrationContentReference",
    dependent:    :destroy,
    autosave:     :true

  validates_length_of :content_references, maximum: 5

  has_many :single_files,
    class_name: "IntegrationSingleFile",
    dependent:  :destroy,
    autosave:   true

  validates_length_of :single_files, maximum: 10, message: "has too many files (maximum is 10)"

  validates :number, presence: true

  validates :note, length: { maximum: 240 }, allow_blank: true, unicode3: true

  validate :validate_default_events_are_supported
  validate :validate_matching_permissions_for_events
  validate :validate_single_file_permissions
  validate :validate_content_references
  validate :validate_preview_permissions_enabled

  before_validation :add_defaults_for_all_integrations, on: :create

  after_create :set_number!

  # Public: The collection of resources that this integration requests access to.
  #
  # Example
  #   permissions
  #   # => { "statuses" => :write, "issues" => :read }
  #
  # Returns a Hash
  def default_permissions
    default_permission_records.permission_map
  end

  def async_default_permissions
    async_default_permission_records.then do |default_permission_records|
      active_permissions = default_permission_records.select do |record|
        !record.marked_for_destruction?
      end

      active_permissions.each_with_object({}) do |record, memo|
        memo[record.resource] = record.action.to_sym
      end
    end
  end

  # Public: Set the collection of resources this integration requests access to.
  #
  # assigned_permissions - A Hash of resource Strings to permission Symbols.
  #
  # Returns the Hash of assigned permissions.
  def default_permissions=(assigned_permissions)
    default_permission_records.permission_map = assigned_permissions
  end

  # Public: The collection of event names that this integration subscribes to.
  #
  # Example
  #   events
  #   # => ["issues", "pull_request"]
  #
  # Returns an Array
  def default_events
    T.unsafe(default_event_records).names
  end

  def async_default_events
    async_default_event_records.then do |default_event_records|
      default_event_records.map(&:name)
    end
  end

  # Public: Set the collection of event names this integration should subscribe
  # to.
  #
  # event_names - An Array of event names.
  #
  # Returns an Array of subscribed event names.
  def default_events=(event_names)
    T.unsafe(default_event_records).names = event_names
  end

  # Public: The collection of content references that this integration
  # requests to be notified of and has permission
  # to create content reference attachments for.
  #
  # Example output
  #   content_references
  #   # => {"sentry.io" => "domain", "runkit.com" => "domain"}
  #
  # Returns a Hash
  def default_content_references
    content_references.map do |content_reference|
      [content_reference.value, content_reference.reference_type]
    end.to_h
  end

  # Public: Set the content references that this integration
  # requests to be notified of and has permission
  # to create content reference attachments for.
  #
  # Example input
  #   # => {"sentry.io" => "domain", "runkit.com" => "domain"}
  #
  # Returns an array of IntegrationContentReferences
  def default_content_references=(content_references)
    content_references.each do |value, reference_type|
      self.content_references.build(
        value: value,
        reference_type: reference_type,
      )
    end
  end

  def single_file_name=(name)
    # Create an IntegrationSingleFile record
    # and set the name on the `single_file_name`
    # column.
    single_files.build(version: self, path: name)
  end

  # To be removed once the single_file_name column is dropped
  # Part of https://github.com/github/ecosystem-apps/issues/335
  def single_file_name
    single_file_paths.first
  end

  # Public: The collection of paths this integration has
  # single file permissions for.
  #
  # Returns an Array
  def single_file_paths
    single_files.map(&:path)
  end

  # Public: Set the single file paths that this integration
  # has permission to.
  #
  # Returns an array of IntegrationSingleFiles
  def single_file_paths=(single_files)
    return unless integration
    single_files.each do |path|
      self.single_files.build(
        path: path,
        version: self,
      )
    end
  end

  def multiple_single_files?
    single_file_paths.length > 1
  end

  # Public: View the difference between two versions.
  #
  # old_version - The IntegrationVersion that is being compared
  #
  # Returns a IntegrationVersion::Differ::Result
  def diff(old_version)
    IntegrationVersion::Differ.perform(
      old_version: old_version,
      new_version: self,
    )
  end

  def permissions_of_type(resource_type)
    subject_types_for_resource = "#{resource_type}::Resources".constantize.send(:subject_types)
    default_permissions.select { |resource, _action| subject_types_for_resource.include?(resource) }
  end

  def permissions_relevant_to(target, installation_type: :integration_installation)
    case installation_type
    when :integration_installation
      return permissions_of_type(Business) if target.is_a?(Business)

      permissions = permissions_of_type(Repository)
      permissions.merge!(permissions_of_type(Organization)) if target.is_a?(Organization)
      permissions

    when :oauth_authorization
      return {} if target.is_a?(Business) || target.is_a?(Organization)
      permissions_of_type(User)
    else
      {}
    end
  end

  def all_permissions_of_type?(resource_type)
    return false if default_permissions.empty?
    permissions_of_type(resource_type) == default_permissions
  end

  def any_permissions_of_type?(resource_type)
    permissions_of_type(resource_type).any?
  end

  # Public: List the permissions listed under
  # User::Resources for this version.
  #
  # Returns an Array of resources and the corresponding action.
  def user_permissions
    permissions_of_type(User)
  end

  # used by GitHub::UserContent
  def body
    note
  end

  private

  def add_defaults_for_all_integrations
    defaults_for_all_integrations = Repository::Resources::DEFAULT_PERMISSIONS
    defaults_for_this_integration = Hash[default_permissions]
    self.default_permissions = defaults_for_this_integration.merge(defaults_for_all_integrations)
  end

  def validate_default_events_are_supported
    unsupported_events = default_events - Integration::Events::SUPPORTED_EVENTS

    if unsupported_events.any?
      errors.add(:default_events, "unsupported: #{unsupported_events.to_sentence}")
    end
  end

  def validate_matching_permissions_for_events
    return if default_events.blank?

    allowed_events = default_permissions.keys.inject([]) do |result, permission|
      result.concat Integration::Events.event_types_for_resource(
        permission,
        include_all_events: true,
      )
    end

    unmatching_event_types = default_events - allowed_events

    if unmatching_event_types.any?
      msg = "are not supported by permissions: #{unmatching_event_types.to_sentence}"
      errors.add(:default_events, msg)
    end
  end

  def validate_single_file_permissions
    if self.default_permissions.key?("single_file") && self.single_file_name.blank?
      errors.add(:single_file_name, "path is required.")
    elsif self.default_permissions.key?("single_file") && self.single_file_name.length > 255
      errors.add(:single_file_name, "is too long (max is 255 characters)")
    elsif !self.default_permissions.key?("single_file") && !self.single_file_name.blank?
      errors.add(:default_permissions, "access to single file is required.")
    end
  end

  def validate_content_references
    return if !self.default_permissions.key?("content_references") && self.content_references.none?
    return if self.default_permissions.key?("content_references") && !self.content_references.none?

    if self.content_references.none?
      errors.add(:content_references, "at least one reference is required.")
    elsif !self.default_permissions.key?("content_references")
      errors.add(:default_permissions, "access to content_references is required.")
    end
  end

  def validate_preview_permissions_enabled
    return unless integration
    actor = T.must(integration).owner

    missing_previews = self.default_permissions.keys.reject do |subject_type|
      Permissions::ResourceRegistry.subject_type_enabled_for?(
        subject_type: subject_type,
        actor: actor,
        integration: integration,
      )
    end

    return unless missing_previews.any?

    errors.add(:default_permissions, "#{missing_previews.to_sentence} are not supported permissions")
  end

  # Finds and sets the next number in the sequence scoped by
  # integration_id - this works exactly like Issue numbers
  def set_number!
    sql = Arel.sql(<<-SQL, integration_id: integration_id)
      SELECT MAX(number) + 1 AS num FROM integration_versions WHERE integration_id = :integration_id FOR UPDATE
    SQL
    update_attribute(:number, self.class.connection.select_value(sql))
  end
end
