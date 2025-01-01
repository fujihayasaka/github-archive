# typed: true
# frozen_string_literal: true

require "test_helper"

class BenchmarkGraphqlJobTest < GitHub::TestCase
  fixtures do
    @user = create :user
    @private_user = create :user
    @repo = create :repository, owner: @user
    @private_repo = create :private_repository, owner: @private_user
    @private_issue = create :issue, repository: @private_repo

    @labels = []
    2.times do
      label = create :label, repository: @repo
      @labels << label
    end

    @users = []
    3.times do
      user = create :user
      @users << user
      @repo.add_member(user)
    end

    @issues = []
    12.times do |i|
      Timecop.travel((i + 1).minutes) do
        issue = create :issue, repository: @repo
        @issues << issue
      end
    end

    @issues.each do |issue|
      issue.labels = @labels
      issue.assignees = @users

      issue.save
      make_searchable(issue)
    end

    @issue = @issues.first
    @plain_issue = create :issue, repository: @repo
  end

  test "make sure the experiment pass for private issues" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    BenchmarkGraphqlJob.perform_now(@user.id, @private_repo.id, @private_issue.number)
  end

  test "make sure the experiment pass for show without mismatches" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    BenchmarkGraphqlJob.perform_now(@user.id, @repo.id, @issue.number)

    assert GitHub.dogstats.distributions("graphql.benchmark.allocations", tags: ["method:show", "type:custom"]).length > 0
    assert GitHub.dogstats.distributions("graphql.benchmark.allocations", tags: ["method:show", "type:graphql"]).length > 0
    assert GitHub.dogstats.distributions("graphql.benchmark.allocations", tags: ["method:show", "type:graphql_minimal_schema"]).length > 0
  end

  test "make sure the experiment pass for show without mismatches for a simple issue" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    BenchmarkGraphqlJob.perform_now(@user.id, @repo.id, @plain_issue.number)
  end

  test "make sure the experiment pass for show without mismatches if issue does not exist" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    BenchmarkGraphqlJob.perform_now(@user.id, @repo.id, 0)
  end

  test "make sure the experiment pass for show without mismatches if repo does not exist" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    BenchmarkGraphqlJob.perform_now(@user.id, 0, 0)
  end

  test "make sure the experiment pass for index without mismatches" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    BenchmarkGraphqlJob.perform_now(@user.id, @repo.id, nil)

  end
end
