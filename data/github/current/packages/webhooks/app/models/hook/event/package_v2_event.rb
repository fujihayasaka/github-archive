# typed: true
# frozen_string_literal: true

class Hook::Event::PackageV2Event < Hook::Event
  supports_targets *DEFAULT_TARGETS

  description "As of June 2021 this event is deprecated. Please use the \"Packages\" event instead."

  event_attr :registry_package, :version, :action, :actor_id, required: true
  event_attr :pkg_subtype

  # Should be passed in fully qualified from the original webhook request
  def package
    Hydro::Schemas::RegistryMetadata::V0::Entities::Package.new(registry_package)
  end

  # Should be passed in fully qualified from the original webhook request
  def package_version
    pkg_subtype
    Hydro::Schemas::RegistryMetadata::V0::Entities::Version.new(version)
  end

  # The organization the package belongs to. V2 packages are scoped to org, not repository.
  def target_organization
    Organization.find_by(login: package.namespace)
  end

  # The user who performed the action.
  #
  # This will automatically be included in hook payloads.
  def actor
    @actor ||= User.find(actor_id)
  end

  def deliverable?
    package.present? && package_version.present? && actor.present?
  end

  def pkg_subtype
    @pkg_subtype ||= attributes[:pkg_subtype]
  end
end
