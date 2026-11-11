# typed: true
# frozen_string_literal: true

require "github/fileserver_health"
require "aqueduct"

module GitHub
  module Stats

    # Generates stats that show up on the serverstats toolbar for staff users.
    class Site

      # The stats displayed on the serverstats toolbar and used in various
      # internal tools (fs-util, etc.).
      #
      # NOTE: /site/stats.json is used like an API by some internal tools.
      # PLEASE DON'T BREAK THIS JSON OUTPUT. If you make changes to the stats
      # bar just leave the old stuff in place.
      #
      # Returns a Hash of stats.
      def self.stats(enterprise = GitHub.enterprise?)
        hash = {
          enterprise: enterprise,
          pending_jobs: pending_jobs,
          response_time: "?",
          memcached: memcached_stats,
          fs: fs_stats,
          disk: {},
          redis2: redis_status(GitHub.legacy_redis),
        }

        hash[:elasticsearch] = elasticsearch? if enterprise

        hash
      end

      # Offline fileservers.
      #
      # Returns the name of fileservers marked offline.
      def self.dead_storage_servers
        GitHub::DGit::Util::offline_fileserver_hosts
      end

      def self.pending_jobs
        GitHub::Aqueduct::Job.list_queues.map do |queue|
          GitHub::Aqueduct::Job.queue_depth(queue: queue)
        end.sum
      rescue ::Aqueduct::Client::ClientError => e
        Failbot.report(e)
        -1
      end

      def self.elasticsearch?
        Elastomer.client.available?
      end

      def self.memcached_stats
        begin
          GitHub.cache.stats
        rescue Memcached::SomeErrorsWereReported
          nil
        end
      end

      # Fileserver stats returned as a Hash where the key a String representing
      # the fileserver hostname and the value is a Boolean representing whether
      # or not the fileserver is online.
      #
      # Returns Hash.
      def self.fs_stats
        return if GitHub.enterprise?

        GitHub::DGit::Util.raw_fileserver_rows.inject({}) do |hash, fs|
          hash.update(fs["host"] => fs["online"])
        end
      end

      def self.storage_servers
        GitHub::DGit::Util::all_fileserver_hosts
      end

      def self.redis_status(connection)
        if (redis_info = connection.info rescue nil)
          {
            connected_clients: redis_info["connected_clients"],
            used_memory: redis_info["used_memory"],
            used_memory_human: "%3.1fM" % [redis_info["used_memory"].to_i / 1024 / 1024],
            keys: (redis_info["db0"] =~ /keys=(\d+)/) && $1,
            uptime: redis_info["uptime_in_days"],
          }
        end
      end

      # These are used in staff API calls for Enterprise. This
      # may be superceded at some point when the gaug.es stuff gets
      # implemented.

      if GitHub.enterprise?
        def self.stats_ttl
          10.minutes
        end

        def self.cached(subset, &block)
          key = "enterprise:stats:#{subset}"
          raw_counts = FeatureManagement::Kv.store.get(key).value!
          if raw_counts
            counts = GitHub::JSON.decode(raw_counts)
          else
            counts = yield
            value = GitHub::JSON.encode(counts)
            ActiveRecord::Base.connected_to(role: :writing) do
              FeatureManagement::Kv.store.set(key, value, expires: stats_ttl.from_now)
            end
          end

          counts.each { |k, v| counts[k] = v.to_i }
          counts
        end

        # Repository Stats
        def self.repo_stats
          cached("repos") do
            {
              "total_repos"  => Repository.where("active = 1").count,
              "root_repos"   => Repository.where("active = 1 AND parent_id IS NULL").count,
              "fork_repos"   => Repository.where("active = 1 AND parent_id IS NOT NULL").count,
              "org_repos"    => Repository.where("active = 1").org_owned.count,
              "total_pushes" => Repositories::Domain::Pushes.new.count,
              "total_wikis"  => RepositoryWiki.count,
            }
          end
        end

        # Hooks Stats
        def self.hook_stats
          cached("hooks") do
            {
              "total_hooks"    => Hook.count,
              "active_hooks"   => Hook.where("active = 1").count,
              "inactive_hooks" => Hook.where("active = 0").count,
            }
          end
        end

        # Pages Stats
        def self.page_stats
          cached("pages") do
            {
              "total_pages" => Page.count,
            }
          end
        end

        # Organization Stats
        def self.org_stats
          cached("orgs") do
            {
              "total_orgs"         => User.where("type = 'Organization' AND login != ?", GitHub.trusted_oauth_apps_org_name).count,
              "disabled_orgs"      => User.where("type = 'Organization' AND disabled = 1").count,
              "total_teams"        => Team.count,
              "total_team_members" => Team.total_team_members,
            }
          end
        end

        # User Stats
        def self.user_stats
          cached("users") do
            {
              "total_users"     => User.where("type='User' AND login != ?", GitHub.ghost_user_login).count,
              "admin_users"     => User.where("gh_role = 'staff'").count,
              "suspended_users" => User.where("type = 'User' AND suspended_at IS NOT NULL").count,
            }
          end
        end

        # Pull Request Stats
        def self.pull_request_stats
          cached("pulls") do
            {
              "total_pulls"       => PullRequest.count,
              "merged_pulls"      => PullRequest.where("merged_at IS NOT NULL").count,
              "mergeable_pulls"   => PullRequest.where("merged_at IS NULL AND mergeable = 1").count,
              "unmergeable_pulls" => PullRequest.where("merged_at IS NULL AND mergeable = 0").count,
            }
          end
        end

        # Issues Stats
        def self.issue_stats
          cached("issues") do
            {
              "total_issues"  => Issue.count,
              "open_issues"   => Issue.where("state = 'open'").count,
              "closed_issues" => Issue.where("state = 'closed'").count,
            }
          end
        end

        # Milestones Stats
        def self.milestone_stats
          cached("milestones") do
            {
              "total_milestones"  => Milestone.count,
              "open_milestones"   => Milestone.where("state = 'open'").count,
              "closed_milestones" => Milestone.where("state = 'closed'").count,
            }
          end
        end

        # Gists Stats
        def self.gist_stats
          cached("gists") do
            {
              "total_gists"   => Gist.where("delete_flag = 0").count,
              "private_gists" => Gist.where("public = 0 AND delete_flag = 0").count,
              "public_gists"  => Gist.where("public = 1 AND delete_flag = 0").count,
            }
          end
        end

        # Comments Stats
        def self.comment_stats
          cached("comments") do
            {
              "total_commit_comments"       => CommitComment.count,
              "total_gist_comments"         => GistComment.count,
              "total_issue_comments"        => IssueComment.count,
              "total_pull_request_comments" => PullRequestReviewComment.count,
            }
          end
        end

        # Security Products Stats
        def self.security_products_stats
          cached("security_products") do
            business = GitHub.global_business

            repository_table = SecurityOverviewAnalytics::Repository.table_name
            feature_status_table = SecurityOverviewAnalytics::FeatureStatus.table_name
            query = SecurityOverviewAnalytics::Repository
              .joins(:feature_status_summary)
              .where(business_id: business.id)
              .select(
                Arel.sql("COUNT(*) AS total_repos"),
                Arel.sql("SUM(IF(`#{repository_table}`.`archived` = 1, 0, 1)) AS nonarchived_repos"),
                Arel.sql("SUM(IF(`#{feature_status_table}`.`secret_scanning_alerts_status` = 'ENABLED', 1, 0)) AS secret_scanning_enabled_repos"),
                Arel.sql("SUM(IF(`#{feature_status_table}`.`secret_scanning_push_protection_status` = 'ENABLED', 1, 0)) AS secret_scanning_push_protection_enabled_repos"),
                Arel.sql("SUM(IF(`#{feature_status_table}`.`code_scanning_alerts_status` = 'ENABLED', 1, 0)) AS code_scanning_enabled_repos"),
                Arel.sql("SUM(IF(`#{feature_status_table}`.`code_scanning_pr_reviews_status` = 'ENABLED', 1, 0)) AS code_scanning_pr_reviews_enabled_repos"),
                Arel.sql("SUM(IF(`#{feature_status_table}`.`code_scanning_auto_codeql_status` = 'ENABLED', 1, 0)) AS code_scanning_default_setup_enabled_repos"),
                Arel.sql("SUM(IF(`#{feature_status_table}`.`code_scanning_auto_codeql_status` = 'ELIGIBLE', 1, 0)) AS code_scanning_default_setup_eligible_repos"),
                Arel.sql("SUM(IF(`#{feature_status_table}`.`dependabot_alerts_status` = 'ENABLED', 1, 0)) AS dependabot_alerts_enabled_repos"),
                Arel.sql("SUM(IF(`#{feature_status_table}`.`dependabot_security_updates_status` = 'ENABLED', 1, 0)) AS dependabot_security_updates_enabled_repos"),
                Arel.sql("0 AS dependabot_version_updates_enabled_repos"), # https://github.com/github/security-center/issues/6192
                Arel.sql("SUM(IF(`#{feature_status_table}`.`advanced_security_status` = 'ENABLED', 1, 0)) AS advanced_security_enabled_repos"),
              )

            stats = SecurityOverviewAnalytics::Repository.connection.select_one(query).to_h

            # TODO: `repos_with_codeql_language`.
            # Ref:
            # - https://github.com/github/security-center/issues/2789#issuecomment-1577151303
            # - https://github.com/github/github/pull/274404#discussion_r1224853600

            summary = business.advanced_security_license.entity_summary

            stats["active_committers"] = summary.active_committers
            stats["purchased_committers"] = business.advanced_security_license.seats
            stats["maximum_committers"] = summary.maximum_committers

            # Secret Protection license stats
            stats["secret_protection_licenses"] = business.secret_protection.seats
            stats["secret_protection_active_committers"] = business.secret_protection.entity_summary.active_committers

            # Code Security license stats
            stats["code_security_licenses"] = business.code_security.seats
            stats["code_security_active_committers"] = business.code_security.entity_summary.active_committers

            stats
          end
        end
      end
    end
  end
end
