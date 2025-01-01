# typed: true
# frozen_string_literal: true

module GitHub
  module Connect
    class UsageMetricsError < StandardError; end

    class UsageMetrics

      attr_reader :collected_at

      SCHEMA_VERSION = "20230306"
      CACHE_KEY = "enterprise_installation:usage_metrics"
      CACHE_TTL = 1.day
      FAILED_METRICS_KEY = "connect-failed-metrics"
      FAILED_METRICS_BUFFER_SIZE = 7

      def initialize
        @collected_at = Time.now.utc.freeze
        @ecosystems = Packages::GettingStartedComponent.new(owner: nil).ecosystems
      end

      # Public: Gather all usage metrics.
      #
      # Note: MEC collection has been removed - https://github.com/github/connected-enterprise/issues/375
      # https://github.com/github/github/pull/204036 can be reverted if we want to re-enable MEC
      #
      # Returns a Hash.
      def data
        return {} unless GitHub.enterprise?

        instance_info
          .merge(enabled_features)
          .merge(admin_stats)
          .merge(dormant_users)
          .merge(actions_stats)
          .merge(packages_stats)
          .merge(advisory_db_stats)
      end

      # Public: Return packages usage statistics
      def packages_stats
        return {} unless GitHub.environment.fetch("ENTERPRISE_ENABLE_PACKAGES_USAGE_STATS", false) == "true"
        cached("packages_stats") do

          # This array should be updated as registries are migrated to V2
          v2_registries = ["container"]

          # Time range for daily CRUD counts
          time_range_start = 1.day.ago.beginning_of_day
          time_range_end = Time.current.midnight

          v1_total_count = Registry::Package.not_deleted.group(:package_type).count
          v1_public_count = Registry::Package.not_deleted.public_scope.group(:package_type).count
          v1_private_count = Registry::Package.not_deleted.private_scope.group(:package_type).count
          v1_daily_create_count = Registry::Package.where("created_at >= ? AND created_at < ?", time_range_start, time_range_end).group(:package_type).count
          # On creation update_at == created_at, so this should be accounted for to avoid double counting creates as updates
          v1_daily_update_count = Registry::Package.where("updated_at >= ? AND updated_at < ? AND updated_at > created_at", time_range_start, time_range_end).group(:package_type).count
          v1_daily_delete_count = Registry::Package.where("deleted_at >= ? AND deleted_at < ?", time_range_start, time_range_end).group(:package_type).count

          ecosystem_stats = []
          client = PackageRegistry::Twirp::MetadataClient.new

          ecosystem_stats = @ecosystems.map do |_key, ecosystem|

            name = ecosystem[:name]
            total_count = 0
            private_count = 0
            public_count = 0
            internal_count = 0
            user_owned_count = 0
            org_owned_count = 0
            create_count = 0
            update_count = 0
            delete_count = 0

            if v2_registries.include?(ecosystem[:name])

              #V2 registries
              if GitHub.registry_v2_enabled_for_enterprise?
                namespaces = client.get_all_namespaces["namespaces"]
                page_size = 500

                if !namespaces.nil?
                  namespaces.each do |namespace|
                    offset = 0

                    loop do
                      packages = client.get_all_packages(namespace: namespace, limit: page_size, offset: offset)
                      break if packages.size <= 0
                      offset += page_size

                      packages.each do |package|

                        if package["deleted_at"].nil?
                          total_count += 1

                          # Visibility
                          case package["visibility"]
                          when :PRIVATE
                            private_count += 1
                          when :PUBLIC
                            public_count += 1
                          when :INTERNAL
                            internal_count += 1
                          end

                          # Ownership level
                          if User.where(id: package["owner_id"], type: "User").exists?
                            user_owned_count += 1
                          end
                          if User.where(id: package["owner_id"], type: "Organization").exists?
                            org_owned_count += 1
                          end
                        end

                        # CRUD counts
                        created_at = package["created_at"].to_time unless package["created_at"].nil?
                        updated_at = package["updated_at"].to_time unless package["updated_at"].nil?
                        deleted_at = package["deleted_at"].to_time unless package["deleted_at"].nil?

                        create_count += 1 if created_at && created_at >= time_range_start && created_at < time_range_end
                        delete_count += 1 if deleted_at && deleted_at >= time_range_start && deleted_at < time_range_end

                        # Avoid double counting creates as updates
                        if updated_at && updated_at > created_at
                          update_count += 1 if updated_at >= time_range_start && updated_at < time_range_end
                        end
                      end
                    end
                  end
                end
              end
            else

              #V1 registries
              total_count = v1_total_count[name] if v1_total_count[name]
              private_count = v1_private_count[name] if v1_private_count[name]
              public_count = v1_public_count[name] if v1_public_count[name]
              create_count = v1_daily_create_count[name] if v1_daily_create_count[name]
              update_count = v1_daily_update_count[name] if v1_daily_update_count[name]
              delete_count = v1_daily_delete_count[name] if v1_daily_delete_count[name]
              user_owned_count, org_owned_count = (Registry::Package.not_deleted.where(package_type: name).reduce({ user_count: 0, org_count: 0 }) do |result, value|
                result[:user_count] += 1 if User.where(id: value.owner_id, type: "User").exists?
                result[:org_count] += 1 if User.where(id: value.owner_id, type: "Organization").exists?
                result
              end).values_at(:user_count, :org_count)
            end

            enabled_status = ENV[ecosystem[:enterprise_key]] ? ENV[ecosystem[:enterprise_key]] : "false"

            {
              name: name,
              enabled: enabled_status,
              published_packages_count: total_count,
              private_packages_count: private_count,
              public_packages_count: public_count,
              internal_packages_count: internal_count,
              user_packages_count: user_owned_count,
              organization_packages_count: org_owned_count,
              daily_update_count: update_count,
              daily_delete_count: delete_count,
              daily_create_count: create_count
            }
          end

          packages_stats = {
            registry_enabled: GitHub.registry_enabled_for_enterprise?,
            registry_v2_enabled: GitHub.registry_v2_enabled_for_enterprise?,
            ecosystems: ecosystem_stats
          }.deep_symbolize_keys
          { packages_stats: packages_stats }
        end
      end

      # Public: Get basic instance information.
      def instance_info
        {
          server_id: DotcomConnection.new.server_id,
          version: GitHub.version_number,
          collected_at: collected_at,
          schema_version: SCHEMA_VERSION,
          host_name: GitHub.host_name,
        }
      end

      # Public: Gather the metrics we need to send.
      #
      # Returns an ordered list of metrics as an Array, including metrics that we failed
      # to send over the past FAILED_METRICS_BUFFER_SIZE days. Oldest metrics first.
      #
      # A simple circular buffer is used where older metrics are discarded and newer metrics
      # are added (FIFO) if the buffer exceeds FAILED_METRICS_BUFFER_SIZE.
      #
      # Most of the time, assuming telemetry is working as expected, this will return
      # an array with the metrics for the day.
      def fetch
        all = []

        all.concat(load_failed)

        all << data

        all = all[all.size - FAILED_METRICS_BUFFER_SIZE...] if all.size >= FAILED_METRICS_BUFFER_SIZE

        all
      end

      # Public: Serialize (JSON) and store metrics for later retransmission.
      #
      # This will delete any previously failed metrics.
      #
      # The method doesn't validate the argument format, so make sure you pass an array of metrics
      # returned by the UsageMetrics.data method, something like:
      #
      #     UsageMetrics.store([UsageMetrics.data])
      #
      def store(metrics)
        data = GitHub::JSON.encode(metrics)
        ::Connect::KV.store.set(FAILED_METRICS_KEY, data)
      end

      # Public: load metrics that need to be retransmitted.
      #
      # An empty array will be returned if there are no metrics to be retransmitted.
      #
      def load_failed
        raw_data = ::Connect::KV.store.get(FAILED_METRICS_KEY).value! || "[]"
        GitHub::JSON.decode(raw_data, symbolize_names: true)
      end

      ### Define individual metrics gathering methods beyond this point and add a `.merge(<method>)` call to `data()`

      # Public: Gather all enabled features.
      def enabled_features
        cached("enabled_features") do
          features = DotcomConnection.new.current_features

          { features: features }
        end
      end

      # Public: Return the admin_stats, just as an API call to GET /enterprise/stats/all would
      def admin_stats
        admin_stats = {
          repos: GitHub::Stats::Site.repo_stats,
          hooks: GitHub::Stats::Site.hook_stats,
          pages: GitHub::Stats::Site.page_stats,
          orgs: GitHub::Stats::Site.org_stats,
          users: GitHub::Stats::Site.user_stats,
          pulls: GitHub::Stats::Site.pull_request_stats,
          issues: GitHub::Stats::Site.issue_stats,
          milestones: GitHub::Stats::Site.milestone_stats,
          gists: GitHub::Stats::Site.gist_stats,
          comments: GitHub::Stats::Site.comment_stats
        }.deep_symbolize_keys

        { admin_stats: admin_stats }
      end

      def advisory_db_stats
        cached("advisory_db_stats", ttl: CACHE_TTL) do
          {
            advisory_db_stats: {
              vulnerability_sync_enabled: GitHub.ghe_content_analysis_enabled?,
              synced_vulnerability_count: Vulnerability.count,
              # Covered by KEY `index_vulnerabilities_on_updated_at` (`updated_at`),
              latest_updated_at: Vulnerability.maximum(:updated_at),
            }.deep_symbolize_keys
          }
        end
      end

      # Public: Return the number of dormant users and the configured dormancy threshold
      def dormant_users
        cached("dormant_users") do
          {
            dormant_users: {
              total_dormant_users: User.dormant_users.count,
              dormancy_threshold: GitHub.dormancy_threshold.inspect
            }
          }
        end
      end

      # Public: Get metrics for actions usage statistics.
      def actions_stats
        return {} unless GitHub.environment.fetch("ENTERPRISE_ENABLE_ACTIONS_USAGE_STATS", false) == "true"
        cached("actions_stats") do
          time_range = (Time.current.midnight - 1.day)..Time.current.midnight
          num_repos = Repository.where("active = 1").count
          # usage metrics is only run in GHES, where there is no database sharding currently.
          active_repo_count = Actions::WorkflowRunExecution.annotate("cross-shard-query-exempted-permanent").where(created_at: time_range).distinct.count(:repository_id)
          {
            actions_stats: {
              number_of_repos_using_actions: active_repo_count,
              percentage_of_repos_using_actions: ((num_repos == 0 ? 0 : active_repo_count / num_repos.to_f) * 100).round(2)
            }
          }
        end
      end

      # Internal: Return or store the cached results of the block passed to it.
      #
      # subset - The subset of metrics to cache.
      # ttl    - The time to live for the cached results.
      # block  - The block to execute and cache the results of.
      def cached(subset, ttl: CACHE_TTL, &block)
        key = "#{CACHE_KEY}:#{subset}"
        raw_data = ::Connect::KV.store.get(key).value!
        if raw_data
          data = GitHub::JSON.decode(raw_data, symbolize_names: true)
        else
          data = yield
          value = GitHub::JSON.encode(data)
          ActiveRecord::Base.connected_to(role: :writing) do
            ::Connect::KV.store.set(key, value, expires: ttl.from_now)
          end
        end

        data.each { |k, v| data[k] = v.to_i if v.is_a?(String) }
        data
      end
    end
  end
end
