# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dependabot_github_app_helper"

class PullRequestsCreatedByDependabotTest < GitHub::TestCase
  include DependabotGithubAppHelper

  fixtures do
    @owner = create(:user)
    @org = create(:organization, admin: @owner)
    @collaborator = create(:user)
    @security_admin = create(:user)

    @repo = create(:repository, owner: @org, from_example: :pull_request_source)
    @repo.add_member(@collaborator)
    @repo.add_member(@security_admin)

    @repo.vulnerability_manager.replace_vulnerability_alert_restricted_users_and_teams(
      user_ids: [@security_admin.id],
      team_ids: [],
    )
    @repo.save!

    make_trusted_oauth_apps_owner
    @dependabot_app = create(:dependabot_integration)
    @dependabot_installation = @dependabot_app.install_on(
      @org,
      repositories: @repo,
      installer: @owner,
      entry_point: :test_case
    ).installation

    @pull_alert = create(:repository_vulnerability_alert,
      :open,
      repository: @repo,
      vulnerable_manifest_path: "Gemfile.lock",
      affects: "rake",
    )

    @pull_update = create(:repository_dependency_update,
      :requested,
      repository: @repo,
      repository_vulnerability_alert: @pull_alert,
      manifest_path: "Gemfile.lock",
      package_name: "rake",
    )
  end

  setup do
    GitHub.stubs(:dependabot_enabled?).returns(true) if GitHub.enterprise?
    reset_dependabot_github_app_memoization
  end

  context "PullRequest.create_for" do
    test "fails if dependency update id is invalid" do
      @dependabot_app.bot.installation = @dependabot_installation
      assert_raises ActiveRecord::RecordInvalid do
        PullRequest.create_for(@repo,
          user: @dependabot_app.bot,
          base: "master",
          head: "master-merged-topic",
          title: "dependabot pr",
          body: "a dependabot pr",
          dependabot_update_id: "not-an-id",
        )
      end
    end

    test "succeeds if the dependency update has a pull_request_id that does not exist due to a rollback" do
      @pull_update.update_attribute(:pull_request_id, 42)
      @pull_update.update_attribute(:state, "complete")

      @dependabot_app.bot.installation = @dependabot_installation

      pull = PullRequest.create_for(@repo,
        user: @dependabot_app.bot,
        base: "master",
        head: "master-merged-topic",
        title: "dependabot pr",
        body: "a dependabot pr",
        dependabot_update_id: @pull_update.id,
      )
      @pull_update.reload

      assert_predicate @pull_update, :complete?
      assert_equal [@pull_update], pull.dependency_updates
      assert_equal pull, @pull_update.pull_request
    end

    test "succeeds if dependency update has previously been marked as errored" do
      @pull_update.update(state: "error", error_title: "title", error_body: "body")
      @dependabot_app.bot.installation = @dependabot_installation
      pull = PullRequest.create_for(@repo,
        user: @dependabot_app.bot,
        base: "master",
        head: "master-merged-topic",
        title: "dependabot pr",
        body: "a dependabot pr",
        dependabot_update_id: @pull_update.id,
      )
      @pull_update.reload

      assert_predicate @pull_update, :complete?
      assert_equal [@pull_update], pull.dependency_updates
      assert_equal pull, @pull_update.pull_request
    end


    test "fails if dependency update is from another repo" do
      repo = create(:repository, owner: @org)
      pull_alert = create(:repository_vulnerability_alert,
        :open,
        repository: repo,
        vulnerable_manifest_path: "Gemfile.lock",
        affects: "rake",
      )
      pull_update = create(:repository_dependency_update,
        :requested,
        repository: repo,
        repository_vulnerability_alert: @pull_alert,
        manifest_path: "Gemfile.lock",
        package_name: "rake",
      )
      @dependabot_app.bot.installation = @dependabot_installation

      assert_raises ActiveRecord::RecordInvalid do
        PullRequest.create_for(@repo,
          user: @dependabot_app.bot,
          base: "master",
          head: "master-merged-topic",
          title: "dependabot pr",
          body: "a dependabot pr",
          dependabot_update_id: pull_update.id,
        )
      end
    end

    test "does not associate dependency update for pull requests created by other bots" do
      integration = create(:integration)
      installation = integration.install_on(
        @org,
        repositories: [@repo],
        installer: @owner,
        entry_point: :test_case
      ).installation
      integration.bot.installation = installation
      pull = PullRequest.create_for(@repo,
        user: integration.bot,
        base: "master",
        head: "master-merged-topic",
        title: "dependabot pr",
        body: "a dependabot pr",
        dependabot_update_id: @pull_update.id,
      )

      assert_predicate @pull_update, :requested?
      assert_equal [], pull.dependency_updates
      assert_nil @pull_update.pull_request
    end

    test "associates pull request with dependency update and marks the update complete" do
      @dependabot_app.bot.installation = @dependabot_installation
      dependabot = @dependabot_app.bot

      assert_predicate @pull_update, :requested?
      assert_nil @pull_update.pull_request_id

      # Create first PR for the update

      pull =
        PullRequest.create_for!(
          @repo,
          base: "master",
          head: "master-forward-2",
          user: dependabot,
          title: "Bumps foo and bar",
          body: "...",
          dependabot_update_id: @pull_update.id
        )

      pull.reload
      @pull_update.reload

      assert_predicate @pull_update, :complete?
      assert_equal pull.id, @pull_update.pull_request_id

      pull.close # Close the first PR

      # Create a second PR for the same update

      pull2 =
        PullRequest.create_for!(
          @repo,
          base: "master",
          head: "update-file-1",
          user: dependabot,
          title: "Bumps foo from 0.10.0 to 1.3.0",
          body: "...",
          dependabot_update_id: @pull_update.id
        )

      pull2.reload
      @pull_update.reload

      assert_predicate @pull_update, :complete?
      assert_equal pull2.id, @pull_update.pull_request_id
    end
  end
end
