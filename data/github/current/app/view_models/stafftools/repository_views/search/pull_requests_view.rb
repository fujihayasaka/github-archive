# typed: true
# frozen_string_literal: true

module Stafftools
  module RepositoryViews
    module Search
      class PullRequestsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels

        attr_reader :repository
        attr_reader :search_entry
        attr_reader :document_count

        DEFAULT_WORKER_COUNT = 10
        HUB_DOCS_URL = "https://thehub.github.com/epd/engineering/products-and-services/dotcom/search/manually-reindexing-repo-issues-prs"
        REPAIR_DASHBOARD_URL = "https://app.datadoghq.com/dashboard/xwr-8mu-j5s/searchrepair?fromUser=true&refresh_mode=sliding"

        def initialize(*args)
          super
          @search_entry = nil

          index = Elastomer::Indexes::PullRequests.new
          query = {
            query: { constant_score: {
              filter: { term: { repo_id: repository.id } },
            } },
            size: 1,
          }
          result = index.search(query, type: "pull_request", routing: repository.id)

          @document_count = Elastomer::UpgradeShims.get_total_hits(result["hits"])
          @search_entry = result["hits"]["hits"].first["_source"] if document_count > 0
        end

        def searchable?
          !repository.spammy? && repository.has_pull_requests?
        end

        def reindex?
          return false unless searchable?
          return false if backfill_in_progress?
          true
        end

        def reindex_reason
          return "The public flag has been updated." unless public_match?
          nil
        end

        def purge?
          !searchable? && search_entry?
        end

        def purge_reason
          return "The repository owner has been flagged as spammy." if repository.spammy?
          return "Pull requests have been disabled for this repository." unless repository.has_pull_requests?
          nil
        end

        def search_entry?
          !@search_entry.nil?
        end

        def public_match?
          return true unless search_entry?
          repository.public == search_entry["public"]
        end

        def purge_before_reindex?
          search_entry? && !public_match?
        end

        def repair_job
          return @repair_job if defined?(@repair_job)
          @repair_job = RepairPullRequestsIndexJob.new(
              "pull-requests",
              target_scope: :repository, target_scope_id: repository.id
            )
        end

        def backfill_started?
          repair_job.exists?
        end

        def backfill_in_progress?
          backfill_started? && repair_job.enabled? && !repair_job.finished?
        end

        def backfill_progress
          repair_job.progress
        end

        def backfill_paused?
          repair_job.paused?
        end

        def backfill_finished?
          backfill_started? && repair_job.finished?
        end

        def backfill_eta
          repair_job.estimated_completion_time
        end

        def backfill_label
          return "Set worker count" if backfill_in_progress?
          return "Resume backfill" if backfill_started? && (!repair_job.enabled? || !repair_job.finished?)
          "Start backfill"
        end

        def reindex_label
          "Reindex Pull Requests"
        end

        def backfill_start_time
          repair_job.stats[:started]
        end

        def backfill_elapsed_time
          repair_job.stats[:elapsed]
        end

        def backfill_finish_time
          repair_job.stats[:finished]
        end

        def backfill_wall_clock_elapsed_time
          return nil unless backfill_start_time

          end_time = if backfill_finished? && backfill_finish_time
            backfill_finish_time
          else
            Time.now
          end

          end_time - backfill_start_time
        end

        def backfill_workers_count
          repair_job.workers
        end

        def backfill_active_workers_count
          repair_job.working
        end

        def worker_count_render_value
          if backfill_in_progress?
            backfill_workers_count
          else
            DEFAULT_WORKER_COUNT
          end
        end

        def docs_url
          HUB_DOCS_URL
        end

        def repair_dashboard_url
          base_url = "#{REPAIR_DASHBOARD_URL}&tpl_var_group_key=#{repair_job.group_key}"

          return base_url unless backfill_start_time

          from_ts = (backfill_start_time.to_f * 1000).to_i

          to_ts = if backfill_finished? && backfill_finish_time.is_a?(Time)
            (backfill_finish_time.to_f * 1000).to_i
          else
            # Set to the top of the next hour from Time.now (minimum 2 hours out)
            # Example: if it's 9:08 now, set to 11:00
            next_hour = Time.now.beginning_of_hour + 2.hours
            (next_hour.to_f * 1000).to_i
          end

          "#{base_url}&from_ts=#{from_ts}&to_ts=#{to_ts}&live=true"
        end

        def hubber_tools_available?
          !GitHub.enterprise?
        end

        def pr_backfill_named_scopes_enabled?
          current_user.feature_flag_enabled?(:elastomer_pr_backfill_named_scopes, default: false)
        end
      end
    end
  end
end
