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
          redis2: redis_status(GitHub.job_coordination_redis),
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
          raw_counts = GitHub.kv.get(key).value! # rubocop:todo GitHub/DoNotUseGlobalKv
          if raw_counts
            counts = GitHub::JSON.decode(raw_counts)
          else
            counts = yield
            value = GitHub::JSON.encode(counts)
            ActiveRecord::Base.connected_to(role: :writing) do
              GitHub.kv.set(key, value, expires: stats_ttl.from_now) # rubocop:todo GitHub/DoNotUseGlobalKv
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
              "total_pushes" => Repositories::Domain::Pushes.new(:stafftools).count,
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
            enabled_state = "enrolled"
            eligible_state = "eligible"

            repo_counts_by_archived = RepositorySecurityCenterConfig
              .group(:owner_id, :archived)
              .pluck(:owner_id, :archived, Arel.sql("COUNT(*) AS repo_count"))
              .each_with_object({}) do |(_, archived, repo_count), repo_counts_by_archived|
                # GROUP BY owner_id and feature_type to utilize existing index
                # SUM repo_count in memory to get total number of repos per feature_type
                repo_counts_by_archived[archived] ||= 0
                repo_counts_by_archived[archived] += repo_count
              end
            total_repos = repo_counts_by_archived.values.sum
            nonarchived_repos = repo_counts_by_archived[false] || 0
            stats = {
              "total_repos" => total_repos,
              "nonarchived_repos" => nonarchived_repos,
            }

            repo_counts_by_feature = RepositorySecurityCenterStatus
              .where(scanning_status: [enabled_state, eligible_state])
              .group(:owner_id, :feature_type)
              .pluck(:owner_id, :feature_type, :scanning_status, Arel.sql("COUNT(*) AS repo_count"))
              .each_with_object({}) do |(_, feature_type, scanning_status, repo_count), repo_counts_by_feature|
                # GROUP BY owner_id and feature_type to utilize existing index
                # SUM repo_count in memory to get total number of repos per feature_type
                repo_counts_by_feature[feature_type] ||= { enabled_state => 0, eligible_state => 0 }
                repo_counts_by_feature[feature_type][scanning_status] += repo_count
              end

            stats = RepositorySecurityCenterStatus.all_feature_types.each_with_object(stats) do |feature_type, stats|
              if feature_type == RepositorySecurityCenterStatus.feature_types[:code_scanning_auto_codeql]
                default_setup_feature_type = "code_scanning_default_setup"
                stats["#{default_setup_feature_type}_enabled_repos"] = repo_counts_by_feature.dig(feature_type, enabled_state) || 0
                stats["#{default_setup_feature_type}_eligible_repos"] = repo_counts_by_feature.dig(feature_type, eligible_state) || 0
              else
                stats["#{feature_type}_enabled_repos"] = repo_counts_by_feature.dig(feature_type, enabled_state) || 0
              end
            end

            stats["advanced_security_enabled_repos"] = RepositorySecurityCenterConfig
              .where(ghas_enabled: true)
              .count

            # TODO: `repos_with_codeql_language`.
            # Ref:
            # - https://github.com/github/security-center/issues/2789#issuecomment-1577151303
            # - https://github.com/github/github/pull/274404#discussion_r1224853600

            business = GitHub.global_business

            summary = business.advanced_security_summary

            stats["active_committers"] = summary.active_committers
            stats["purchased_committers"] = business.advanced_security_license.seats
            stats["maximum_committers"] = summary.maximum_committers

            stats
          end
        end
      end
    end
  end
end
