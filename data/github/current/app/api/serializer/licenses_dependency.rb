# typed: false
# frozen_string_literal: true

module Api::Serializer::LicensesDependency
  # Public: Build the hash of a license
  #
  # input - a License
  # options - :full - whether to return the full hash. Defaults to false
  #
  # Contains the numeric ID, the SPDX-compliant key, and the human-readable name
  #
  # Returns a hash
  def license_hash(license, options = {})
    return nil unless license
    options = Api::SerializerOptions.from(options)
    url = license.pseudo_license? ? nil : url("/licenses/#{license.key}", options)

    hash = {
      key: license.key,
      name: license.name,
      spdx_id: license.spdx_id,
      url: url,
      node_id: global_id_for(license, options),
    }

    return hash unless options[:full]

    hash.update({
      html_url: license.url,
      description: license.description,
      implementation: license.how,
      permissions: license.permissions,
      conditions: license.conditions,
      limitations: license.limitations,
      body: license.body,
      featured: license.featured?,
    })
  end

  def license_content_hash(license_content, options = {})
    return nil unless license_content
    options = Api::SerializerOptions.from(options)

    # Detect a potentially different license if it's not the default branch.
    license = if options[:ref] == options[:default_branch]
      options[:repo].license
    else
      key = RepositoryLicense.detect_license(options[:repo], options[:ref])
      License.find(key)
    end

    hash = content_hash(license_content, options)
    options[:full] = false
    hash[:license] = license_hash(license, options)

    hash
  end

  SimpleLicenseFragment = Api::App::PlatformClient.parse  <<-'GRAPHQL'
    fragment on License {
      id
      key
      name
      spdxId
      url
      pseudoLicense
    }
  GRAPHQL

  def graphql_simple_license_hash(license, options = {})
    return nil unless license
    options = Api::SerializerOptions.from(options)
    license = SimpleLicenseFragment.new(license)
    url = license.pseudo_license ? nil : url("/licenses/#{license.key}", options)

    {
      key: license.key,
      name: license.name,
      spdx_id: license.spdx_id,
      url: url,
      node_id: license.id,
    }
  end
end
