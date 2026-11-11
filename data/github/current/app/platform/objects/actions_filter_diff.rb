# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ActionsFilterDiff < Platform::Objects::Base
      docs_category :actions
      description "Diff used in Actions path filtering"

      minimum_accepted_scopes ["repo"]

      def self.async_viewer_can_see?(permission, object)
        permission.typed_can_see?("Repository", object.repository)
      end

      def self.async_api_can_access?(permission, object)
        permission.typed_can_see?("Repository", object.repository)
      end

      field :paths, [String], "Unique paths modified", null: false
      field :advisory, String, "Reason that diff could not be generated", null: true
      field :merge_base, String, "Resolved merge-base SHA used as the diff base (null for branch-creates)", null: true

      def self.generate_async(repo, **args)
        pull = Promise.resolve(nil)
        if args.include?(:pull_request)
          database_id = Platform::Helpers::NodeIdentification.from_global_id(args[:pull_request]).last
          pull = repo.pull_requests.find_by(id: database_id)
          raise Platform::Errors::NotFound, "Could not find pull request" if pull.nil?
        end

        Promise.all([pull, repo.async_rpc]).then do |pr, rpc|
          begin
            ref = args[:ref]
            head_sha = args.fetch(:head_sha)
            base_sha = args.fetch(:base_sha)
            unless GitRPC::Util.null_oid?(base_sha) || GitRPC::Util.null_oid?(head_sha)
              GitHub.dogstats.distribution_time("actions.generate_diffs.find_commits.dist.timing") do
                base_sha = repo.rpc.merge_base(base_sha, head_sha)
              end
            end

            Generate.new(repo, pr, rpc, ref, head_sha, base_sha).result
          rescue GitRPC::Timeout
            GitHub.logger.info(
              "GitRPC timeout when finding merge base for Actions filter diff",
              "gh.repo.id": repo.id
            )
            Models::ActionsFilterDiff.unavailable(repo, "merge_base_timeout")
          rescue GitRPC::InvalidObject, GitRPC::ObjectMissing
            raise Platform::Errors::NotFound, "Could not find referenced commits"
          end
        end
      end

      class Generate
        def initialize(repo, pr, rpc, ref, head_sha, base_sha)
          @repo = repo
          @pr = pr
          @rpc = rpc
          @ref = ref
          @head_sha = head_sha
          @base_sha = base_sha
        end

        def result
          GitHub.dogstats.distribution_time("actions.generate_diffs.dist.time", tags: result_timing_tags) do
            generate_result
          end
        end

        private

        def generate_result
          return from_branch_create if branch_create?

          compare_base_with_head_sha
        end

        def compare_base_with_head_sha
          comparison = GitHub::Comparison.deprecated_build(
            @repo,
            @base_sha,
            @head_sha,
            pull: @pr,
            direct_compare: !@pr,
          )

          if comparison.diffs.unavailable_reason
            Models::ActionsFilterDiff.unavailable(@repo, comparison.diffs.unavailable_reason, merge_base: @base_sha)
          elsif comparison.empty?
            Models::ActionsFilterDiff.empty_diff(@repo, merge_base: @base_sha)
          elsif comparison.commit_limit_exceeded?
            Models::ActionsFilterDiff.too_many_commits(@repo, merge_base: @base_sha)
          elsif comparison.diffs.truncated?
            Models::ActionsFilterDiff.truncated(@repo, unique_diffs(comparison), merge_base: @base_sha)
          else
            Models::ActionsFilterDiff.new(@repo, unique_diffs(comparison), nil, merge_base: @base_sha)
          end
        end

        def from_branch_create
          # get a list a of commit shas that exist only on this branch (new commits)
          full_ref = @ref
          if !full_ref.start_with?("refs/heads/") && full_ref != "HEAD"
            full_ref = "refs/heads/#{full_ref}"
          end
          begin
            distinct_commits = SpokesAPI::Client.paged_responses do |cur|
              @repo.spokes_api.list_distinct_commits(ref: full_ref, exclude_oids: [], cursor: cur)
            end.flat_map do |response|
              response.commits.map { |item| item.oid.id }
            end
          rescue SpokesAPI::NotFound
            return Models::ActionsFilterDiff.unavailable(@repo, "ref_not_found")
          end

          # nothing new, no diff
          if distinct_commits.empty?
            return Models::ActionsFilterDiff.empty_diff(@repo)
          end

          # get the commit data for the distinct shas
          commits = @repo.read_objects(
            distinct_commits,
            :commit
          )

          # roots are the new commits that either have no parents or have parents that are not new
          # all commits marked with an asterisk here would be roots
          # commits marked with an @ are boundary commits
          # o---@---@---o     ← existing branch
          #      \   \
          #       *   *---o   ← new branch
          #        \     /
          #     *---o---o
          #            /
          #       *---o
          present = Set.new(commits.map { |c| c["oid"] })
          roots = commits.reject do |c|
            c.fetch("parents", []).any? { |oid| present.include?(oid) }
          end

          # determine all of the changed files across all of the roots
          root_parents = roots.map { |r| r.fetch("parents", []) }.flatten.uniq
          if root_parents.any?
            result = paths_from_all_unique_parent_diffs(root_parents)
            return result if result.is_a?(Models::ActionsFilterDiff)
            paths, truncated = result
            if truncated
              Models::ActionsFilterDiff.truncated(@repo, paths)
            else
              Models::ActionsFilterDiff.new(@repo, paths)
            end
          else
            compare_base_with_head_sha
          end
        end

        def paths_from_all_unique_parent_diffs(root_parents)
          paths = Set.new
          truncated = T.let(false, T::Boolean)
          root_parents.each do |parent_oid|
            comparison = GitHub::Comparison.deprecated_build(
                @repo,
                @head_sha,
                parent_oid,
                direct_compare: true,
            )

            # if we hit a too many commits in any compare, we're done
            if comparison.commit_limit_exceeded?
              return Models::ActionsFilterDiff.too_many_commits(@repo)
            elsif comparison.diffs.unavailable_reason || comparison.empty?
              next
            end

            truncated ||= !!comparison.diffs.truncated?
            paths.merge(unique_diffs(comparison))
          end
          [paths.to_a, truncated]
        end

        def unique_diffs(comparison)
          set = Set.new
          comparison.diffs.each do |d|
            set.add(d.a_path) if d.a_path.present?
            set.add(d.b_path) if d.b_path.present?
          end
          set.to_a
        end

        def branch_create?
          GitRPC::Util.null_oid?(@base_sha)
        end

        def result_timing_tags
          if @pr
            ["event:pull_request"]
          else
            ["event:push", "branch_create:#{branch_create?}"]
          end
        end
      end
    end
  end
end
