# typed: true
# frozen_string_literal: true

require "test_helper"

class ForksListingComponentTest < GitHub::TestCase
  include Forks::FixtureHelpers
  include GitHub::ComponentTestHelpers

  setup do
    @helper = FakeHelper.new
    @helper.extend Forks::PaginatedForksDependency
  end

  fixtures do
    @user = create(:user)
    @root_repo = create(:repository, owner: @user, from_example: :pull_request_source)
    3.times { create_fork(@root_repo, pushed_at: Time.now + 1.hour) }
    @path_resolver = path_resolver(
      repo_name: @root_repo.name,
      repo_owner_display_login: @root_repo.owner_display_login,
    ).freeze
  end

  def attributes
    @attributes ||= {
      child_fork_counts: Hash.new(0),
      open_pull_request_counts: Hash.new(0),
      open_issue_counts: Hash.new(0),
      stargazer_counts: Hash.new(0),
      last_updated: @root_repo.forks.pluck(:id, :pushed_at).to_h
    }
  end

  test "it renders the component" do
    render_inline(Forks::ForksListingComponent.new(forks_scope.to_a, attributes, @path_resolver), allowed_queries: 3)
    assert_test_selector "fork-detail", count: 3
  end

  test "it does not render the component" do
    attributes[:last_updated] = {}
    render_inline(Forks::ForksListingComponent.new(forks_scope.to_a, attributes, @path_resolver), allowed_queries: 3)
    refute_test_selector "fork-detail"
  end

  def forks_scope
    @helper.paginated_forks_for(repository: @root_repo, actor: @user, options: @path_resolver.options)
  end
end
