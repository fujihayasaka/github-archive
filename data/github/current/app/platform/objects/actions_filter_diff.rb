# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ActionsFilterDiff < Platform::Objects::Base
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
            unless base_sha == GitHub::NULL_OID || head_sha == GitHub::NULL_OID
              GitHub.dogstats.distribution_time("actions.generate_diffs.find_commits.dist.timing") do
                base_sha = repo.rpc.merge_base(base_sha, head_sha)
              end
            end

            Generate.new(repo, pr, rpc, ref, head_sha, base_sha).result
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
            Models::ActionsFilterDiff.unavailable(@repo, comparison.diffs.unavailable_reason)
          elsif comparison.empty?
            Models::ActionsFilterDiff.empty_diff(@repo)
          elsif comparison.commit_limit_exceeded?
            Models::ActionsFilterDiff.too_many_commits(@repo)
          else
            Models::ActionsFilterDiff.new(@repo, unique_diffs(comparison))
          end
        end

        def from_branch_create
          # get a list a of commit shas that exist only on this branch (new commits)
          distinct_commits = @rpc.distinct_commits(@ref, exclude: [])

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
            paths = paths_from_all_unique_parent_diffs(root_parents)
            Models::ActionsFilterDiff.new(@repo, paths)
          else
            compare_base_with_head_sha
          end
        end

        def paths_from_all_unique_parent_diffs(root_parents)
          paths = Set.new
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

            paths.merge(unique_diffs(comparison))
          end
          paths.to_a
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
          @base_sha == ::GitHub::NULL_OID
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
