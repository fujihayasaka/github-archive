# frozen_string_literal: true

module Activity
  class Splunk
    BASE_URL = "https://splunk.githubapp.com/en-GB/app/gh_reference_app/search"
    EARLIEST = "-24h"
    LATEST = "now"
    PADDING = 3.minutes

    # We stopped logging to the legacy index on November 8th, 2024 (8pm UTC)
    LEGACY_INDEX_EOL = Time.utc(2024, 11, 8, 20)

    MONOLITH_INDEX = "rails"
    APP = "dependabot-api"

    TABLE_FIELDS = %w(
      activity_log_event
      nwo
      gh.repo.id
      repository_using_config_file
      will_pause_at
      paused_at
    ).freeze

    def self.all_activity_table_url
      new.table_url
    end

    def initialize(account: nil, repo: nil, update_config: nil, update_job: nil, pull_request: nil)
      @account = account
      @repo = repo
      @update_config = update_config
      @update_job = update_job
      @pull_request = pull_request
    end

    def table_url
      @table_url ||= "#{BASE_URL}?#{query_string}"
    end

    def api_logs_url
      @api_logs_url ||= "#{BASE_URL}?#{job_scoped_api_query_string}"
    end

    def monolith_logs_url
      @monolith_logs_url ||= "#{BASE_URL}?#{job_scoped_monolith_query_string}"
    end

    def index_name
      should_use_legacy_index? ? "catchall" : "dependabot"
    end

    private

    attr_reader :update_job

    def query_string
      [
        "earliest=#{EARLIEST}",
        "latest=#{LATEST}",
        "q=#{search_string}",
      ].join("&")
    end

    def should_use_legacy_index?
      return false if update_job.blank? || update_job.updated_at.blank?

      update_job.updated_at < LEGACY_INDEX_EOL
    end

    def search_string
      CGI.escape("#{splunk_search} | #{splunk_table}")
    end

    def splunk_search
      [
        "index=#{index_name} app=#{APP} activity_log_event=*",
        filters_from_objects,
      ].join(" ")
    end

    def splunk_table
      "table " + TABLE_FIELDS.join(" ")
    end

    def filters_from_objects
      {
        "gh.owner.id": @account&.github_id,
        "gh.repo.id": @repo&.github_id,
        "gh.dependabot_api.update_config.id": @update_config&.id,
        "gh.dependabot_api.update_job.id": @update_job&.id,
        "gh.dependabot_api.pull_request.id": @pull_request&.id,
      }.compact.map { |k, v| "#{k}=#{v}" }
    end

    def job_scoped_api_query_string
      [
        "earliest=#{job_start}",
        "latest=#{job_end}",
        "q=#{api_query_string}",
      ].join("&")
    end

    def job_scoped_monolith_query_string
      [
        "earliest=#{job_start}",
        "latest=#{job_end}",
        "q=#{monolith_query_string}",
      ].join("&")
    end

    def job_start
      (update_job.created_at - PADDING).to_i
    end

    def job_end
      ((update_job.last_transition&.created_at || Time.current) + PADDING).to_i
    end

    def api_query_string
      CGI.escape("index=#{index_name} gh_app=dependabot-api #{update_job.id}")
    end

    def monolith_query_string
      CGI.escape(
        "index=#{MONOLITH_INDEX} gh.repo.id=#{update_job.update_config.repo.github_id} " \
        "gh.actor.id=#{Dependabot::Application.github_dependabot_user_id}"
      )
    end
  end
end
