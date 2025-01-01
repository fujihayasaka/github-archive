# typed: true
# frozen_string_literal: true

module Packages
  module Migration
    class MigrateNamespaceJob < Packages::Migration::MigrationJob
      default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

      class NamespaceNotFoundError < RuntimeError; end
      class UnsupportedRegistryTypeError < RuntimeError; end
      class MigrationNotSupported < RuntimeError; end

      BATCH_SIZE = 100

      queue_as :packages_migration_migrate_namespace

      retry_on_dirty_exit

      discard_on NamespaceNotFoundError
      discard_on UnsupportedRegistryTypeError
      discard_on MigrationNotSupported

      attr_reader :namespace, :registry_metadata, :registry_package_type

      def next_batch(login, registry_package_type, timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **options)
        init_registry_package_type(registry_package_type)

        init_namespace(login)
        if GitHub.enterprise? && @registry_package_type == :docker
          Registry::PackageVersion.joins(:package).where(package: { owner_id: namespace&.id, package_type: :docker }, migration_state: "retriable_error").update_all(migration_state: "unmigrated")
        end
        ensure_org_settings

        update_namespace_migration_status

        emit_owner_migration_status_change_event

        update_registry_feature_flags

        get_packages(unmigrated_only: !is_forced, failed_only: is_failed_retry, is_error_retry: is_error_retry)
          .where("registry_packages.id > ?", offset_item_id)
          .order(:id)
          .limit(BATCH_SIZE)
          .pluck(:id)
      end

      def init_registry_package_type(registry_package_type)
        @registry_package_type = registry_package_type.to_sym

        # enterprise only support docker migration
        unless (!GitHub.enterprise? && registry_package_type.to_s.in?(%w[docker npm rubygems nuget])) || (GitHub.enterprise? && @registry_package_type == :docker)
          log(msg: (msg = "registry type #{registry_package_type} is not supported"))
          raise UnsupportedRegistryTypeError.new(msg)
        end
      end

      def ensure_org_settings
        return unless namespace&.organization?

        return if has_used_registry

        set_package_type_availability

        namespace&.allow_members_to_publish_private_packages(actor: namespace)

        if namespace&.members_can_create_public_repositories?
          log(msg: "enabling public visibility settings for #{namespace}")
          namespace&.allow_members_to_publish_public_packages(actor: namespace)
        end
        if namespace&.members_can_create_internal_repositories?
          log(msg: "enabling internal visibility settings for #{namespace}")
          namespace&.allow_members_to_publish_internal_packages(actor: namespace)
        end
      end

      def has_used_registry
        packages = registry_metadata.get_all_packages(namespace: namespace&.login, ecosystem: registry_package_type.to_sym, limit: 1)
        packages && packages.length > 0
      end

      def process_batch(batch, login, registry_package_type, **options)
        if batch.empty? && is_ecosystem_eligible_for_migration
          log(msg: "no packages to migrate for #{namespace}")
          update_state_if_batch_empty
        end
        batch.each do |pkg_id|
          log(msg: "enqueueing migrate package job with package id #{pkg_id}")
          ::Packages::Migration::MigratePackageJob.perform_later(pkg_id, force: is_forced, retry_failed: is_failed_retry, is_error_retry: is_error_retry, last_migrated_package_id: last_migrated_package_id)
        end
      end

      def set_package_type_availability
        if @registry_package_type == :docker
          namespace&.set_package_type_availability(:container, true, actor: @namespace)
        else
          namespace&.set_package_type_availability(@registry_package_type, true, actor: @namespace)
        end
      end

      def next_batch_offset_item_id(batch, *args, **options)
        batch.max
      end

      private

      def init_namespace(login)
        if login.nil? || login == ""
          log(msg: (msg = "invalid login given"))
          raise NamespaceNotFoundError.new(msg)
        end

        @namespace = User.find_by_login(login)

        if @namespace.nil?
          log(msg: (msg = "namespace #{login} not found"))
          raise NamespaceNotFoundError.new msg
        end
        @registry_metadata = PackageRegistry::Twirp.metadata_client
      end

      def update_namespace_migration_status
        return unless is_first_run
        if is_ecosystem_eligible_for_migration
          Registry::OwnerMigration.upsert({ owner_id: namespace.id, package_type: registry_package_type, state: :inProgress }) if namespace.present?
        elsif registry_package_type == :docker
          @namespace&.enable_feature(:packages_docker_v1_migration_in_process)
          @namespace&.disable_feature(:packages_docker_v1_migration_pending)
        end
      end

      def is_ecosystem_eligible_for_migration
        (GitHub.enterprise? && registry_package_type == :docker) || registry_package_type == :npm || registry_package_type == :nuget || registry_package_type == :rubygems
      end

      def emit_owner_migration_status_change_event
        return unless is_first_run && (registry_package_type == :npm || registry_package_type == :nuget || registry_package_type == :rubygems)

        # rms needs to invalidate owner migration status cache
        log(msg: "emitting owner migration status change event for owner with id #{namespace.id} and ecosystem #{registry_package_type}")
        GlobalInstrumenter.instrument("package_registry.namespace_cache_invalidate", { namespace: namespace.name, ecosystem: registry_package_type })
      end

      def update_registry_feature_flags
        return unless is_first_run
        # enable ui and api access for the namespace
        log(msg: (msg = "invalid registry type #{registry_package_type}"))
      end

      # only used in case of npm, nuget, and rubygems and docker in enterprise
      # update namespace state as migrated packages found for the namespace
      def update_state_if_batch_empty
        return unless is_first_run && namespace.present?
        log(msg: "updating namespace state as no packages found for #{namespace}")
        om = Registry::OwnerMigration.find_by(owner_id: namespace.id, package_type: registry_package_type)
        om.update(state: :migrated) if om
      end

      def get_packages(unmigrated_only: true, failed_only: false, is_error_retry: false)
        namespace&.packages&.migratable(registry_package_type.to_s, unmigrated_only: unmigrated_only, failed_only: failed_only, is_error_retry: is_error_retry)
      end

      def last_migrated_package_id

        if @last_migrated_package_id.nil? || @last_migrated_package_id <= 0
          @last_migrated_package_id = get_packages
            .order(id: :desc)
            .limit(1)
            .pluck(:id)
            .first
        end

        @last_migrated_package_id
      end
    end
  end
end
