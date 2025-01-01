# typed: false
# frozen_string_literal: true
module Api::Serializer::RegistryPackagesDependency

  # Creates a Hash to be serialized to JSON.
  #
  # registry_package - Registry Package instance.
  # package_version  - Package Version instance.
  #
  # Returns a Hash if the Registry Package exists, or nil.
  def registry_package_hash(hook_event, options)
    registry_package = hook_event.package
    package_version = hook_event.package_version
    return nil unless registry_package && package_version
    package_type = registry_package.package_type
    ecosystem = registry_package.ecosystem.to_s
    pkg_subtype = hook_event.pkg_subtype.to_s
    registry = registry_package.source_registry
    if pkg_subtype.present? && pkg_subtype == "actions"
      package_type = pkg_subtype.upcase
      ecosystem = pkg_subtype.upcase
      registry[:type] = pkg_subtype.upcase if !registry.empty? && registry[:type].present?
    end
    html_package_path = "/#{registry_package.namespace}/packages/#{registry_package.id}"
    {
      id: registry_package.id,
      name: registry_package.name,
      namespace: registry_package.namespace,
      description: registry_package.description,
      ecosystem: ecosystem,
      package_type: package_type,
      html_url: html_url(html_package_path),
      created_at: time(registry_package.created_at),
      updated_at: time(registry_package.updated_at),
      owner: simple_user_hash(registry_package.owner, options),
      package_version: registry_package_version_hash(registry_package, package_version, options),
      registry: registry,
    }
  end

  # Creates a Hash to be serialized to JSON.
  #
  # registry_package - Registry Package instance.
  # package_version  - Package Version instance.
  #
  # Returns a Hash if the package_version exists, or nil.
  def registry_package_version_hash(registry_package, package_version, options)
    return nil if !package_version || !registry_package

    target_oid = package_version&.release&.tag&.target&.oid
    target_commitish = package_version&.release&.target_commitish
    unless target_oid.present?
      target_oid = registry_package.repository&.default_oid
      target_commitish = registry_package.repository&.default_branch
    end

    {}.tap do |h|
      h[:id] = package_version.id
      h[:version] = package_version.version
      h[:name] = package_version.name
      h[:description] = package_version.description
      h[:summary] = package_version.summary
      h[:body] = registry_package_version_body_sanitize(package_version.body)
      h[:body_html] = package_version.body_html
      h[:release] = registry_package_version_release_hash(registry_package, package_version, options) if package_version.release
      h[:manifest] = package_version.package_manifest
      h[:html_url] = html_url(package_version.html_uri)
      h[:tag_name] = package_version&.release&.exposed_tag_name
      h[:target_commitish] = target_commitish
      h[:target_oid] = target_oid
      h[:draft] = package_version&.release&.draft?
      h[:prerelease] = package_version&.release&.prerelease?
      h[:created_at] = time(package_version.created_at)
      h[:updated_at] = time(package_version.updated_at)
      h[:metadata] = package_version.try(:version_metadata) || registry_package_version_metadata_hash(package_version)
      h[package_version.ecosystem_metadata_label] = package_version.try(:version_ecosystem_metadata) || registry_package_version_metadata_hash(package_version)
      h[:package_files] = package_version.package_files.map { |file| registry_package_file_hash(file) }
      h[:author] = simple_user_hash(package_version.author, options)
      h[:installation_command] = package_version.installation_command
      h[:package_url] = package_version.source_url
    end.compact
  end

  # if payload body is a symbolic link that targets to body itself, it will cause a stack level too deep error
  # and we need to remove the target from the payload from the symbolic link to avoid this error
  # https://github.com/github/github/issues/247455
  def registry_package_version_body_sanitize(package_version_body)
    if package_version_body&.respond_to?(:symlink_source) && package_version_body.symlink_source&.instance_variable_get("@target") == package_version_body
      package_version_body.symlink_source&.instance_variable_set("@target", nil)
    end

    package_version_body
  end

  def registry_package_version_release_hash(registry_package, package_version, options)
    return nil unless package_version.release

    options = options.merge({
      repo: registry_package.repository,
    })

    repo = repo_path(options, package_version.release)
    repo_api_path = "/repos/#{repo}"
    release_path = "#{repo_api_path}/releases/#{package_version.release.id}"

    {
      url: url(release_path, options),
      html_url: package_version.release.permalink,
      id: package_version.release.id,
      tag_name: package_version.release.exposed_tag_name,
      target_commitish: package_version.release.target_commitish,
      name: package_version.release.name,
      draft: package_version.release.draft?,
      author: simple_user_hash(package_version.release.author, content_options(options)),
      prerelease: package_version.release.prerelease?,
      created_at: time(package_version.release.created_at),
      published_at: time(package_version.release.published_at),
    }
  end

  def registry_package_version_metadata_hash(package_version)
    package_version.serializeable_metadata.map do |metadata|
      {
        name: metadata.name,
        value: metadata.value,
        id: metadata.id,
      }
    end
  end

  # Creates a Hash to be serialized to JSON.
  #
  # package_file - Package File instance
  #
  # Returns a Hash if the package_file exists, or nil.
  def registry_package_file_hash(package_file)
    return nil if !package_file

    asset_path = package_file.url
    {
      download_url: asset_path,
      id: package_file.id,
      name: package_file.filename,
      sha256: package_file.sha256,
      sha1: package_file.sha1,
      md5: package_file.md5,
      content_type: package_file.content_type,
      state: package_file.state,
      size: package_file.size,
      created_at: time(package_file.created_at),
      updated_at: time(package_file.updated_at),
    }
  end
end
