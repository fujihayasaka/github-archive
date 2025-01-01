# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

class SiteScopedIntegrationInstallationTest < GitHub::TestCase
  include PermissionsHelper

  fixtures do
    @user = create(:user)
    @repo = create(:repository, :minimal, owner: @user)
    @integration = create_unlimited_global_integration

    GitHub.flipper[:disabled_global_apps].disable
    result = SiteScopedIntegrationInstallation::Creator.perform(
      @integration, @user, repositories: [@repo], entry_point: :test_case
    )
    assert_predicate result, :success?
    @subject = result.installation
  end

  context "validations" do
    test "requires an integration" do
      @subject.integration = nil

      refute_predicate @subject, :valid?
      assert_includes @subject.errors[:integration], "must exist"
    end

    test "requires a valid target" do
      @subject.target = nil

      refute_predicate @subject, :valid?
      assert_includes @subject.errors[:target], "can't be blank"

      @subject.target = @repo
      refute_predicate @subject, :valid?
      assert_includes @subject.errors[:target_type], "is not included in the list"
    end
  end

  context "#bot" do
    test "returns the integration's bot" do
      assert_equal @integration.bot, @subject.bot
    end

    test "sets the site installation as the bot's current installation context" do
      assert_equal @subject, @subject.bot.installation
    end
  end

  test "#can_have_granular_permissions?" do
    assert_predicate @subject, :can_have_granular_permissions?
  end

  test "#can_have_granular_user_permissions?" do
    refute_predicate @subject, :can_have_granular_user_permissions?
  end

  context "#generate_token" do
    test "creates a token for the installation" do
      token_value = @subject.generate_token
      token       = AuthenticationToken.with_unhashed_token(token_value).first

      assert_equal @subject, token.authenticatable
    end
  end

  context "#generate_signed_auth_token" do
    test "for a bot with site_scoped_installation" do
      bot = create(:bot)

      result = SiteScopedIntegrationInstallation::Creator.perform(
        create_unlimited_global_integration, @user, repositories: :all, entry_point: :test_case
      )
      assert_predicate result, :success?
      site_scoped_installation = result.installation

      scope = "some_scope"
      data = {
        installation_id: site_scoped_installation.id,
        installation_type: "SiteScopedIntegrationInstallation",
      }
      token = bot.signed_auth_token scope: scope, data: data
      parsed_token = User.verify_signed_auth_token scope: scope, token: token
      assert parsed_token.valid?
    end
  end

  test "#governed_by_oauth_application_policy?" do
    refute_predicate @subject, :governed_by_oauth_application_policy?
  end

  context "#installed_on_all_repositories?" do
    test "it's false when installed on selected repositories" do
      refute_predicate @subject, :installed_on_all_repositories?
    end

    test "it's true when installed on all repositories" do
      docs_repo = create(:private_repository, :minimal, owner: @user)

      result = SiteScopedIntegrationInstallation::Creator.perform(
        create_unlimited_global_integration, @user, repositories: :all, entry_point: :test_case
      )
      assert_predicate result, :success?
      site_scoped_installation = result.installation

      assert_predicate site_scoped_installation, :installed_on_all_repositories?
      assert_includes site_scoped_installation.repositories, @repo
      assert_includes site_scoped_installation.repositories, docs_repo
    end

    test "#repository_selection returns 'all' when installed on all repos" do
      result = SiteScopedIntegrationInstallation::Creator.perform(
        create_unlimited_global_integration, @user, repositories: :all, entry_point: :test_case
      )
      assert_predicate result, :success?
      site_scoped_installation = result.installation

      assert_equal "all", site_scoped_installation.repository_selection
    end
  end

  test "#launch_github_app?" do
    GitHub.stubs(:launch_github_app).returns(@integration)
    assert_predicate @subject, :launch_github_app?
  end

  test "#launch_lab_github_app?" do
    GitHub.stubs(:launch_lab_github_app).returns(@integration)
    assert_predicate @subject, :launch_lab_github_app?
  end

  context "#permissions" do
    test "returns a Hash of resource names and permission level the installation has" do
      assert_same_elements %w(metadata), @subject.permissions.keys
      assert_same_elements [:read], @subject.permissions.values
    end
  end

  context "#rate_limit" do
    test "defaults to the GitHub API default" do
      Apps::Internal::Registry.reset_configuration!
      assert_equal GitHub.api_default_rate_limit, @subject.rate_limit
    end

    test "uses override if override property is configured" do
      Apps::Internal::Registry.configure(
        app: @integration,
        app_alias: :some_internal_app,
        id: ->() { @integration.id },
        properties: {
          site_scoped_rate_limit: 125_600,
        },
      )

      assert_equal @integration, Apps::Internal.integration(:some_internal_app)
      assert_equal 125_600, @subject.rate_limit
    end
  end

  test "#version defaults to the integration latest version" do
    assert_equal @integration.latest_version, @subject.version
  end

  context "#repository_ids" do
    test "returns an Array of ids for the repositories this installation has any permission on" do
      assert_same_elements [@repo.id], @subject.repository_ids
    end

    test "limits results to a minimum of specified permissions" do
      assert_empty @subject.repository_ids(min_action: :write)
    end

    test "limits results to repos with access to the passed resources" do
      integration = create_unlimited_global_integration(permissions: { "statuses" => :read })
      installation = make_site_scoped_integration_installation(
        integration: integration, target: @user, repositories: [@repo],
      )
      assert_same_elements [@repo.id], installation.repository_ids(resource: "statuses")
    end

    test "does not include repos with access to other resources" do
      integration = create_unlimited_global_integration(permissions: { "statuses" => :read })
      installation = make_site_scoped_integration_installation(
        integration: integration, target: @user, repositories: [@repo],
      )
      assert_empty @subject.repository_ids(resource: "issues")
    end

    test "returns an empty Array if an invalid resource is passed" do
      integration = create_unlimited_global_integration(permissions: { "statuses" => :read })
      installation = make_site_scoped_integration_installation(
        integration: integration, target: @user, repositories: [@repo],
      )

      assert_empty @subject.repository_ids(resource: "stuff")
    end
  end

  context "#repositories" do
    test "returns a scoped relation for the repositories this installation has any permission on" do
      assert_same_elements [@repo], @subject.repositories.all
    end

    test "limits results to a minimum specified permission" do
      assert_empty @subject.repositories(min_action: :write)
    end

    test "limits results to repos with access via a specified resource" do
      assert_same_elements [@repo], @subject.repositories(resource: "metadata").all
    end

    test "does not include repos, with access other than the specified resource" do
      assert_empty @subject.repositories(resource: "issues")
    end

    test "returns an empty scope if passed an invalid resource" do
      assert_empty @subject.repositories(resource: "stuff")
    end
  end

  test "#using_basic_auth?" do
    refute_predicate @subject, :using_basic_auth?
  end

  test "#using_personal_access_token?" do
    refute_predicate @subject, :using_personal_access_token?
  end

  test "#user? is false" do
    refute_predicate @subject, :user?
  end

  test "#name" do
    assert_equal "site_scoped_integration_installation-#{@subject.id}", @subject.name
  end

  context "#per_repo_rate_limit?" do
    test "it is false when installed on all repos regardless of repos count" do
      assert_equal 1, @user.repositories.count
      integration = create_unlimited_global_integration(capabilities: { per_repo_rate_limit: true })
      result = SiteScopedIntegrationInstallation::Creator.perform(
        integration, @user, repositories: :all, entry_point: :test_case
      )
      assert_predicate result, :success?
      site_scoped_installation = result.installation

      refute_predicate site_scoped_installation, :per_repo_rate_limit?
    end
  end

  context "#repo_owner_rate_limit?" do
    test "it is true when installed on all repos regardless of repos count" do
      assert_equal 1, @user.repositories.count
      integration = create_unlimited_global_integration(capabilities: { repo_owner_rate_limit: true })
      result = SiteScopedIntegrationInstallation::Creator.perform(
        integration, @user, repositories: :all, entry_point: :test_case
      )
      assert_predicate result, :success?
      site_scoped_installation = result.installation

      assert_predicate site_scoped_installation, :repo_owner_rate_limit?
    end
  end

  test "destroy deletes Permission records" do
    actor   = @subject
    subject = @repo.resources.metadata

    assert_granted_in_permissions_table(
      actor_id:     actor.ability_id,
      actor_type:   actor.ability_type,
      subject_id:   subject.ability_id,
      subject_type: subject.ability_type,
    )

    perform_enqueued_jobs only: [DestroyDependentRecordsJob] do
      @subject.destroy
    end

    refute_granted_in_permissions_table(
      actor_id:     actor.ability_id,
      actor_type:   actor.ability_type,
      subject_id:   subject.ability_id,
      subject_type: subject.ability_type,
    )
  end

  context "instrumentation" do
    test "#event_context" do
      expected_context = {
        site_scoped_integration_installation:    @subject.name,
        site_scoped_integration_installation_id: @subject.id,
      }
      assert_equal @subject.event_context, expected_context

      expected_context_with_custom_prefix = {
        foo:    @subject.name,
        foo_id: @subject.id,
      }
      assert_equal @subject.event_context(prefix: :foo), expected_context_with_custom_prefix
    end
  end

  context "suspension" do
    context "#integrator_suspended?" do
      test "returns false" do
        refute_predicate @subject, :integrator_suspended?
      end
    end

    context "#user_suspended?" do
      test "returns false" do
        refute_predicate @subject, :integrator_suspended?
      end
    end

    context "#suspended?" do
      test "is true if the installation is suspended by the integrator" do
        refute_predicate @subject, :suspended?
      end
    end
  end

  context "dual writing", skip_enterprise: true, skip_in_multitenant_mode: true do
    test "was not written to lodge if the feature flag was not enabled", feature_disabled: :dual_write_site_scoped_integration_installations_to_lodge do
      lodge_id = ApplicationRecord::Lodge.connection.select_value(Arel.sql(<<-SQL, id: @subject.id))
        SELECT id FROM site_scoped_integration_installations
        WHERE id = :id
      SQL

      assert_nil lodge_id
    end

    test "inserted the same record into lodge on creation", feature_enabled: :dual_write_site_scoped_integration_installations_to_lodge do
      struct  = ScopedInstallations::AuthorizationDetails::Structs::V1.new
      subject = SiteScopedIntegrationInstallation.create(integration: @integration, target: @user, rate_limit: 100_000, authorization_details: struct.serialize)

      rows = ApplicationRecord::Lodge.connection.select_rows(Arel.sql(<<-SQL, id: subject.id))
        SELECT id,
               integration_id,
               target_id,
               target_type,
               created_at,
               updated_at,
               expires_at,
               rate_limit,
               authorization_details
        FROM site_scoped_integration_installations
        WHERE id = :id
      SQL

      assert_equal 1, rows.size
      row = rows.first

      # Remove `authorization_details` from the row and compare as a hash.
      actual_authorization_details = JSON.parse(row.delete_at(-1))

      expected = subject.attributes_for_database.values_at("id", "integration_id", "target_id", "target_type", "created_at", "updated_at", "expires_at", "rate_limit")
      assert_same_elements expected, rows.first

      assert_same_hash actual_authorization_details, subject.authorization_details
    end

    test "updates the record on lodge", feature_enabled: :dual_write_site_scoped_integration_installations_to_lodge do
      Timecop.travel(2.days) { @subject.touch }; @subject.reload

      rows = ApplicationRecord::Lodge.connection.select_rows(Arel.sql(<<-SQL, id: @subject.id))
        SELECT updated_at
        FROM site_scoped_integration_installations
        WHERE id = :id
      SQL

      assert_equal 1, rows.size
      assert_same_elements [@subject.attributes_for_database["updated_at"]], rows.first
    end

    test "deletes the record on lodge", feature_enabled: :dual_write_scoped_integration_installations_to_lodge do
      @subject.destroy

      rows = ApplicationRecord::Lodge.connection.select_rows(Arel.sql(<<-SQL, id: @subject.id))
        SELECT id
        FROM site_scoped_integration_installations
        WHERE id = :id
      SQL

      assert_empty rows
    end

    test "does not delete the record on lodge if the records are out of sync", feature_enabled: :dual_write_scoped_integration_installations_to_lodge do
      @subject.update_column(:updated_at, 2.days.from_now); @subject.reload

      @subject.destroy

      rows = ApplicationRecord::Lodge.connection.select_rows(Arel.sql(<<-SQL, id: @subject.id))
        SELECT id
        FROM site_scoped_integration_installations
        WHERE id = :id
      SQL

      assert_equal 1, rows.size
      assert_same_elements [@subject.id], rows.first
    end
  end
end
