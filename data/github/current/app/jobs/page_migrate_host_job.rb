# typed: true
# frozen_string_literal: true

# This Job will migrate a pages site from iad datacenter to azure eastus datacenter
class PageMigrateHostJob < ApplicationJob

  queue_as :page_migrate_host

  retry_on_dirty_exit

  MAX_THROTTLE_RETRIES = 4

  SERVICE_NAME = "page_migrate_host"

  RSYNC_TIMEOUT = 600 # seconds

  AZURE_EASTUS = "azure-eastus"

  RSYNC = "nice -n 19 ionice -c 3 rsync --rsync-path=\"nice -n 19 ionice -c 3 rsync\" --timeout=#{RSYNC_TIMEOUT}"

  def pages_twirp_client
    @pages_twirp_client ||= Page::Twirp::RequestClient.new(service_name: SERVICE_NAME)
  end

  def delegate
    @delegate ||= GitHub::Pages::Management::Delegate.new
  end

  def skip_update_migration_failed_status?
    GitHub.flipper[:skip_update_migration_failed_status].enabled?
  end

  def perform(page_migration_id)
    return unless GitHub.flipper[:pages_migration_azure].enabled?

    Failbot.push(app: "page-migrate-host")

    GitHub.dogstats.increment "pages.azure.migration", tags: ["state:started"]

    page_migration = Page::PagesMigrations.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) { Page::PagesMigrations.find(page_migration_id) }
    Page::PagesMigrations.throttle_writes_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) { page_migration.update(status: :running) } if skip_update_migration_failed_status?
    target_hosts = pages_twirp_client.request_deployment_hosts(page_migration.page_id.to_s, page_migration.page_deployment_id.to_s)
    if target_hosts.empty?
      GitHub.logger.info("page migration skipped, no target hosts found", {
        "gh.pages.id" => page_migration.page_id,
        "gh.pages.deployment.id" => page_migration.page_deployment_id
      })
      return with_write { page_migration.update(status: :created) }
    end
    GitHub.logger.info("page migration started", {
      "gh.pages.id" => page_migration.page_id,
      "gh.pages.deployment.id" => page_migration.page_deployment_id,
    })

    replicas = current_replicas(page_migration.page_id, page_migration.page_deployment_id)

    # 1. skip if the page is already in azure-eastus
    src_hosts = replicas.pluck(:host)
    if src_hosts.empty? || !src_hosts.none? { |host| host.include?(AZURE_EASTUS) }
      GitHub.logger.info("page migration skipped, page is already in azure-eastus or no replica found for the page", {
        "gh.pages.id" => page_migration.page_id,
        "gh.pages.deployment.id" => page_migration.page_deployment_id,
      })

      Page::PagesMigrations.throttle_writes_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) { page_migration.update(status: :skipped_already_in_azure) } unless skip_update_migration_failed_status?
      GitHub.dogstats.increment "pages.azure.migration", tags: ["state:skipped", "reason:page_already_in_azure_eastus"]
      return
    end

    deployment_revision = current_deployment_version(page_migration.page_id, page_migration.page_deployment_id)
    if deployment_revision.nil?
      Page::PagesMigrations.throttle_writes_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) { page_migration.update(status: :failed_nil_deployment_revision) } unless skip_update_migration_failed_status?
      GitHub.dogstats.increment "pages.azure.migration", tags: ["state:failed", "reason:revision_not_found"]
      return
    end

    # try peek the source host to find 1 host that has the page
    source_host = find_source_host(replicas, page_migration.page_id, deployment_revision)

    if source_host.nil?
      GitHub.logger.error("source host not be able to be processed", {
        "gh.pages.id" => page_migration.page_id,
        "gh.pages.deployment.id" => page_migration.page_deployment_id
      })
      Page::PagesMigrations.throttle_writes_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) { page_migration.update(status: :failed_source_host_not_found) } unless skip_update_migration_failed_status?
      GitHub.dogstats.increment "pages.azure.migration", tags: ["state:failed", "reason:source_host_not_found"]
      return
    end

    succeed = T.let(true, T::Boolean)

    new_replicas = []

    target_hosts.each do |host|
      if !migrate(source_host, host, page_migration.page_id, deployment_revision)
        GitHub.logger.error("page migration failed", {
          "gh.pages.id" => page_migration.page_id,
          "gh.pages.deployment.id" => page_migration.page_deployment_id
        })
        succeed = false
        break
      end
      new_replicas << { page_id: page_migration.page_id, pages_deployment_id: page_migration.page_deployment_id == 0 ? nil : page_migration.page_deployment_id, created_at: GitHub::SQL::ArelLiterals::NOW, updated_at: GitHub::SQL::ArelLiterals::NOW, host: host }
    end

    if !succeed
      Page::PagesMigrations.throttle_writes_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) { page_migration.update(status: :failed_rsync) } unless skip_update_migration_failed_status?
      GitHub.dogstats.increment "pages.azure.migration", tags: ["state:failed", "reason:rsync_failed"]
      return
    end
    Page::PagesMigrations.throttle_writes_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
      Page::Replica.transaction do
        replicas = current_replicas(page_migration.page_id, page_migration.page_deployment_id)

        # re-query to ensure the host is still iad and replica still exists
        src_hosts = replicas.pluck(:host)
        if src_hosts.empty? || !src_hosts.none? { |host| host.include?(AZURE_EASTUS) }
          GitHub.logger.info("page migration skipped, page is already in azure-eastus or no replica found for the page", {
            "gh.pages.id" => page_migration.page_id,
            "gh.pages.deployment.id" => page_migration.page_deployment_id,
          })
          page_migration.update(status: :skipped) unless skip_update_migration_failed_status?
          GitHub.dogstats.increment "pages.azure.migration", tags: ["state:skipped", "reason:page_already_in_azure_eastus"]
        else
          # insert new replicas
          replicas.delete_all
          Page::Replica.insert_all(new_replicas)
          page_migration.update(manifest: { migrated_time: Time.now, src_hosts: src_hosts, target_hosts: target_hosts }, status: :succeed)
          GitHub.dogstats.increment "pages.azure.migration", tags: ["state:succeed"]
        end
      end
    end
  end

  def find_source_host(replicas, page_id, revision)
    revision ||= "legacy"
    path = GitHub::Routing.dpages_storage_path(page_id, revision: revision)
    replicas.each do |replica|
      if delegate.ssh(replica.host, "test -d #{path}", timeout: 5)
        return replica.host
      end
    end
    nil
  end

  def migrate(source_host, target_host, page_id, revision)
    revision ||= "legacy"

    path = GitHub::Routing.dpages_storage_path(page_id, revision: revision)

    return false unless delegate.ssh(target_host, "rm -rf #{path} && mkdir -p #{path}", timeout: 5)

    return false unless delegate.ssh(source_host, "#{RSYNC} -a #{path}/ #{target_host}:#{path}/", timeout: RSYNC_TIMEOUT)

    return false unless delegate.ssh(target_host, "test -d #{path}", timeout: 5)

    true
  end

  def current_replicas(page_id, pages_deployment_id)
    pages_deployment_id = pages_deployment_id == 0 ? nil : pages_deployment_id
    Page::Replica.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
      Page::Replica.where(page_id: page_id, pages_deployment_id: pages_deployment_id)
    end
  end

  def current_deployment_version(page_id, page_deployment_id)
    return Page::Deployment.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
      Page::Deployment.find_by(id: page_deployment_id, page_id: page_id)&.revision
    end if page_deployment_id != 0
    Page::throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) { Page.find(page_id).built_revision }
  end
end
