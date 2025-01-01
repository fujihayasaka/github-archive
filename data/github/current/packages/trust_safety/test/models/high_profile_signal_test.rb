# typed: true
# frozen_string_literal: true

require "test_helper"

class HighProfileSignalsTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository)
  end

  # High Profile repos are defined by the following Trust & Safety criteria:
  # https://github.com/github/trust-safety/blob/main/docs/operations/escalation-procedures/high-profile-escalation.md
  context "#high_profile_repo?" do
    test "false if high profile criteria not met" do
      high_profile, high_profile_reason = HighProfileSignals.high_profile_repo?(@repo)
      refute high_profile
      assert_nil high_profile_reason
    end

    test "false if repo is private" do
      private_repo = create(:private_repository)

      high_profile, high_profile_reason = HighProfileSignals.high_profile_repo?(private_repo)
      refute high_profile
      assert_nil high_profile_reason
    end

    test "true if high profile criteria for forks_count is met" do
      50.times do
        forker = create(:user)
        create(:fork_repository, forker: forker, fork_repo: @repo)
      end

      assert_equal(50, @repo.forks_count)

      high_profile, high_profile_reason = HighProfileSignals.high_profile_repo?(@repo)
      assert high_profile
      assert_equal "Repository meets criteria threshold: forks count", high_profile_reason
    end

    test "true if high profile criteria for watchers_count is met" do
      100.times do
        watcher = create(:user)
        watcher.watch_repo(@repo)
      end

      assert_equal(100, @repo.watchers_count)

      high_profile, high_profile_reason = HighProfileSignals.high_profile_repo?(@repo)
      assert high_profile
      assert_equal "Repository meets criteria threshold: watchers count", high_profile_reason
    end

    test "true if high profile criteria for contributors is met" do
      10.times do
        contributor = create(:user)
        create(:commit_contribution, :with_summaries, repository: @repo, user: contributor, commit_count: 1)
      end

      assert_equal(10, CommitContributions.domain.contributors_count_for_repository(@repo))

      high_profile, high_profile_reason = HighProfileSignals.high_profile_repo?(@repo)
      assert high_profile
      assert_equal "Repository meets criteria threshold: contributors count", high_profile_reason
    end

    test "true for multiple high profile criteria" do
      100.times do
        watcher = create(:user)
        watcher.watch_repo(@repo)
      end

      10.times do
        contributor = create(:user)
        create(:commit_contribution, :with_summaries, repository: @repo, user: contributor, commit_count: 1)
      end

      50.times do
        forker = create(:user)
        create(:fork_repository, forker: forker, fork_repo: @repo)
      end


      assert_equal(50, @repo.forks_count)
      assert_equal(100, @repo.watchers_count)
      assert_equal(10, CommitContributions.domain.contributors_count_for_repository(@repo))

      high_profile, high_profile_reason = HighProfileSignals.high_profile_repo?(@repo)
      assert high_profile
      assert_equal "Repository meets criteria threshold: forks count, watchers count, contributors count", high_profile_reason
    end

    test "true if high profile criteria for repository dependents is met" do
      GitHub.stubs(:dependency_graph_enabled?).returns(true)
      Repository.any_instance.stubs(:dependency_graph_enabled?).returns(true)

      packages = DependencyGraph::Package.wrap([
        { node: {
          name: "test-package",
          abstractRepositoryDependents: {
            totalCount: 40,
          },
        }
      }.with_indifferent_access
      ])

      Platform::Loaders::Dependencies
        .stubs(:load_packages)
        .with({
          package_filter: {
            repository_id: @repo.id,
            first: 1,
            package_id: @repo.used_by_package_id,
            preview: @repo.dependency_graph_preview?,
          },
          dependents_filter: {
            type: :repository,
            first: 8,
          },
          include_dependents: true,
        })
        .returns(Promise.new.fulfill(GitHub::Result.new { packages }))

      high_profile, high_profile_reason = HighProfileSignals.high_profile_repo?(@repo)
      assert high_profile
      assert_equal "Repository meets criteria threshold: has dependents", high_profile_reason
    end

    test "true if high profile criteria for package dependents is met" do
      GitHub.stubs(:dependency_graph_enabled?).returns(true)
      Repository.any_instance.stubs(:dependency_graph_enabled?).returns(true)

      packages = DependencyGraph::Package.wrap([
        { node: {
          name: "test-package",
          dependents: {
            edges: [
              {
                node: {
                  name: "rails",
                  repositoryId: 400,
                },
              },
            ],
            pageInfo: {
              hasPreviousPage: true,
              hasNextPage: true,
            },
          },
        }
      }.with_indifferent_access
      ])

      Platform::Loaders::Dependencies
        .stubs(:load_packages)
        .with({
          package_filter: {
            repository_id: @repo.id,
            first: 1,
            package_id: @repo.used_by_package_id,
            preview: @repo.dependency_graph_preview?,
          },
          dependents_filter: {
            type: :repository,
            first: 8,
          },
          include_dependents: true,
        })
        .returns(Promise.new.fulfill(GitHub::Result.new { packages }))

      high_profile, high_profile_reason = HighProfileSignals.high_profile_repo?(@repo)
      assert high_profile
      assert_equal "Repository meets criteria threshold: has dependents", high_profile_reason
    end
  end
end
