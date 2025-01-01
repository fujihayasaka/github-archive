# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dependabot_github_app_helper"

class PullRequestParticipantsForDependabotTest < GitHub::TestCase
  include DependabotGithubAppHelper

  fixtures do
    make_trusted_oauth_apps_owner
    @dependabot_app = create(:dependabot_integration)
    @dependabot_bot = @dependabot_app.bot

    @repo_owner = create(:user, login: "repo-owner")
    @repo       = create(:repository, owner: @repo_owner)
  end

  setup do
    reset_cache
    reset_repo_root
    reset_dependabot_github_app_memoization

    example_repo :rebase_pull_request, @repo

    GitHub.stubs(dependency_graph_enabled?: true)
    GitHub.stubs(dependabot_enabled?: true)

    refute_nil GitHub.trusted_oauth_apps_owner
    refute_nil GitHub.dependabot_github_app&.bot
  end

  def create_pull_request(user:)
    create(:pull_request,
      repository: @repo,
      base_repository: @repo,
      base_user: @repo.owner,
      base_ref: "master",
      head_repository: @repo,
      head_user: @repo.owner,
      head_ref: "contrib",
      user: user,
    )
  end

  test "list of participants, by default, does not include Dependabot" do
    pull = create_pull_request(user: @dependabot_bot)

    assert_empty pull.participants_for(@repo_owner)
  end

  test "list of participants includes Dependabot when asked for" do
    pull = create_pull_request(user: @dependabot_bot)

    assert_equal [@dependabot_bot], pull.participants_for(@repo_owner, remove_dependabot: false)
  end

  test "list of participants does include random bots" do
    bot = create(:integration, name: "simple-ci").bot
    pull = create_pull_request(user: bot)

    assert_empty pull.participants_for(@repo_owner, remove_dependabot: false)
  end
end
