# typed: false
# frozen_string_literal: true
module Api::Serializer::PackagesDependency

  def package_hash(package, options)
    return nil unless package

    owner = package.repository.nil? ? package.owner : package.repository.owner

    h = {
      id: package.id,
      name: package.name,
      package_type: package.respond_to?(:api_package_type) ? package.api_package_type : package.package_type,
      owner: simple_user_hash(owner, options),
      version_count: package.version_count,
      visibility: package.visibility,
      url: url(package.uri),
      created_at: time(package.created_at),
      updated_at: time(package.updated_at),
    }

    # ensure repo can be seen by current_user
    if repo = package.repository
      if repo.public?
        h[:repository] = simple_repository_hash(repo, options)
      elsif options[:current_user]
        h[:repository] = simple_repository_hash(repo, options) if repo.readable_by?(options[:current_user])
      end
    end

    h[:html_url] = html_url(package.html_uri) if package.html_uri

    h.compact
  end

  def package_version_hash(version, options)
    return nil unless version
    package_type = if GitHub.flipper[:search_action_packages].enabled?(options[:current_user]) && version.respond_to?(:aop?) && version.aop?
      :actions
    else
      version.package_type
    end

    h = {
      id: version.id,
      name: version.name,
      url: url(version.uri),
      package_html_url: html_url(version.package_html_uri),
      license: version.license,
      created_at: time(version.created_at),
      updated_at: time(version.updated_at)
    }

    h[:description] = version.description unless version.description.empty?
    h[:deleted_at] = time(version.deleted_at) if version.deleted_at
    h[:html_url] = html_url(version.html_uri) if version.html_uri

    h[:metadata] = {
      package_type: package_type
    }

    case package_type
    when :container, :actions
      h[:metadata][package_type] = version.container_metadata
    when :docker
      h[:metadata][:docker] = version.docker_metadata
    end

    h.compact
  end
end
