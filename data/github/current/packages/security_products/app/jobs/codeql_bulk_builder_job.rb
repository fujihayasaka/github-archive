# typed: true
# frozen_string_literal: true

# CodeqlBulkBuilderJob creates even batches of all onboarded CodeQl databases throughout the FRESHNESS_DURATION
# and refreshes them by triggering the CodeqlBulkBuilderBatchJob.
class CodeqlBulkBuilderJob < ApplicationJob
  queue_as :code_scanning_multi_repository_variant_analysis

  retry_on_dirty_exit

  SCHEDULE_INTERVAL = 1.hour.freeze
  FRESHNESS_DURATION = 1.week.freeze
  BATCH_SIZE = 100.freeze
  REF = "main"

  # do not run this job on Proxima
  exempt_from_tenant_context_requirement
  schedule interval: SCHEDULE_INTERVAL, condition: -> { !(GitHub.enterprise? || GitHub.multi_tenant_enterprise?) }

  def perform
    return if GitHub.enterprise?
    return if FeatureFlag.vexi.enabled?(:disable_codeql_database_builder_job, default: false)

    languages = CodeqlBulkBuilderConfig::ALLOWED_LANGUAGES

    # Allow disabling Swift separately since it uses macOS runners, so it is a more limited resource
    if FeatureFlag.vexi.enabled?(:code_scanning_codeql_disable_bulk_builder_swift, default: false)
      languages -= ["swift"]
    end

    # Gate Rust behind a feature flag for now
    if !FeatureFlag.vexi.enabled?(:code_scanning_rust_bulk_builder, default: false)
      languages -= ["rust"]
    end

    # Ensure that we don't exceed the maximum batch size by splitting the languages evenly
    # This will allow exceeding the batch size slightly since we're ceiling the batch size.
    batch_size = (BATCH_SIZE / languages.size.to_f).ceil

    languages.each do |language|
      all_configs = CodeqlBulkBuilderConfig.where(is_active: true).where(language: language)

      total_onboarded_repos = all_configs.count

      # Calculate even batches throughout FRESHNESS_DURATION of all onboarded repos
      limit = (total_onboarded_repos * 1.0 * SCHEDULE_INTERVAL / FRESHNESS_DURATION).ceil

      # Fetch the repos for which a build has been least-recently attempted
      repos = all_configs
        .where("last_attempted < ?", FRESHNESS_DURATION.ago)
        .order(last_attempted: :asc, id: :asc)
        .limit(limit)
        .pluck(:repository_id, :language, :last_attempted)

      # Split into batches and schedule the batches evenly spread across the schedule interval
      batches = repos.each_slice(batch_size)
      batches.each_with_index do |batch, i|
        delay = SCHEDULE_INTERVAL * i / batches.size
        CodeqlBulkBuilderBatchJob.set(wait: delay).perform_later(repos_to_build: batch, ref: REF)
      end

      ActiveRecord::Base.connected_to(role: :writing) do
        # Update the last attempted value for each repository to signal that it has been scheduled
        CodeqlBulkBuilderConfig.update_last_updated(repos.map { |id, language, _| [id, language] })
      end
    end
  end
end
