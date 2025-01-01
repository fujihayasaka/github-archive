# typed: true
# frozen_string_literal: true

require "github-kredz"
require "test_helper"
require "test_helpers/fake_varz_response"

class VariablesTest < GitHub::TestCase
  include DogstatsTestHelpers

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @owner = create(:user)
    @installed_github_app = create(:integration, default_permissions: { "checks" => :write }, name: "Great App", owner: @owner, url: "http://great-app.com")

    @org = create(:business_organization, admin: @owner)
    @org_member = create(:user)
    @org.add_member(@org_member)

    @repo = create(:private_repository, owner: @owner)
    @org_repo = create(:repository, owner: @org)

    @rando = create(:user)
    @rando_github_app = create(:integration, default_permissions: { "checks" => :write }, name: "Another App", owner: @owner, url: "http://another-app.com")

    @repository_variables = [
        GitHub::Kredz::Services::Varz::Variable.new(name: "1234"),
        GitHub::Kredz::Services::Varz::Variable.new(name: "foobaz"),
        GitHub::Kredz::Services::Varz::Variable.new(name: "override"),
    ]

    @organization_variables = [
      GitHub::Kredz::Services::Varz::Variable.new(name: "override"),
      GitHub::Kredz::Services::Varz::Variable.new(name: "org-variable"),
    ]

    env = create(:environment, name: "PROD", repository: @repo)
    variable_owner = GitHub::Kredz::Services::Varz::VariableOwner.new(
      environment: GitHub::Kredz::Services::Varz::Environment.new(
        global_id:  GitHub.enterprise? ? env.global_relay_id : env.next_global_id,
      ),
    )

    @environment_variables = [
      GitHub::Kredz::Services::Varz::Variable.new(name: "ENV_Variable_1", owner: variable_owner),
      GitHub::Kredz::Services::Varz::Variable.new(name: "ENV_VARIABLE_2", owner: variable_owner)
    ]

    @key_name = "custom-tasks-key"
  end

  context "#embed" do
    test "embeds variables" do
      expected = String.new(
        "\x02" +
        "\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF" +
        "\x68\x65\x6c\x6c\x6f\x2c\x20\x77\x6f\x72\x6c\x64",
        encoding: Encoding::ASCII_8BIT
      )
      assert_equal expected, Variables.embed(0xDEADBEEFDEADBEEF, "hello, world")
    end
  end

  context "#for_app with Varz" do
    test "returns variables for a given integration and owner" do
      GitHub::KredzClient::Varz.expects(:list_variables)
        .with(app: @installed_github_app, owner: @org, actor: @org_member, page: 0, per_page: 0)
        .returns(build_varz_response(GitHub::Kredz::Services::Varz::ListResponse.new(variables: @organization_variables)))

      variables = Variables.for_app(@installed_github_app, owner: @org, actor: @org_member)
      assert @organization_variables.all? { |s| variables.include?(s) }
    end

    test "raises exception if Varz call fails" do
      GitHub::KredzClient::Varz.expects(:list_variables)
        .with(app: @installed_github_app, owner: @org, actor: @org_member, page: 0, per_page: 0)
        .returns(build_varz_response({}, error_code: :unavailable, error_message: "Service unavailable"))

      exception = assert_raises Variables::Error do
        Variables.for_app(@installed_github_app, owner: @org, actor: @org_member)
      end

      assert_equal "Variables service unavailable", exception.message
    end

    test "returns empty list if no variables exist for the given integration and owner" do
      GitHub::KredzClient::Varz.expects(:list_variables)
        .with(app: @rando_github_app, owner: @rando, actor: @rando, page: 0, per_page: 0)
        .returns(build_varz_response(GitHub::Kredz::Services::Varz::ListResponse.new(variables: [])))

      variables = Variables.for_app(@rando_github_app, owner: @rando, actor: @rando)
      assert_empty variables
    end
  end

  context "#for_repository with Varz" do
    test "returns variables for a given org, repo and integration" do
      GitHub::KredzClient::Varz.expects(:list_repository_variables)
        .with(app: @installed_github_app, repository: @org_repo, actor: @org_member, environments: [], include_value: true)
        .returns(build_varz_response(GitHub::Kredz::Services::Varz::ListVariablesForRepositoryResponse.new(
          repository_variables: @repository_variables,
          organization_variables: @organization_variables,
          environment_variables: @environment_variables,
        )))

      variables = Variables.for_repository(@org_repo, actor: @org_member, app: @installed_github_app)

      assert variables.key? :repository_variables
      assert variables.key? :organization_variables

      assert @organization_variables.all? { |s| variables[:organization_variables].map { |h| h[:name] }.include?(s.name) }
      assert @repository_variables.all? { |s| variables[:repository_variables].map { |h| h[:name] }.include?(s.name) }
      assert @environment_variables.all? { |s| variables[:environment_variables].map { |h| h[:name] }.include?(s.name) }
    end

    test "raises exception if Varz call fails" do
      GitHub::KredzClient::Varz.expects(:list_repository_variables)
        .with(app: @installed_github_app, repository: @org_repo, actor: @org_member, environments: [], include_value: true)
        .returns(build_varz_response({}, error_code: :unavailable, error_message: "Service unavailable"))

      exception = assert_raises Variables::Error do
        Variables.for_repository(@org_repo, actor: @org_member, app: @installed_github_app)
      end

      assert_equal "Variables service unavailable", exception.message
    end
  end

  context "#variable_count_for_environments with Varz" do
    test "handles no environments without kredz" do
      @repo.stubs(:can_use_environments?).returns(false)
      variable_counts = Variables.variable_count_for_environments(@repo, app: @installed_github_app, environments: @repo.environments)
      assert_empty variable_counts
    end

    test "returns variable counts" do
      repo_with_env = create(:repository, owner: @owner)
      repo_with_env.stubs(:can_use_environments?).returns(true)
      env = create(:environment, name: "Staging", repository: repo_with_env)

      env_global_id = GitHub.enterprise? ? env.global_relay_id : env.next_global_id
      counts_response = [
        GitHub::Kredz::Services::Varz::VariableCount.new(owner_global_id: env_global_id, count: 3),
      ]

      GitHub::KredzClient::Varz.expects(:get_variable_counts)
        .with(app: @installed_github_app, owner_ids: [env_global_id], owner_type: GitHub::KredzClient::Varz::VARIABLE_OWNER_ENVIRONMENT_TYPE)
        .returns(build_varz_response(GitHub::Kredz::Services::Varz::VariableCountsResponse.new(
          variable_counts: counts_response,
        )))

      variable_counts = Variables.variable_count_for_environments(repo_with_env, app: @installed_github_app, environments: repo_with_env.environments)
      assert_equal 1, variable_counts.size
      assert_equal env.global_relay_id, variable_counts[0].owner_global_id
      assert_equal 3, variable_counts[0].count
    end
  end

  context "#fetch with Varz" do
    test "fetches a variable" do
      GitHub::KredzClient::Varz.expects(:fetch_variable)
        .with(key: "org-variable", app: @installed_github_app, owner: @org, actor: @org_member)
        .returns(
          build_varz_response(GitHub::Kredz::Services::Varz::FetchResponse.new(
            variable: GitHub::Kredz::Services::Varz::Variable.new(name: "org-variable")
          ))
        )

      Variables.fetch(name: "org-variable", app: @installed_github_app, owner: @org, actor: @org_member)
    end

    test "records metrics about the fetch" do
      GitHub::KredzClient::Varz.expects(:fetch_variable)
        .with(key: "org-variable", app: @installed_github_app, owner: @org, actor: @org_member)
        .returns(
          build_varz_response(GitHub::Kredz::Services::Varz::FetchResponse.new(
            variable: GitHub::Kredz::Services::Varz::Variable.new(name: "org-variable")
          ))
        )

      Variables.fetch(name: "org-variable", app: @installed_github_app, owner: @org, actor: @org_member)

      assert_dogstats_timing(1, "variables.varz.fetch", tags: ["app:#{@installed_github_app.name}", "status:200", "succeeded:true"])
    end
  end

  context "#update with Varz" do
    test "updates a variable" do
      Timecop.freeze do
        value = Base64.strict_encode64("val")
        GitHub::KredzClient::Varz.expects(:update_variable)
          .with(
            app: @installed_github_app,
            owner: @org,
            actor: @org_member,
            key: "org-variable",
            value: value,
            visibility: GitHub::KredzClient::Varz::VARIABLE_VISIBILITY_SELECTED_REPOS,
            selected_repositories: [@org_repo],
            updated_key: "org-variable-new",
          )
          .returns(
            build_varz_response(GitHub::Kredz::Services::Varz::UpdateResponse.new(
              variable: GitHub::Kredz::Services::Varz::Variable.new(name: "org-variable-new")
            ))
          )

        GlobalInstrumenter.expects(:instrument).with("org_variable.update", {
          app: @installed_github_app.name,
          owner_type: :ORGANIZATION,
          owner_org: @org,
          owner_env: nil,
          owner_repo: nil,
          actor: @org_member,
          name: "org-variable",
          visibility: GitHub::KredzClient::Varz::VARIABLE_VISIBILITY_SELECTED_REPOS,
          state: :UPDATED,
          updated_at: Time.now,
          updated_name: "org-variable-new",
          varlen: 3,
        }).once

        Variables.update(
          name: "org-variable",
          app: @installed_github_app,
          owner: @org,
          actor: @org_member,
          value: value,
          visibility: GitHub::KredzClient::Varz::VARIABLE_VISIBILITY_SELECTED_REPOS,
          selected_repositories: [@org_repo],
          updated_name: "org-variable-new",
        )
      end
    end

    test "records metrics about the update" do
      Timecop.freeze do
        value = Base64.strict_encode64("val")
        GitHub::KredzClient::Varz.expects(:update_variable)
          .with(
            app: @installed_github_app,
            owner: @org,
            actor: @org_member,
            key: "org-variable",
            value: value,
            visibility: GitHub::KredzClient::Varz::VARIABLE_VISIBILITY_SELECTED_REPOS,
            selected_repositories: [@org_repo],
            updated_key: "org-variable-new",
          )
          .returns(
            build_varz_response(GitHub::Kredz::Services::Varz::UpdateResponse.new(
              variable: GitHub::Kredz::Services::Varz::Variable.new(name: "org-variable-new")
            ))
          )

        GlobalInstrumenter.expects(:instrument).with("org_variable.update", {
          app: @installed_github_app.name,
          owner_type: :ORGANIZATION,
          owner_org: @org,
          owner_env: nil,
          owner_repo: nil,
          actor: @org_member,
          name: "org-variable",
          visibility: GitHub::KredzClient::Varz::VARIABLE_VISIBILITY_SELECTED_REPOS,
          state: :UPDATED,
          updated_at: Time.now,
          updated_name: "org-variable-new",
          varlen: 3,
        }).once

        Variables.update(
          name: "org-variable",
          app: @installed_github_app,
          owner: @org,
          actor: @org_member,
          value: value,
          visibility: GitHub::KredzClient::Varz::VARIABLE_VISIBILITY_SELECTED_REPOS,
          selected_repositories: [@org_repo],
          updated_name: "org-variable-new",
        )

        assert_dogstats_timing(1, "variables.varz.update", tags: ["app:#{@installed_github_app.name}", "status:200", "succeeded:true"])
      end
    end
  end

  context "#store with Varz" do
    test "stores a variable" do
      Timecop.freeze do
        value = Base64.strict_encode64("some-variable")
        GitHub::KredzClient::Varz.expects(:store_variable)
          .with(
            app: @installed_github_app,
            owner: @org,
            actor: @org_member,
            key: "org-variable",
            value: value,
            visibility: GitHub::KredzClient::Varz::VARIABLE_VISIBILITY_SELECTED_REPOS,
            selected_repositories: [@org_repo],
          )
          .returns(
            build_varz_response(GitHub::Kredz::Services::Varz::StoreResponse.new(
              variable: GitHub::Kredz::Services::Varz::Variable.new(name: "org-variable")
            ))
          )

        GlobalInstrumenter.expects(:instrument).with("org_variable.create", {
          app: @installed_github_app.name,
          owner_type: :ORGANIZATION,
          owner_org: @org,
          owner_repo: nil,
          owner_env: nil,
          actor: @org_member,
          name: "org-variable",
          visibility: GitHub::KredzClient::Varz::VARIABLE_VISIBILITY_SELECTED_REPOS,
          state: :CREATED,
          updated_at: Time.now,
          varlen: 13
        }).once

        Variables.store(
          name: "org-variable",
          app: @installed_github_app,
          owner: @org,
          actor: @org_member,
          value: value,
          visibility: GitHub::KredzClient::Varz::VARIABLE_VISIBILITY_SELECTED_REPOS,
          selected_repositories: [@org_repo],
        )
      end
    end

    test "records metrics about the store" do
      Timecop.freeze do
        value = Base64.strict_encode64("some-variable")
        GitHub::KredzClient::Varz.expects(:store_variable)
          .with(
            app: @installed_github_app,
            owner: @org,
            actor: @org_member,
            key: "org-variable",
            value: value,
            visibility: GitHub::KredzClient::Varz::VARIABLE_VISIBILITY_SELECTED_REPOS,
            selected_repositories: [@org_repo],
          )
          .returns(
            build_varz_response(GitHub::Kredz::Services::Varz::StoreResponse.new(
              variable: GitHub::Kredz::Services::Varz::Variable.new(name: "org-variable")
            ))
          )

        GlobalInstrumenter.expects(:instrument).with("org_variable.create", {
          app: @installed_github_app.name,
          owner_type: :ORGANIZATION,
          owner_org: @org,
          owner_repo: nil,
          owner_env: nil,
          actor: @org_member,
          name: "org-variable",
          visibility: GitHub::KredzClient::Varz::VARIABLE_VISIBILITY_SELECTED_REPOS,
          state: :CREATED,
          updated_at: Time.now,
          varlen: 13
        }).once

        Variables.store(
          name: "org-variable",
          app: @installed_github_app,
          owner: @org,
          actor: @org_member,
          value: value,
          visibility: GitHub::KredzClient::Varz::VARIABLE_VISIBILITY_SELECTED_REPOS,
          selected_repositories: [@org_repo],
        )

        assert_dogstats_timing(1, "variables.varz.store", tags: ["app:#{@installed_github_app.name}", "status:200", "succeeded:true"])
      end
    end
  end

  context "#delete with Varz" do
    test "deletes a variable" do
      Timecop.freeze do
        GitHub::KredzClient::Varz.expects(:delete_variable)
          .with(key: "org-variable", app: @installed_github_app, owner: @org, actor: @org_member)
          .returns(
            build_varz_response(GitHub::Kredz::Services::Varz::DeleteResponse.new(success: true))
          )

        GlobalInstrumenter.expects(:instrument).with("org_variable.remove", {
          app: @installed_github_app.name,
          owner_type: :ORGANIZATION,
          owner_org: @org,
          owner_repo: nil,
          owner_env: nil,
          actor: @org_member,
          name: "org-variable",
          state: :DELETED,
          updated_at: Time.now,
        }).once
        Variables.delete(name: "org-variable", app: @installed_github_app, owner: @org, actor: @org_member)
      end
    end

    test "records metrics about the delete" do
      Timecop.freeze do
        GitHub::KredzClient::Varz.expects(:delete_variable)
          .with(key: "org-variable", app: @installed_github_app, owner: @org, actor: @org_member)
          .returns(
            build_varz_response(GitHub::Kredz::Services::Varz::DeleteResponse.new(success: true))
          )
        GlobalInstrumenter.expects(:instrument).with("org_variable.remove", {
          app: @installed_github_app.name,
          owner_type: :ORGANIZATION,
          owner_org: @org,
          owner_repo: nil,
          owner_env: nil,
          actor: @org_member,
          name: "org-variable",
          state: :DELETED,
          updated_at: Time.now,
        }).once
        Variables.delete(name: "org-variable", app: @installed_github_app, owner: @org, actor: @org_member)

        assert_dogstats_timing(1, "variables.varz.delete", tags: ["app:#{@installed_github_app.name}", "status:200", "succeeded:true"])
      end
    end
  end

  context "#list with Varz" do
    test "lists variables" do
      GitHub::KredzClient::Varz.expects(:list_variables)
        .with(app: @installed_github_app, owner: @org, actor: @org_member, page: 0, per_page: 0)
        .returns(build_varz_response(GitHub::Kredz::Services::Varz::ListResponse.new(variables: @organization_variables)))

      variables = Variables.list(app: @installed_github_app, owner: @org, actor: @org_member)
      assert @organization_variables.all? { |s| variables.variables.include?(s) }
    end

    test "records metrics about the list" do
      GitHub::KredzClient::Varz.expects(:list_variables)
        .with(app: @installed_github_app, owner: @org, actor: @org_member, page: 0, per_page: 0)
        .returns(build_varz_response(GitHub::Kredz::Services::Varz::ListResponse.new(variables: @organization_variables)))

      variables = Variables.list(app: @installed_github_app, owner: @org, actor: @org_member)
      assert @organization_variables.all? { |s| variables.variables.include?(s) }

      assert_dogstats_timing(1, "variables.varz.list", tags: ["app:#{@installed_github_app.name}", "status:200", "succeeded:true"])
    end
  end

  context "#list_repository with Varz" do
    test "lists variables for a repository" do
      GitHub::KredzClient::Varz.expects(:list_repository_variables)
        .with(app: @installed_github_app, repository: @org_repo, environments: Environment.none, actor: @org_member, include_value: true)
        .returns(build_varz_response(GitHub::Kredz::Services::Varz::ListVariablesForRepositoryResponse.new(
          repository_variables: @repository_variables,
          organization_variables: @organization_variables,
          environment_variables: @environment_variables,
        )))

      variables = Variables.list_repository(app: @installed_github_app, repository: @org_repo, environments: Environment.none, actor: @org_member)

      assert @organization_variables.all? { |s| variables.organization_variables.include?(s) }
      assert @repository_variables.all? { |s| variables.repository_variables.include?(s) }
      assert @environment_variables.all? { |s| variables.environment_variables.include?(s) }
    end

    test "lists only variable names for a repository when include_value is false" do
      GitHub::KredzClient::Varz.expects(:list_repository_variables)
        .with(app: @installed_github_app, repository: @org_repo, environments: [], actor: @org_member, include_value: false)
        .returns(build_varz_response(GitHub::Kredz::Services::Varz::ListVariablesForRepositoryResponse.new(
          repository_variables: @repository_variables,
          organization_variables: @organization_variables,
        )))

      variables = Variables.list_repository(app: @installed_github_app, repository: @org_repo, environments: Environment.none, actor: @org_member, include_value: false)

      assert @organization_variables.all? { |s| variables.organization_variables.include?(s) }
      assert @repository_variables.all? { |s| variables.repository_variables.include?(s) }
      assert @organization_variables.all? { |s| s.value == "" }
      assert @repository_variables.all? { |s| s.value == "" }

      assert_dogstats_timing(1, "variables.varz.list_repository", tags: ["app:#{@installed_github_app.name}", "status:200", "succeeded:true"])
    end

    test "records metrics about the list for repository" do
      GitHub::KredzClient::Varz.expects(:list_repository_variables)
        .with(app: @installed_github_app, repository: @org_repo, environments: Environment.none, actor: @org_member, include_value: true)
        .returns(build_varz_response(GitHub::Kredz::Services::Varz::ListVariablesForRepositoryResponse.new(
          repository_variables: @repository_variables,
          organization_variables: @organization_variables,
          environment_variables: @environment_variables,
        )))

      variables = Variables.list_repository(app: @installed_github_app, repository: @org_repo, environments: Environment.none, actor: @org_member)

      assert @organization_variables.all? { |s| variables.organization_variables.include?(s) }
      assert @repository_variables.all? { |s| variables.repository_variables.include?(s) }
      assert @environment_variables.all? { |s| variables.environment_variables.include?(s) }

      assert_dogstats_timing(1, "variables.varz.list_repository", tags: ["app:#{@installed_github_app.name}", "status:200", "succeeded:true"])
    end
  end

  def build_varz_response(resp, error_code: nil, error_message: nil)
    FakeVarzResponse.new(data: resp, error_code: error_code, error_message: error_message)
  end
end
