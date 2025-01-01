# typed: true
# frozen_string_literal: true

class Hook::Event::PackageEvent < Hook::Event
  supports_targets *DEFAULT_TARGETS

  description "GitHub Packages published or updated in a repository."

  event_attr :action, :actor_id, required: true
  event_attr :registry_package_id, :package_version_id, :registry_package, :version, :package_file, :pkg_subtype

  def package
    @package ||= if is_a_v1_package?
      Api::Packages::PackageV1Adapter.new(
        Registry::Package.find_by(id: registry_package_id)
      )
    else
      Api::Packages::PackageEntityAdapter.new(
        Hydro::Schemas::RegistryMetadata::V0::Entities::Package.new(registry_package)
      )
    end
  end

  def package_version
    @package_version ||= if is_a_v1_package?
      Api::Packages::PackageVersionV1Adapter.new(
        package,
        Registry::PackageVersion.find_by(id: package_version_id)
      )
    else
      schema_files = []
      package_file.map do |file|
        schema_files.push(Hydro::Schemas::RegistryMetadata::V0::Entities::PackageFile.new(file))
      end
      pkg_subtype
      Api::Packages::PackageVersionEntityAdapter.new(
        Hydro::Schemas::RegistryMetadata::V0::Entities::Version.new(version),
        package,
        schema_files
      )
    end
  end

  # The organization the package belongs to. V2 packages are scoped to org, not repository.
  def target_organization
    return super if is_a_v1_package?

    Organization.find_by(login: package.namespace)
  end

  # The repository that this event is associated with. The delivery
  # system will use this to find subscribed repository and organization
  # hooks.
  #
  # This will automatically be included in hook payloads.
  def target_repository
    package.try(:repository)
  end

  # The user who performed the action.
  #
  # This will automatically be included in hook payloads.
  def actor
    @actor ||= User.find_by(id: actor_id)
  end

  def pkg_subtype
    @pkg_subtype ||= attributes[:pkg_subtype]
  end

  def deliverable?
    if is_a_v1_package?
      target_repository.present? && package.present?
    else
      package.present? && package_version.present? && actor.present?
    end
  end

  private

  def is_a_v1_package?
    attributes[:package_version_id].present?
  end

end
