# typed: true
# frozen_string_literal: true
# This class is essentially a wrapper around the PackageEvent class
# Only differences being the payload using `registry_package` key
# And the webhook event is called `registry_package`

class Hook::Event::RegistryPackageEvent < Hook::Event
  supports_targets *DEFAULT_TARGETS

  description "Registry package published or updated in a repository."

  event_attr :action, :actor_id, required: true
  event_attr :registry_package_id, :package_version_id, :registry_package, :version, :package_file, :pkg_subtype

  delegate :package, :package_version, :target_organization, :target_repository, :actor, :deliverable?, to: :package_event

  def package_event
    PackageEvent.new(@attributes)
  end
end
