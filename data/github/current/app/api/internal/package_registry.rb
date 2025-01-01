# typed: false
# frozen_string_literal: true

class Api::Internal::PackageRegistry < Api::Internal
  if PackageRegistryHelper.ghes_registry_enabled?
    # Internal: Determine whether a specific package type is enabled at the enterprise level
    get "/internal/registry/package_enabled_status", operation_id: :internal do
      @route_owner = "@github/package-registry"

      global_state = Configurable::PackageAvailability.package_availability
      enabled_status = {}

      Registry::Package::PUBLICLY_SUPPORTED_TYPES.each do |type|
        type_name = type.to_s

        if global_state == Configurable::PackageAvailability::ENABLED || global_state.nil?
          enabled_status[type_name] = true
        elsif global_state == Configurable::PackageAvailability::DISABLED
          enabled_status[type_name] = false
        else
          enabled_status[type_name] = this_business.managed_package_type_enabled?(type_name)
        end
      end
      render json: enabled_status
    end
  end

  # Internal: Given a registry package nwo (owner + package name), returns the package info.
  get "/internal/registry/:registry_type/@:owner/:pkg", operation_id: :internal do
    @route_owner = "@github/package-registry"

    result = platform_execute(PackageInfoQuery, variables: {
      owner: params[:owner],
      name: params[:pkg],
      packageType: params[:registry_type].upcase,
      registryPackageType: params[:registry_type],
    })

    if !result.errors.messages.nil? && !result.errors.messages.empty?
      deliver_raw(result.errors, status: 500)
    else
      deliver_raw({ "data" => result.data.to_h }, status: 200)
    end
  end

  def externally_accessible?
    false
  end

  def require_request_hmac?
    true
  end

  def authenticated_for_private_mode?
    true
  end

  PackageInfoQuery = PlatformClient.parse <<-'GRAPHQL'
    query ($owner: String!, $name: String!, $packageType: PackageType!, $registryPackageType: String!) {
      owner: packageOwner(login: $owner) {
        packages: packages(first: 1, name: $name, packageType: $packageType, registryPackageType: $registryPackageType, publicOnly: true) {
          edges {
            node {
              id
              repositoryInfo {
                id
                databaseId
                nameWithOwner
              }
              tags(first: 100) {
                edges {
                  node {
                    name
                    version {
                      version
                    }
                  }
                }
              }
              latestVersion {
                id
                version
                manifest
                updatedAt
              }
              versions(first: 100) {
                nodes {
                  id
                  version
                  manifest
                  updatedAt
                  files(first:100) {
                    nodes {
                      id
                      name
                      guid
                      url
                      sha1
                      md5
                      sha256
                      size
                      sri
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  GRAPHQL
end
