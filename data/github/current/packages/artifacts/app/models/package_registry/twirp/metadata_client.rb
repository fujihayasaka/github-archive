# typed: true
# frozen_string_literal: true

module PackageRegistry
  module Twirp
    class MetadataClient < PackageRegistry::Twirp::BaseClient

      def initialize(connection_open_timeout: CONNECTION_OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
        super(package_registry_hmac_key: GitHub.package_registry_metadata_hmac_key,
          connection_open_timeout: connection_open_timeout, read_timeout: read_timeout)
      end

      def get_packages_metadata(actor:, package_ids:, include_deleted: false, exclude_latest_versions: false, include_version_count: false)
        actor_id = actor_id_value(actor)
        # If user is unauthenticated, we send a user_id of 0 to indicate anonymous access
        actor_id = actor_id || 0
        actor_type = actor_type_value(actor)
        integration_name = actor_integration_name(actor)
        resp = rpc(:GetPackagesMetadata, user_id: actor_id, actor_type: actor_type, package_ids: package_ids, include_deleted: include_deleted, exclude_latest_version: exclude_latest_versions, include_version_count: include_version_count, integration_name: integration_name)
        resp.packages_metadata.map { |md| PackageRegistry::PackageMetadata.new(md) }
      end

      # get_package_metadata returns package metadata along with it's versions
      # 0 version_limit means ALL versions will be returned
      def get_package_metadata(ecosystem:, namespace:, name:, actor:, version_offset: 0, version_limit: 0, version_filter: nil, include_deleted: false, search_action_packages_enabled: false, include_download_count: false, read_from_replica: false)
        package_subtype = package_subtype_value(ecosystem, search_action_packages_enabled)
        ecosystem = ecosystem_value(ecosystem)
        container_version_filter = container_version_filter(version_filter)
        actor_type = actor_type_value(actor)
        actor_id = actor_id_value(actor)
        integration_name = actor_integration_name(actor)
        resp = rpc(
          :GetPackageMetadata,
          ecosystem: ecosystem,
          package_subtype: package_subtype,
          namespace: namespace,
          name: name,
          user_id: actor_id,
          actor_type: actor_type,
          version_offset: version_offset,
          version_limit: version_limit,
          containerVersionFilter: container_version_filter,
          include_deleted: include_deleted,
          include_download_count: include_download_count,
          integration_name: integration_name,
          read_from_replica: read_from_replica,
        )
        PackageRegistry::PackageMetadata.new(resp.package_metadata, package_type: package_subtype) unless resp.package_metadata.nil?
      end

      def get_package_version(ecosystem:, actor:, namespace:, name:, version_id:, search_action_packages_enabled: false)
        package_subtype = package_subtype_value(ecosystem, search_action_packages_enabled)
        ecosystem = ecosystem_value(ecosystem)
        actor_type = actor_type_value(actor)
        actor_id = actor_id_value(actor)
        integration_name = actor_integration_name(actor)
        resp = rpc(:GetPackageVersion,
          ecosystem: ecosystem,
          package_subtype: package_subtype,
          user_id: actor_id,
          actor_type: actor_type,
          namespace: namespace,
          name: name,
          version_id: version_id,
          integration_name: integration_name)
        PackageRegistry::PackageVersion.new(resp.version) unless resp.version.nil?
      end

      def get_container_latest_version(ecosystem:, actor:, namespace:, name:)
        ecosystem = ecosystem_value(ecosystem)
        actor_type = actor_type_value(actor)
        actor_id = actor_id_value(actor)
        integration_name = actor_integration_name(actor)
        resp = rpc(:GetContainerLatestVersion, ecosystem: ecosystem, user_id: actor_id, actor_type: actor_type, namespace: namespace, name: name, integration_name: integration_name)
        PackageRegistry::PackageVersion.new(resp.version) unless resp.version.nil?
      end

      def get_container_metadata_for_version_deletion(ecosystem:, actor:, namespace:, name:)
        ecosystem = ecosystem_value(ecosystem)
        actor_type = actor_type_value(actor)
        actor_id = actor_id_value(actor)
        integration_name = actor_integration_name(actor)
        resp = rpc(:GetContainerMetadataForVersionDeletion, namespace: namespace, name: name, ecosystem: ecosystem, user_id: actor_id, actor_type: actor_type, integration_name: integration_name)
        PackageRegistry::ContainerVersionDeletionMetadata.new(resp)
      end

      def get_container_non_sign_latest_version(ecosystem:, actor_id:, actor_type:, namespace:, name:, integration_name:) # this function only gets called for an Action package
        ecosystem = ecosystem_value(ecosystem)
        resp = rpc(:GetContainerLatestVersion, ecosystem: ecosystem, user_id: actor_id, actor_type: actor_type, namespace: namespace, name: name, integration_name: integration_name)
        PackageRegistry::PackageVersion.new(resp.version) unless resp.version.nil?
      end

      def get_package_listing(ecosystem:, actor:, namespace:, internal_namespaces: [], readable_repo_ids: [], visibility: "", limit: 0, offset: 0, search_action_packages_enabled: false)
        package_subtype = package_subtype_value(ecosystem, search_action_packages_enabled)
        ecosystem = ecosystem_value(ecosystem)
        actor_type = actor_type_value(actor)
        actor_id = actor_id_value(actor)
        integration_name = actor_integration_name(actor)
        resp = rpc(:GetPackageListing,
          ecosystem: ecosystem,
          package_subtype: package_subtype,
          user_id: actor_id,
          actor_type: actor_type,
          namespace: namespace,
          internal_namespaces: internal_namespaces,
          visibility: visibility,
          readable_repo_ids: readable_repo_ids,
          limit: limit,
          offset: offset,
          integration_name: integration_name)
        {
          packages: resp.packages.map { |md| PackageRegistry::PackageMetadata.new(md, package_type: package_subtype) },
          total_packages: resp.total_packages
        }
      end

      def get_package_version_download_counts(package_id:, version_id:)
        resp = rpc(:GetPackageVersionDownloadCounts, package_id: package_id, version_id: version_id)
        resp ? PackageRegistry::DownloadCounts.new(resp) : PackageRegistry::DownloadCounts::NULL
      end

      def get_package_version_files(version_id:)
        resp = rpc(:GetPackageVersionFiles, version_id: version_id)
        resp.files.map { |f| PackageRegistry::PackageFile.new(f) }
      end

      def get_package_total_download_counts(package_id:)
        resp = rpc(:GetPackageTotalDownloadCounts, package_id: package_id)
        resp ? PackageRegistry::DownloadCounts.new(resp) : PackageRegistry::DownloadCounts::NULL
      end

      def get_packages_total_download_counts(package_ids:)
        resp = rpc(:GetPackagesTotalDownloadCounts, package_ids: package_ids)
        resp.package_counts ? resp.package_counts.to_h : {}
      end

      def get_packages_by_names(namespace:, package_names:, ecosystem:, actor:)
        ecosystem = ecosystem_value(ecosystem)
        actor_type = actor_type_value(actor)
        actor_id = actor_id_value(actor)
        integration_name = actor_integration_name(actor)
        resp = rpc(:GetPackagesByNames, namespace: namespace, package_names: package_names, ecosystem: ecosystem, user_id: actor_id, actor_type: actor_type, integration_name: integration_name)
        resp.packages.map { |md| PackageRegistry::PackageMetadata.new(md) }
      end

      def update_package(ecosystem:, namespace:, name:, visibility:, actor:)
        ecosystem = ecosystem_value(ecosystem)
        visibility = visibility_value(visibility)
        actor_type = actor_type_value(actor)
        rpc(:UpdatePackage, ecosystem: ecosystem, namespace: namespace, name: name, visibility: visibility, user_id: actor&.id, actor_type: actor_type)
      end

      def update_package_visibility(ecosystem:, namespace:, name:, visibility:, actor:)
        ecosystem = ecosystem_value(ecosystem)
        visibility = visibility_value(visibility)
        actor_type = actor_type_value(actor)
        rpc(:UpdatePackage, ecosystem: ecosystem, namespace: namespace, name: name, visibility: visibility, user_id: actor&.id, actor_type: actor_type, update_mask: Google::Protobuf::FieldMask.new(paths: ["visibility"]))
      end

      def update_package_active_sync_perms(ecosystem:, namespace:, name:, active_sync_perms:, actor:)
        ecosystem = ecosystem_value(ecosystem)
        actor_type = actor_type_value(actor)
        rpc(:UpdatePackage, ecosystem: ecosystem, namespace: namespace, name: name, active_sync_perms: active_sync_perms, user_id: actor&.id, actor_type: actor_type, update_mask: Google::Protobuf::FieldMask.new(paths: ["active_sync_perms"]))
      end

      def update_package_version_ecodata(version_id:, key:, value:, actor:)
        actor_type = actor_type_value(actor)
        rpc(:UpdatePackageVersionEcodata, version_id: version_id, key: key, value: value, actor_type: actor_type, user_id: actor&.id)
      end

      def update_package_repo(package_id:, repo_id:)
        rpc(:UpdatePackageRepo, package_id: package_id, repo_id: repo_id)
      end

      def remove_package_repo(ecosystem:, namespace:, name:, actor:, repo_id:)
        ecosystem = ecosystem_value(ecosystem)
        actor_type = actor_type_value(actor)
        rpc(:UpdatePackage, ecosystem: ecosystem, namespace: namespace, name: name, user_id: actor&.id, actor_type: actor_type, update_mask: Google::Protobuf::FieldMask.new(paths: ["repo_id"]))
      end

      def delete_package(ecosystem:, namespace:, name:, actor:, mode: :soft, staff_override: false, search_action_packages_enabled: false)
        mode = delete_mode_value(mode)
        package_subtype = package_subtype_value(ecosystem, search_action_packages_enabled)
        ecosystem = ecosystem_value(ecosystem)
        actor_type = actor_type_value(actor)
        actor_id = actor_id_value(actor)
        integration_name = actor_integration_name(actor)
        rpc(:DeletePackage,
          ecosystem: ecosystem,
          package_subtype: package_subtype,
          namespace: namespace,
          name: name,
          user_id: actor_id,
          actor_type: actor_type,
          mode: mode,
          staff_override:
          staff_override,
          integration_name: integration_name)
      end

      def delete_package_version(ecosystem:, namespace:, name:, actor:, version:, mode: :soft, search_action_packages_enabled: false)
        package_subtype = package_subtype_value(ecosystem, search_action_packages_enabled)
        ecosystem = ecosystem_value(ecosystem)
        m = delete_mode_value(mode)
        actor_type = actor_type_value(actor)
        actor_id = actor_id_value(actor)
        integration_name = actor_integration_name(actor)
        rpc(:DeletePackageVersion,
          ecosystem: ecosystem,
          package_subtype: package_subtype,
          namespace: namespace,
          name: name,
          user_id: actor_id,
          actor_type: actor_type,
          mode: m,
          version: version,
          integration_name: integration_name)
      end

      def restore_package(namespace:, name:, ecosystem:, actor:, search_action_packages_enabled: false)
        package_subtype = package_subtype_value(ecosystem, search_action_packages_enabled)
        ecosystem = ecosystem_value(ecosystem)
        actor_type = actor_type_value(actor)
        actor_id = actor_id_value(actor)
        integration_name = actor_integration_name(actor)
        rpc(:RestorePackage,
          namespace: namespace,
          name: name,
          ecosystem: ecosystem,
          package_subtype: package_subtype,
          user_id: actor_id,
          actor_type: actor_type,
          integration_name: integration_name)
      end

      def restore_package_version(namespace:, name:, ecosystem:, actor:, version:, search_action_packages_enabled: false)
        package_subtype = package_subtype_value(ecosystem, search_action_packages_enabled)
        ecosystem = ecosystem_value(ecosystem)
        actor_type = actor_type_value(actor)
        actor_id = actor_id_value(actor)
        integration_name = actor_integration_name(actor)
        rpc(:RestorePackageVersion,
          namespace: namespace,
          name: name,
          ecosystem: ecosystem,
          package_subtype: package_subtype,
          user_id: actor_id,
          actor_type: actor_type,
          version: version,
          integration_name: integration_name)
      end

      def get_deleted_package_versions(namespace:, name:, ecosystem:, actor:, version_order: :desc, version_limit: 50, version_offset: 0, search_action_packages_enabled: false)
        package_subtype = package_subtype_value(ecosystem, search_action_packages_enabled)
        ecosystem = ecosystem_value(ecosystem)
        actor_type = actor_type_value(actor)
        actor_id = actor_id_value(actor)
        integration_name = actor_integration_name(actor)
        order = order_value(version_order)
        resp = rpc(:GetDeletedPackageVersions,
          namespace: namespace,
          name: name,
          ecosystem: ecosystem,
          package_subtype: package_subtype,
          user_id: actor_id,
          actor_type: actor_type,
          version_order: order,
          version_limit: version_limit,
          version_offset: version_offset,
          integration_name: integration_name)
        PackageRegistry::PackageMetadata.new(resp.package_metadata) unless resp.package_metadata.nil?
      end

      def retire_namespace(namespace:, name:, ecosystem:, owner_id:)
        ecosystem = ecosystem_value(ecosystem)
        rpc(:RetireNamespace, namespace: namespace, name: name, ecosystem: ecosystem, owner_id: owner_id)

      end

      def unretire_namespace(namespace:, name:, ecosystem:)
        ecosystem = ecosystem_value(ecosystem)
        rpc(:UnretireNamespace, namespace: namespace, name: name, ecosystem: ecosystem)
      end

      def check_packages_retired_namespace(owner_id:, old_namespace:, new_namespace:)
        rpc(:CheckPackagesRetiredNamespace, owner_id: owner_id, old_namespace: old_namespace, new_namespace: new_namespace)
      end

      # get_all_packages is for use by internal jobs/etc as it does NOT perform Authz checks on the RMS server side
      def get_all_packages(namespace:, ecosystem: :unknown, limit: 100, offset: 0, exclude_deleted: false, filter: nil, order: nil, full_response: false)
        ecosystem = ecosystem_value(ecosystem)
        resp = rpc(:GetAllPackages, namespace: namespace, ecosystem: ecosystem, limit: limit, offset: offset, exclude_deleted: exclude_deleted, filter: filter, order: order)
        full_response ? resp : resp.packages.map { |p| PackageRegistry::Package.new(p) }
      end

      # this API endpoint is only used by Stafftools and does not perform Authz checks, so the value of integration_name doesn't matter
      def get_all_package_summaries(namespace:, ecosystem: :unknown, limit: 100, offset: 0, exclude_deleted: false, filter: nil, order: nil, full_response: false)
        ecosystem = ecosystem_value(ecosystem)
        resp = rpc(:GetAllPackageSummaries, namespace: namespace, ecosystem: ecosystem, limit: limit, offset: offset, exclude_deleted: exclude_deleted, filter: filter, order: order, integration_name: "")
        {
          total_packages: resp.total_packages,
          package_summaries: resp.package_summaries.map { |summary| PackageRegistry::PackageSummary.new(summary) }
        }
      end

      def get_packages_by_original_name(namespace:, name:, ecosystem:, actor:, search_action_packages_enabled: false)
        package_subtype = package_subtype_value(ecosystem, search_action_packages_enabled)
        ecosystem = ecosystem_value(ecosystem)
        actor_type = actor_type_value(actor)
        actor_id = actor_id_value(actor)
        integration_name = actor_integration_name(actor)
        resp = rpc(:GetPackagesByOriginalName,
          namespace: namespace,
          name: name,
          ecosystem: ecosystem,
          package_subtype: package_subtype,
          user_id: actor_id,
          actor_type: actor_type,
          integration_name: integration_name)
        resp.packages.map { |p| PackageRegistry::Package.new(p) }
      end

      def get_packages_by_repo(repo_id:)
        rpc(:GetPackagesByRepo, repo_id: repo_id)
      end

      def get_reclaimed_storage(ecosystem:, namespace:, name:, billing_entity_namespaces:, version:)
        ecosystem = ecosystem_value(ecosystem)
        rpc(
          :GetReclaimedStorage,
          ecosystem: ecosystem,
          namespace: namespace,
          name: name,
          billing_entity_namespaces: billing_entity_namespaces,
          version: version,
        )
      end

      def get_storage_utilization(namespaces:, effective_date:)
        resp = rpc(
          :GetStorageUtilization,
          namespaces: namespaces,
          effective_date: effective_date,
        )
      end

      def get_eco_namespace_storage_utilization(namespace:)
        resp = rpc(
          :GetEcoNamespaceStorageUtilization,
          namespace: namespace,
        )
      end

      def get_all_namespaces
        rpc(:GetAllNamespaces, {})
      end

      # get package visibility
      def get_package_visibility(namespace:, name:, ecosystem:)
        ecosystem = ecosystem_value(ecosystem)
        rpc(:GetPackageVisibility, ecosystem: ecosystem, namespace: namespace, name: name)
      end

      private

      def twirp_class
        Proto::RegistryMetadata::V1::Package::MetadataClient
      end

      def ecosystem_value(ecosystem)
        case ecosystem.downcase.to_sym
        when :container, :actions
          Proto::RegistryMetadata::V1::Package::Ecosystem::CONTAINER
        when :npm
          Proto::RegistryMetadata::V1::Package::Ecosystem::NPM
        when :nuget
          Proto::RegistryMetadata::V1::Package::Ecosystem::NUGET
        when :rubygems
          Proto::RegistryMetadata::V1::Package::Ecosystem::RUBYGEMS
        when :maven
          Proto::RegistryMetadata::V1::Package::Ecosystem::MAVEN
        else
          Proto::RegistryMetadata::V1::Package::Ecosystem::UNKNOWN
        end
      end

      def package_subtype_value(ecosystem, search_action_packages_enabled = false)
        # if FF is not enabled, return ANY
        return Proto::RegistryMetadata::V1::Package::PackageSubtype::ANY unless search_action_packages_enabled

        case ecosystem.downcase.to_sym
        when :actions
          Proto::RegistryMetadata::V1::Package::PackageSubtype::ACTIONS
        when :container
          Proto::RegistryMetadata::V1::Package::PackageSubtype::NOSPECIALSUBTYPE
        else
          Proto::RegistryMetadata::V1::Package::PackageSubtype::ANY
        end
      end

      def actor_type_value(actor)
        # Treating INSTALLATION = ScopedIntegrationInstallation
        return Proto::RegistryMetadata::V1::Package::ActorType::UNSPECIFIED if actor.nil?
        return Proto::RegistryMetadata::V1::Package::ActorType::INSTALLATION if scoped_integration_installation?(actor)
        return Proto::RegistryMetadata::V1::Package::ActorType::SITE_SCOPED_INSTALLATION if site_scoped_integration_installation?(actor)
        return Proto::RegistryMetadata::V1::Package::ActorType::USER if actor.try(:user?) || actor.try(:organization?)
        Proto::RegistryMetadata::V1::Package::ActorType::UNSPECIFIED
      end

      def actor_id_value(actor)
        return nil unless actor
        return actor.id unless integration_actor?(actor)
        actor.is_a?(Bot) ? actor.installation.id : actor.id
      end

      def actor_integration_name(actor)
        integration = actor.try(:installation).try(:integration)
        return nil unless integration
        Apps::Privileged.property(:packages_authorization_name, app: integration) || integration.name
      end

      def integration_actor?(actor)
        actor.is_a?(Bot) ||
        actor.is_a?(IntegrationInstallation) ||
        actor.is_a?(ScopedIntegrationInstallation) || # it is possible these last two clauses never get touched, and may be invalid, as the value of actor might never be a scoped or site-scoped installation (but actor.installation may)
        actor.is_a?(SiteScopedIntegrationInstallation)
      end

      def scoped_integration_installation?(actor)
        return false if actor.nil? || !integration_actor?(actor)
        actor.is_a?(IntegrationInstallation) || actor.installation.is_a?(ScopedIntegrationInstallation)
      end

      def site_scoped_integration_installation?(actor)
        return false unless actor.respond_to?(:installation)
        actor.installation.is_a?(SiteScopedIntegrationInstallation)
      end

      def order_value(order)
        case order
        when :desc
          ::Proto::RegistryMetadata::V1::Package::Order::DESCENDING
        when :asc
          ::Proto::RegistryMetadata::V1::Package::Order::ASCENDING
        else
          ::Proto::RegistryMetadata::V1::Package::Order::DESCENDING
        end
      end

      def delete_mode_value(mode)
        case mode.downcase
        when :permanent
          ::Proto::RegistryMetadata::V1::Package::DeleteMode::PERMANENT
        else
          ::Proto::RegistryMetadata::V1::Package::DeleteMode::SOFT
        end
      end

      def visibility_value(visibility)
        case visibility.downcase.to_sym
        when :public
          ::Proto::RegistryMetadata::V1::Package::Visibility::PUBLIC
        when :private
          ::Proto::RegistryMetadata::V1::Package::Visibility::PRIVATE
        when :internal
          ::Proto::RegistryMetadata::V1::Package::Visibility::INTERNAL
        else
          ::Proto::RegistryMetadata::V1::Package::Visibility::PRIVATE
        end
      end

      def container_version_filter(version_type)
        case version_type&.downcase&.to_sym
        when :all
          # nil will return both tagged and untagged
          nil
        when :tagged
          ::Proto::RegistryMetadata::V1::Package::EcoVersionFilterContainer::TAGGED
        when :untagged
          ::Proto::RegistryMetadata::V1::Package::EcoVersionFilterContainer::UNTAGGED
        end
      end
    end
  end
end
