# typed: true
# frozen_string_literal: true

require "test_helper"

class Forks::PaginatedForksDependencyTest < GitHub::TestCase
  include Forks::FixtureHelpers

  module HelperTestHelper
    def permitted_params
      @params ||= ActionController::Parameters.new
      @params.permit(:sort_by, :period, :page, :user_id, :repository, :include)
    end

    def user_or_global_feature_enabled?(feature_name)
      GitHub.flipper[feature_name].enabled?
    end
  end

  setup do
    @helper = FakeHelper.new
    @helper.extend Forks::PaginatedForksDependency
    @helper.extend HelperTestHelper
    @user = create :user
    @root_repo = create :repository, owner: @user, from_example: :forkable
    @helper.current_repository = @root_repo
    3.times do
      repo = create_fork(@root_repo, pushed_at: Time.now + 1.hour)
      example_repo :rebase_pull_request, repo
    end
  end

  def controls(options = {})
    Forks::SearchOptionsResolver.new(**options)
  end

  context "#paginated_forks_for" do
    context "when sorting by" do
      test "most_starred" do
        @root_repo.forks.first.update!(stargazer_count: 25)
        @root_repo.forks.second.update!(stargazer_count: 100)
        expected_order = [@root_repo.forks.second, @root_repo.forks.first, @root_repo.forks.last]
        assert_query_count(5) do
          forks = @helper.paginated_forks_for(
            repository: @root_repo,
            actor: nil,
            options: controls
          ).to_a
          assert_equal expected_order, forks
        end
      end

      test "recently updated" do
        @root_repo.forks.first.update!(pushed_at: Time.now + 1.day)
        @root_repo.forks.second.update!(pushed_at: Time.now + 3.days)
        @root_repo.forks.last.update!(pushed_at: Time.now + 2.days)
        expected_order = [@root_repo.forks.second, @root_repo.forks.last, @root_repo.forks.first]
        assert_query_count(5) do
          forks = @helper.paginated_forks_for(
            repository: @root_repo,
            actor: nil,
            options: controls(sort_by: :last_updated)
          ).to_a
          assert_equal expected_order, forks
        end
      end

      test "open issues" do
        2.times { create :issue, repository: @root_repo.forks.last }
        create :issue, repository: @root_repo.forks.first

        expected_order = [@root_repo.forks.last, @root_repo.forks.first, @root_repo.forks.second]

        assert_query_count(5) do
          forks = @helper.paginated_forks_for(
            repository: @root_repo,
            actor: nil,
            options: controls(sort_by: :open_issue_counts)
          ).to_a
          assert_equal expected_order, forks
        end
      end

      test "open pull requests" do
        pr_repo = @root_repo.forks.last
        create_pull_request pr_repo

        assert_query_count(5) do
          forks = @helper.paginated_forks_for(
            repository: @root_repo,
            actor: nil,
            options: controls(sort_by: :open_pull_request_counts)
          ).to_a
          assert_equal pr_repo, forks.first
        end
      end
    end

    context "when filtering" do
      test ":untouched" do
        forks = @helper.paginated_forks_for(
          repository: @root_repo,
          actor: nil,
          options: controls(include: [:inactive])
        ).to_a
        assert_empty forks
      end

      test ":archived" do
        @root_repo.forks.first.update!(maintained: false)
        assert_equal 2, @helper.paginated_forks_for(
          repository: @root_repo,
          actor: nil,
          options: controls
        ).count
        assert_equal 3, @helper.paginated_forks_for(
          repository: @root_repo,
          actor: nil,
          options: controls(include: [:active, :archived])
        ).count
      end

      test ":unstarred" do
        assert_empty @helper.paginated_forks_for(
          repository: @root_repo,
          actor: nil,
          options: controls(include: [:starred])
        )
      end
    end
  end

end
