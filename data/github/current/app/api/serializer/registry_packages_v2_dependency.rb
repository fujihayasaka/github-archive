# typed: false
# frozen_string_literal: true

module Api::Serializer::RegistryPackagesV2Dependency

  # Creates a Hash to be serialized to JSON.
  #
  # registry_package - Registry Package instance.
  # package_version  - Package Version instance.
  #
  # Returns a Hash if the Registry Package exists, or nil.
  def registry_package_v2_hash(hook_event, options)
    registry_package = hook_event.package
    package_version = hook_event.package_version
    return nil unless registry_package && package_version

    ecosystem = registry_package.ecosystem.to_s
    pkg_subtype = hook_event.pkg_subtype.to_s
    if pkg_subtype.present? && pkg_subtype == "actions"
      ecosystem = pkg_subtype.upcase
    end
    html_package_path = "/#{registry_package.namespace}/packages/#{registry_package.id}"
    {
        id: registry_package.id,
        name: registry_package.name,
        namespace: registry_package.namespace,
        description: registry_package.description,
        ecosystem: ecosystem,
        html_url: html_url(html_package_path),
        created_at: time(registry_package.created_at),
        updated_at: time(registry_package.updated_at),
        package_version: registry_package_version_v2_hash(registry_package, package_version),
    }
  end

  # Creates a Hash to be serialized to JSON.
  #
  # registry_package - Registry Package instance.
  # package_version  - Package Version instance.
  #
  # Returns a Hash if the package_version exists, or nil.
  def registry_package_version_v2_hash(registry_package, package_version)
    return nil if !package_version || !registry_package

    html_package_version_path = "/#{registry_package.namespace}/packages/#{registry_package.id}?version=#{package_version.id}"

    eco_metadata_label = "#{package_version.ecosystem.downcase}_metadata".to_sym
    eco_metadata = package_version.send(eco_metadata_label)

    {}.tap do |h|
      h[:id] = package_version.id
      h[:name] = package_version.name
      h[:description] = package_version.description
      h[:blob_store] = package_version.blob_store
      h[:html_url] = html_url(html_package_version_path)
      h[:created_at] = time(package_version.created_at)
      h[:updated_at] = time(package_version.updated_at)
      h[eco_metadata_label] = eco_metadata.to_h
    end.compact
  end
end
