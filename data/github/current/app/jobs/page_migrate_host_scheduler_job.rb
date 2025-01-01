# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# This Job will scheduele migrate pages site from iad datacenter to azure eastus datacenter job
class PageMigrateHostSchedulerJob < ApplicationJob

  queue_as :page_migrate_host_scheduler

  retry_on_dirty_exit

  # This job is only used for a migration and will be removed
  exempt_from_tenant_context_requirement

  SCHEDULE_INTERVAL = 2.minutes

  # Don't run more than one of this job at a time
  locked_by timeout: 10.minutes, key: DEFAULT_LOCK_PROC

  BATCH_SIZE = 800

  MAX_THROTTLE_RETRIES = 4

  MAX_RSYC_FAILED_IN_THREE_SCHEDULED_RUNS = 40

  def perform
    return unless GitHub.flipper[:pages_migration_azure].enabled?
    batch_size = GitHub.flipper[:pages_migration_azure_higher_batch_size].enabled? ? 1000 : BATCH_SIZE
    Failbot.push(app: "page-migrate-host-scheduler")
    page_migrations_map = T.let([], T.untyped)

    # collecting failed rsync migrations count in last 3 scheduled runs
    # if any of the last 3 runs has more than 40 failed rsync migrations, we will skip this run
    # during the incident, the migration job failed with rsync error around 30 - 50 / mins.
    failed_rsync_migrations_count = Page::PagesMigrations.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) { Page::PagesMigrations.where("updated_at >= ?", Time.now - 3 * SCHEDULE_INTERVAL).where(status: :failed_rsync).count }
    if failed_rsync_migrations_count >= MAX_RSYC_FAILED_IN_THREE_SCHEDULED_RUNS
      GitHub.dogstats.increment "pages.azure.migration.skipped"
      return
    end

    GitHub.dogstats.increment "pages.azure.migration.scheduled"
    page_migrations = Page::PagesMigrations.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
      Page::PagesMigrations.where(status: :created).order(created_at: :asc).limit(batch_size).pluck(:id, :page_id) + retry_failed_hosts(batch_size)
    end
    page_migrations_map = page_migrations.map { |pair| { id: pair[0], page_id: pair[1] } }
    return if page_migrations_map.empty?
    process_migrations(page_migrations_map)

    # delete all succeed page migrations with succeed status
    Page::PagesMigrations.throttle_writes_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
      Page::PagesMigrations.where(status: [:succeed, :skipped_already_in_azure, :failed_nil_deployment_revision]).order(created_at: :asc).limit(1500).delete_all
    end
  end

  def process_migrations(page_migrations_map)

    # get all page ids from page migrations
    existed_page_ids = Page.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) { Page.where(id: page_migrations_map.map { |item| item[:page_id] }).pluck(:id) }
    pages_migration_id_to_update = []
    pages_migration_id_to_skip = []

    page_migrations_map.each do |pair|
      if existed_page_ids.include?(pair[:page_id])
        pages_migration_id_to_update << pair[:id]
      else
        pages_migration_id_to_skip << pair[:id]
      end
    end

    Page::PagesMigrations.throttle_writes_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
      if pages_migration_id_to_skip.any?
        GitHub.logger.info("page migration skipped, page not exist", {
          "gh.pages.existed.page.ids" => existed_page_ids,
          "gh.pages.migration.id.to.update" => pages_migration_id_to_update,
          "gh.pages.migration.ids.to.skip" => pages_migration_id_to_skip,
        })
        with_write { Page::PagesMigrations.where(id: pages_migration_id_to_skip).update_all(status: :skipped_page_missing) }
        GitHub.dogstats.count("pages.azure.migration", pages_migration_id_to_skip.count, tags: ["state:skipped", "reason:page_not_exist"])
      end

      if pages_migration_id_to_update.any?
        chunk_size = (pages_migration_id_to_update.length / 10.0).ceil
        batches = pages_migration_id_to_update.each_slice(chunk_size).to_a
        batches.each do |batch|
          batch.each do |page_migration_id|
            PageMigrateHostJob.perform_later(page_migration_id)
            GitHub.dogstats.increment "pages.azure.migration.job.schduled"
          end
          sleep 2
        end
      end
    end
  end

  def retry_failed_hosts(batch_size = BATCH_SIZE)
    if GitHub.flipper[:pages_migration_azure_retry_errors].enabled?
      state = [:failed_rsync]
      if GitHub.flipper[:pages_migration_azure_retry_running_errors].enabled?
        state << :running
      end
      Page::PagesMigrations.where(status: state)
        .where("updated_at <= ?", Time.now - 2.hours)
        .order(created_at: :asc)
        .limit(batch_size)
        .pluck(:id, :page_id)
    else
      []
    end
  end
end
