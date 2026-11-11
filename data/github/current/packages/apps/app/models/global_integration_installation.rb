# typed: true
# frozen_string_literal: true

class GlobalIntegrationInstallation
  include Ability::Actor
  include IntegrationInstallable
  include GitHub::Memoizer
  include ProgrammaticActor::AuthorizationDetailsGrantable

  AUTHZD_AUTHORIZATION_DETAILS_NAMESPACE = "installation.global"

  attr_reader :integration, :integration_id, :target, :target_id, :target_type

  delegate :single_file_name,
    :single_file_paths,
    :multiple_single_files?,
    to: :version

  sig { params(integration: Integration, target: T.any(Business, Organization, User)).void }
  def initialize(integration, target)
    @integration    = integration
    @integration_id = integration.id

    @target      = target
    @target_id   = target.id
    @target_type = target.class.name
  end

  def abilities(subject_types: [], subject_ids: [])
    Permission.none
  end

  def async_target
    Promise.resolve(target)
  end

  # Return as a Hash that matches the `authorization_details` column.
  memoize def authorization_details
    authorization_details_struct.serialize
  end

  memoize def authorization_details_struct
    struct = ScopedInstallations::AuthorizationDetails::Builder.build(version: 1)

    Permissions::ResourceRegistry.permissions_by_resource(self).each_pair do |resource_class, permissions|
      resource_string = resource_class.name.underscore.split("/").find do |string|
        ScopedInstallations::AuthorizationDetails::ResourceType.has_serialized?(string)
      end

      next if resource_string.nil?

      struct.add_permissions_selection(
        resource_type: ScopedInstallations::AuthorizationDetails::ResourceType.deserialize(resource_string),
        permissions: permissions,
        selection: ScopedInstallations::AuthorizationDetails::Selection::Global
      )
    end

    struct
  end

  def authzd_proto_attributes
    authorization_details_struct.authzd_proto_attributes + ScopedInstallations::AuthorizationDetails::AuthzdProtoAttributesSerializer.generate(
      struct: authorization_details_struct,
      namespace: AUTHZD_AUTHORIZATION_DETAILS_NAMESPACE
    )
  end

  def id
    self.integration_id
  end

  def self.for_target(integration, target)
    return unless target
    return unless Apps::Privileged.capable?(:installed_globally, app: integration)

    GlobalIntegrationInstallation.new(integration, target)
  end

  def self.for_repository(integration, repository)
    return unless Apps::Privileged.capable?(:installed_globally, app: integration)

    repo_owner = repository&.owner
    return if repo_owner.nil?

    installation = GlobalIntegrationInstallation.new(integration, repo_owner)
    Repository::Resources.filter(installation.permissions).any? ? installation : nil
  end

  def new_record?
    false
  end

  memoize def version
    integration.latest_version
  end
end
