# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dependabot_github_app_helper"

class SuggesterRepositorySuggesterTest < GitHub::TestCase
  include DependabotGithubAppHelper
  include ConditionalAccess::FilterTestHelper

  fixtures do
    @owner = create :user, login: "owner", plan: "large"
    @user = create :user, login: "authed"
    @repo = create :private_repository, owner: @owner, from_example: :review_comment_source
    @repo.add_member(@user)
    @issue = create(:issue, repository: @repo)
    @issue2 = create :issue, repository: @repo
    @fork = create(:fork_repository, forker: @user, fork_repo: @repo, from_example: :review_comment_fork)
    @dependabot_repo = create(:repository, owner: @owner, from_example: :rebase_pull_request)

    make_trusted_oauth_apps_owner
    @dependabot_app = create(:dependabot_integration)
    @dependabot_bot = @dependabot_app.bot

    @authorizing_filter = cap_authorizing_filter.freeze

    GitHub.flipper[:repository_suggester_elastic_search].disable
  end

  setup do
    reset_dependabot_github_app_memoization
    GitHub.stubs(dependency_graph_enabled?: true)
    GitHub.stubs(dependabot_enabled?: true)

    refute_nil GitHub.trusted_oauth_apps_owner
    refute_nil GitHub.dependabot_github_app&.bot
  end

  def create_pull_request(user:)
    create(:pull_request,
      repository: @dependabot_repo,
      base_repository: @dependabot_repo,
      base_user: @dependabot_repo.owner,
      base_ref: "master",
      head_repository: @dependabot_repo,
      head_user: @dependabot_repo.owner,
      head_ref: "contrib",
      user: user,
    )
  end

  test "user suggestions include user repository owners when subject is a user repository" do
    suggester = create_suggester_with_cap_stubbing(viewer: @user, subject: @repo)
    assert suggester.mentions.any? { |x| x[:login] == @owner.login }
  end

  test "user suggestions dont exclude current user" do
    suggester = create_suggester_with_cap_stubbing(viewer: @user, subject: @repo)
    assert suggester.mentions.any? { |x| x[:login] == @user.login }
  end

  test "user suggestions include all repository collaborators when subject is a user repository" do
    user = create(:collaborator, repository: @repo)
    suggester = create_suggester_with_cap_stubbing(viewer: @user, subject: @repo)
    assert suggester.mentions.any? { |x| x[:login] == user.login }
  end

  test "user suggestions exclude any blocked repository collaborators when subject is a user repository" do
    blocker = create(:user)
    @repo.add_member blocker
    blocker.block @user
    suggester = create_suggester_with_cap_stubbing(viewer: @user, subject: @repo)
    refute suggester.mentions.any? { |x| x[:login] == blocker.login }
  end

  test "user suggestions include user avatar url when get_avatars is true" do
    suggester = create_suggester_with_cap_stubbing(viewer: @user, subject: @repo, get_avatars: true)

    assert suggester.mentions.any? { |x| x[:avatarUrl] == @owner.primary_avatar_url }
  end

  test "user suggestions do not include user avatar url when get_avatars is false" do
    suggester = create_suggester_with_cap_stubbing(viewer: @user, subject: @repo, get_avatars: false)
    assert suggester.mentions.any? { |x| !x.key?(:avatarUrl) }
  end

  test "user avatar is returned for bots", skip_with_all_emus: true do
    pull_request = create_pull_request(user: @dependabot_bot)
    suggester = create_suggester_with_cap_stubbing(viewer: @user, subject: pull_request, get_avatars: true)
    mentions = suggester.mentions

    assert_equal 2, mentions.size
    assert_equal "dependabot", mentions.first[:login]
    assert_equal @dependabot_bot.primary_avatar_url, mentions.first[:avatarUrl]
  end

  test "queries efficiently for blocked repository collaborators when subject is a user repository", skip_with_all_emus: true do
    GitHub.flipper[:actor_id_result_batching].enable
    blockers = create_list(:collaborator, 10, repository: @repo)
    blockers.each do |b|
      b.block(@user)
    end
    suggester = create_suggester_with_cap_stubbing(viewer: @user, subject: @repo)

    queries = log_queries { suggester.mentions }.second.
      reject { |query| query.sql.include?("flipper_features") }
    assert queries.size < blockers.size, "Expected suggested users query count " \
      "(#{queries.size}) to be lower then number of users (#{blockers.size})"
  end

  test "user suggestions exclude repository-owning Organization when subject is an org repository" do
    org = create(:organization, admin: @owner)
    org_repo = create(:repository, owner: org)
    issue = create :issue, repository: org_repo

    suggester = create_suggester_with_cap_stubbing(viewer: @owner, subject: org_repo)
    refute suggester.mentions.any? { |x| x[:login] == org.login }
  end

  test "user suggestions include members of the org's Owners team when subject is an org repository" do
    owner = create(:user)
    user = create(:user)

    org = create :organization, admin: owner
    org.add_admin(user)

    org_repo = create(:private_repository, owner: org)
    issue = create :issue, repository: org_repo

    suggester = create_suggester_with_cap_stubbing(viewer: user, subject: org_repo)
    assert suggester.mentions.any? { |x| x[:login] == owner.login }
  end

  test "user suggestions include all team members who can access repository when subject is an org repository" do
    org = create(:organization, admin: @owner)
    org_repo = create(:repository, owner: org)
    issue = create :issue, repository: org_repo
    user = create(:user)
    team = create(:team, organization: org)
    team.add_repository org_repo, :pull
    team.add_member user
    team.add_member @user

    suggester = create_suggester_with_cap_stubbing(viewer: @user, subject: org_repo)
    assert suggester.mentions.any? { |x| x[:login] == user.login }
  end

  if GitHub.spamminess_check_enabled?
    test "user suggestions exclude any users which are hidden from the caller when subject is a repository" do
      spammy_user = create :user, spammy: true
      create :issue_comment, issue: @issue, body: "sup?", user: spammy_user

      suggester = create_suggester_with_cap_stubbing(viewer: @user, subject: @repo)
      refute suggester.mentions.any? { |x| x[:login] == spammy_user.login }
    end

    test "user suggestions exclude any users which are hidden from the caller" do
      spammy_user = create :user, spammy: true
      create :issue_comment, issue: @issue, body: "sup?", user: spammy_user

      suggester = create_suggester_with_cap_stubbing(viewer: @user, subject: @issue)
      refute suggester.mentions.any? { |x| x[:login] == spammy_user.login }
    end
  end

  test "user suggestions include dependabot when subject is a PR opened by dependabot", skip_with_all_emus: true do
    pull_request = create_pull_request(user: @dependabot_bot)
    suggester = create_suggester_with_cap_stubbing(viewer: @user, subject: pull_request)
    mentions = suggester.mentions

    assert_equal 2, mentions.size
    assert_equal "dependabot", mentions.first[:login]
    assert_equal @owner.login, mentions.last[:login]
  end

  test "user suggestions do not include dependabot when subject is a random PR" do
    pull_request = create_pull_request(user: @owner)
    suggester = create_suggester_with_cap_stubbing(viewer: @user, subject: pull_request)
    mentions = suggester.mentions

    assert_equal 1, mentions.size
    assert_equal @owner.login, mentions.first[:login]
  end

  test "team suggestions are empty if repository is a user-owned repository" do
    suggester = create_suggester_with_cap_stubbing(viewer: @user, subject: @repo)
    refute suggester.mentions.any? { |x| x[:type] == "team" }
  end

  test "team suggestions exclude teams from other organizations when subject is an org-owned repository" do
    org = create(:organization, admin: @owner)
    org_repo = create(:repository, owner: org)
    issue = create :issue, repository: org_repo
    team = create(:team, organization: org)
    team.add_repository org_repo, :pull
    team.add_member @user

    org2 = create(:organization, admin: @owner)
    team2 = create :team, organization: org2
    team2.add_repository org_repo, :pull
    team2.add_member @user

    suggester = create_suggester_with_cap_stubbing(viewer: @user, subject: org_repo)
    refute suggester.mentions.any? { |x| x[:type] == "team" && x[:id] == team2.id }
  end

  test "team suggestions include repo organization teams the user is a member of when subject is an org repository" do
    org = create(:organization, admin: @owner)
    org_repo = create(:repository, owner: org)
    issue = create :issue, repository: org_repo
    team = create(:team, organization: org)
    team.add_repository org_repo, :pull
    team.add_member @user

    suggester = create_suggester_with_cap_stubbing(viewer: @user, subject: org_repo)
    assert suggester.mentions.any? { |x| x[:type] == "team" && x[:id] == team.id }
  end

  test "team suggestions exclude repo organization teams that user is not a member of when subject is an org repository" do
    org = create(:organization, admin: @owner)
    org_repo = create(:repository, owner: org)
    issue = create :issue, repository: org_repo
    team = create(:team, organization: org)
    team.add_repository org_repo, :pull
    team.add_member @user
    team2 = create(:team, organization: org)
    team2.add_repository org_repo, :pull

    suggester = create_suggester_with_cap_stubbing(viewer: @user, subject: org_repo)
    refute suggester.mentions.any? { |x| x[:type] == "team" && x[:id] == team2.id }
  end

  test "team suggestions include user avatar url when get_avatars is true" do
    org = create(:organization, admin: @owner)
    org_repo = create(:repository, owner: org)
    issue = create :issue, repository: org_repo
    team = create(:team, organization: org)
    team.add_repository org_repo, :pull
    team.add_member @user

    suggester = create_suggester_with_cap_stubbing(viewer: @user, subject: org_repo, get_avatars: true)
    assert suggester.mentions.any? { |x| x[:type] == "team" && x[:avatarUrl] == team.primary_avatar_url }
  end

  test "team suggestions do not include user avatar url when get_avatars is false" do
    org = create(:organization, admin: @owner)
    org_repo = create(:repository, owner: org)
    issue = create :issue, repository: org_repo
    team = create(:team, organization: org)
    team.add_repository org_repo, :pull
    team.add_member @user

    suggester = create_suggester_with_cap_stubbing(viewer: @user, subject: org_repo, get_avatars: false)
    assert suggester.mentions.any? { |x| x[:type] == "team" && !x.key?(:avatarUrl) }
  end


  test "user suggestions include user owners of a user repository" do
    suggester = create_suggester_with_cap_stubbing(viewer: @user, subject: @issue)
    assert suggester.mentions.any? { |x| x[:id] == @owner.id }
  end

  test "user suggestions include all collaborators on a user repository" do
    user = create(:collaborator, repository: @repo)
    suggester = create_suggester_with_cap_stubbing(viewer: @user, subject: @issue)
    assert suggester.mentions.any? { |x| x[:login] == user.login }
  end

  test "user suggestions exclude owning Organization on an org repository" do
    org = create(:organization, admin: @owner)
    org_repo = create(:repository, owner: org)
    issue = create :issue, repository: org_repo

    suggester = create_suggester_with_cap_stubbing(viewer: @owner, subject: issue)
    refute suggester.mentions.any? { |x| x[:login] == org.login }
  end

  test "user suggestions include members of the Owners team on an org repository" do
    owner = create(:user)
    user = create(:user)

    org = create :organization, admin: owner
    org.add_admin(user)

    org_repo = create(:private_repository, owner: org)
    issue = create :issue, repository: org_repo

    suggester = create_suggester_with_cap_stubbing(viewer: user, subject: issue)
    assert suggester.mentions.any? { |x| x[:login] == owner.login }
  end

  test "user suggestions include all team members who can access an org repository" do
    org = create(:organization, admin: @owner)
    org_repo = create(:repository, owner: org)
    issue = create :issue, repository: org_repo
    user = create(:user)
    team = create(:team, organization: org)
    team.add_repository org_repo, :pull
    team.add_member user
    team.add_member @user

    suggester = create_suggester_with_cap_stubbing(viewer: @user, subject: issue)
    assert suggester.mentions.any? { |x| x[:login] == user.login }
  end

  test "user suggestions include participants on the subject" do
    user = create(:collaborator, repository: @issue.repository)
    create :issue_comment, issue: @issue, body: "sup?", user: user

    suggester = create_suggester_with_cap_stubbing(viewer: @user, subject: @issue)
    assert suggester.mentions.any? { |x| x[:login] == user.login }
  end

  test "participants are marked" do
    user = create(:collaborator, repository: @issue.repository)
    create :issue_comment, issue: @issue, body: "sup?", user: user

    suggester = create_suggester_with_cap_stubbing(viewer: @user, subject: @issue)
    participant = suggester.mentions.find { |x| x[:login] == user.login }
    assert participant[:participant]
  end

  test "user suggestions don't include suspended user who opened the issue" do
    user = create(:user)
    issue = create :issue, repository: @repo
    suggester = create_suggester_with_cap_stubbing(viewer: user, subject: issue)

    user.suspend("test for participants on the subject")
    refute suggester.mentions.any? { |x| x[:login] == user.login }
  end

  test "user suggestions don't include suspended participants who commented on the issue" do
    user = create(:user)
    create :issue_comment, issue: @issue, body: "sup?", user: user
    suggester = create_suggester_with_cap_stubbing(viewer: @user, subject: @issue)

    user.suspend("test for participants on the subject")
    refute suggester.mentions.any? { |x| x[:login] == user.login }
  end

  test "team suggestions are empty if repository is not owned by an organization" do
    suggester = create_suggester_with_cap_stubbing(viewer: @user, subject: @issue)
    refute suggester.mentions.any? { |x| x[:type] == "team" }
  end

  test "team suggestions exclude teams from other organizations" do
    org = create(:organization, admin: @owner)
    org_repo = create(:repository, owner: org)
    issue = create :issue, repository: org_repo
    team = create(:team, organization: org)
    team.add_repository org_repo, :pull
    team.add_member @user

    org2 = create(:organization, admin: @owner)
    team2 = create :team, organization: org2
    team2.add_repository org_repo, :pull
    team2.add_member @user

    suggester = create_suggester_with_cap_stubbing(viewer: @user, subject: issue)
    refute suggester.mentions.any? { |x| x[:type] == "team" && x[:id] == team2.id }
  end

  test "team suggestions include repo organization teams the user is a member of" do
    org = create(:organization, admin: @owner)
    org_repo = create(:repository, owner: org)
    issue = create :issue, repository: org_repo
    team = create(:team, organization: org)
    team.add_repository org_repo, :pull
    team.add_member @user

    suggester = create_suggester_with_cap_stubbing(viewer: @user, subject: issue)
    assert suggester.mentions.any? { |x| x[:type] == "team" && x[:id] == team.id }
  end

  test "team suggestions exclude repo organization teams that user is not a member of" do
    org = create(:organization, admin: @owner)
    org_repo = create(:repository, owner: org)
    issue = create :issue, repository: org_repo
    team = create(:team, organization: org)
    team.add_repository org_repo, :pull
    team.add_member @user
    team2 = create(:team, organization: org)
    team2.add_repository org_repo, :pull

    suggester = create_suggester_with_cap_stubbing(viewer: @user, subject: issue)
    refute suggester.mentions.any? { |x| x[:type] == "team" && x[:id] == team2.id }
  end

  test "team suggestions for org members should include all non-secret org teams when subject is an org repository issue" do
    org = create(:organization)

    org_repo = create(:repository, owner: org)
    issue = create :issue, repository: org_repo

    closed_team = create(:team, organization: org, privacy: :closed)
    closed_team.add_repository(org_repo, :pull)

    secret_team = create(:team, organization: org, privacy: :secret)
    secret_team.add_repository(org_repo, :pull)

    suggester = create_suggester_with_cap_stubbing(viewer: @user, subject: issue)
    refute suggester.mentions.any? { |x| x[:type] == "team" && x[:id] == closed_team.id }
    refute suggester.mentions.any? { |x| x[:type] == "team" && x[:id] == secret_team.id }

    org.add_member @user
    suggester = create_suggester_with_cap_stubbing(viewer: @user, subject: issue)

    assert suggester.mentions.any? { |x| x[:type] == "team" && x[:id] == closed_team.id }
    refute suggester.mentions.any? { |x| x[:type] == "team" && x[:id] == secret_team.id }
  end

  test "team suggestions for org members should include all non-secret org teams when subject is an org repository", skip_with_all_emus: true do
    # This is already created by machinist while creating a :staff user.
    org = Organization.find_by_login(GitHub.trusted_oauth_apps_org_name)

    org_repo = create(:repository, owner: org)

    closed_team = create(:team, organization: org, privacy: :closed)
    closed_team.add_repository(org_repo, :pull)

    secret_team = create(:team, organization: org, privacy: :secret)
    secret_team.add_repository(org_repo, :pull)

    suggester = create_suggester_with_cap_stubbing(viewer: @user, subject: org_repo)
    refute suggester.mentions.any? { |x| x[:type] == "team" && x[:id] == closed_team.id }
    refute suggester.mentions.any? { |x| x[:type] == "team" && x[:id] == secret_team.id }

    org.add_member @user
    suggester = create_suggester_with_cap_stubbing(viewer: @user, subject: org_repo)
    assert suggester.mentions.any? { |x| x[:type] == "team" && x[:id] == closed_team.id }
    refute suggester.mentions.any? { |x| x[:type] == "team" && x[:id] == secret_team.id }
  end

  test "issue suggestions include most issue suggestions from the repository" do
    issue = create :issue, repository: @repo

    suggester = create_suggester_with_cap_stubbing(viewer: @user, subject: @issue)
    found_issues = suggester.issues.to_a

    assert_includes found_issues, @issue2
    assert_includes found_issues, issue
    refute_includes found_issues, @issue
  end

  test "issue suggestions include issues matching a substring query" do
    match0 = create(:issue, repository: @repo, title: "a zzz b zzz c zzz d")
    match1 = create(:issue, repository: @repo, title: "a yyy B yyy c yyy D")
    match2 = create(:issue, repository: @repo, title: "ABcd---")
    nonmatch0 = create(:issue, repository: @repo, title: "dcba")
    nonmatch1 = create(:issue, repository: @repo, title: "zzz")

    suggester = create_suggester_with_cap_stubbing(viewer: @user, subject: @issue, query: "abcd")
    found_issues = suggester.issues.to_a

    assert_includes found_issues, match0
    assert_includes found_issues, match1
    assert_includes found_issues, match2
    refute_includes found_issues, nonmatch0
    refute_includes found_issues, nonmatch1
  end

  test "issue suggestions include issues matching a query containing multibyte characters" do
    match = create(:issue, repository: @repo, title: "multibyte characters: あ aaa い bbb うえ ccc お #{GRIN_EMOJI}")
    nonmatch = create(:issue, repository: @repo, title: "no matches here")

    suggester = create_suggester_with_cap_stubbing(viewer: @user, subject: @issue, query: "あいうえお#{GRIN_EMOJI}")
    found_issues = suggester.issues.to_a

    assert_includes found_issues, match
    refute_includes found_issues, nonmatch
  end

  test "issue suggestions include issues matching a number query" do
    match0 = create(:issue, repository: @repo, title: "match by number alone")
    num = match0.number
    match1 = create(:issue, repository: @repo, title: "match by #{num} in the middle")
    match2 = create(:issue, repository: @repo, title: num.to_s.chars.join(" zzz "))
    nonmatch = create(:issue, repository: @repo, title: "nope")

    suggester = create_suggester_with_cap_stubbing(viewer: @user, subject: @repo, query: num.to_s)
    found_issues = suggester.issues.to_a

    assert_includes found_issues, match0
    assert_includes found_issues, match1
    assert_includes found_issues, match2
    refute_includes found_issues, nonmatch
  end

  test "a user who has made commits will no longer show up in suggestions for a private repo, if they've been removed from the owning organization" do
    test_removed_user do |user_writer|
      CommitContribution.create!(
        repository: @repo,
        user: user_writer,
        committed_date: Time.now.to_date,
      )
    end
  end

  test "a user who has participated in an issue will no longer show up in suggestions for a private repo, if they've been removed from the owning organization" do
    test_removed_user(@issue.user)
  end

  test "a user who has commented on a commit will no longer show up in suggestions for a private repo, if they've been removed from the owning organization" do
    test_removed_user do |user_commenter|
      commit = @repo.create_commit(nil, message: "test commit", author: @repo.organization.admins[0], files: [])
      create(:commit_comment, user: user_commenter, repository: @repo, commit_id: commit.oid)
      commit
    end
  end

  test "a user who has made a pull request review will no longer show up in suggestions for a private repo, if they've been removed from the owning organization" do
    test_removed_user do |user_reviewer|
      fork_owner = @repo.organization.admins[0]
      fork = create(:fork_repository, forker: fork_owner, fork_repo: @repo, from_example: :pull_request_fork)

      fork.commits.find(fork.ref_to_sha("topic"))
      pull_request =
          PullRequest.new(
              repository: @repo,
              base_repository: @repo,
              base_user: @repo.owner,
              base_ref: "master",
              head_repository: fork,
              head_user: fork.owner,
              head_ref: "topic",
              issue: @issue,
              user: fork_owner,
          )

      pull_request.save!
      pull_request.reviews.create!(user: user_reviewer, head_sha: pull_request.head_sha)

      pull_request
    end
  end

  test "issue suggestions include discussions from the repository" do
    repo = create :private_repository, owner: @owner, has_discussions: true

    # Create some issues and discussions, ordered from newer to older.
    issues_and_discussions = [
      create(:discussion, repository: repo, updated_at: 1.hour.ago),
      create(:issue, repository: repo, updated_at: 2.hours.ago),
      create(:discussion, repository: repo, updated_at: 3.hours.ago),
      create(:issue, repository: repo, updated_at: 4.hours.ago),
    ]

    suggester = create_suggester_with_cap_stubbing(viewer: @user, subject: repo)
    suggestions = suggester.issues_and_discussions.to_a

    assert_equal issues_and_discussions.map(&:number), suggestions.map(&:number)
  end

  test "issue suggestions include discussions matching a query" do
    repo = create :private_repository, owner: @owner, has_discussions: true

    discussion_match = create(:discussion, repository: repo, title: "a zzz b")
    issue_match = create(:issue, repository: repo, title: "c zzz d")
    discussion_nonmatch = create(:discussion, repository: repo, title: "e yyy f")
    issue_nonmatch = create(:issue, repository: repo, title: "g yyy h")

    suggester = Suggester::RepositorySuggester.new(viewer: @user, subject: repo, query: "zzz")
    suggestions = suggester.issues_and_discussions.to_a

    assert_includes suggestions, discussion_match
    assert_includes suggestions, issue_match
    refute_includes suggestions, discussion_nonmatch
    refute_includes suggestions, issue_nonmatch
  end

  def test_removed_user(user_writer = create(:user), &block)
    org = create(:organization)
    user_admin = create(:user)
    org.add_member(user_admin, action: :admin)
    org.add_member(user_writer, action: :write)
    org.allow_private_repository_forking(actor: user_admin)

    perform_enqueued_jobs(only: [TransferRepositoryJob, RepositoryOrchestrationJob]) { @repo.async_transfer_ownership_to(org, actor: @owner) }

    @repo.reload
    subject = block.call(user_writer) if block_given?
    subject ||= @issue

    org.remove_member!(user_writer)

    @repo.reload
    suggester = create_suggester_with_cap_stubbing(viewer: create(:user), subject: subject)
    refute suggester.mentions.any? { |x| x[:login] == user_writer.login }
  end

  def create_suggester_with_cap_stubbing(viewer:, subject:, query: "", get_avatars: false)
    Suggester::RepositorySuggester.new(
      viewer: viewer,
      subject: subject,
      cap_filter: @authorizing_filter,
      query: query,
      get_avatars: get_avatars)
  end
end
