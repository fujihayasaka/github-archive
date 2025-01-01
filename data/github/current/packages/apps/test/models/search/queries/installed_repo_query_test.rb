# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchQueriesInstalledRepoQueryTest < GitHub::TestCase
  fixtures do
    @owner = create(:paid_user, login: "owner")

    @private_repo = create(
      :private_repository,
      owner: @owner,
      name: "owner-repo"
    )

    @public_repo = create(
      :repository,
      owner: @owner,
      name: "owner-repo-public"
    )

    @integration = create(
      :integration,
      owner: create(:user),
      default_permissions: { "metadata" => :read }
    )

    @installation = make_integration_installation(
      integration: @integration,
      repositories: [@private_repo, @public_repo]
    )
  end

  test "includes installation repos in must collection" do
    @owner.oauth_access = @integration.grant(@owner, entry_point: :test_case)

    query = Search::Queries::InstalledRepoQuery.new(
      current_user: @owner,
      installation: @installation,
      page: 1
    )

    target_repo_ids = [@private_repo, @public_repo].map &:id
    query.phrase = "pha"
    actual = query.build_query

    actual_must = actual[:bool][:filter][:bool][:must]
    assert_same_elements target_repo_ids, actual_must[:terms][:repo_id]
  end

  test "instruments searches without repo_id in collection" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    query = Search::Queries::InstalledRepoQuery.new(
      current_user: @owner,
      installation: nil,
      page: 1
    )

    query.phrase = "pha"
    built_query = query.build_query

    assert_nil built_query[:build]

    query.execute

    assert_equal 1, GitHub.dogstats.increments("search.query.no_installed_repos").length
  end
end
