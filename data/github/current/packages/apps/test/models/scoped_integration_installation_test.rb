# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

class ScopedIntegrationInstallationTest < GitHub::TestCase
  include PermissionsHelper
  include DogstatsTestHelpers

  fixtures do
    @user = create(:user)
    @repo = create(:repository, :minimal, owner: @user)

    @installation = make_integration_installation(target: @user, permissions: { "metadata" => :read })
    @integration = @installation.integration

    result = ScopedIntegrationInstallation::Creator.perform(
      @installation, repositories: [@repo], entry_point: :test_case
    )
    assert_predicate result, :success?

    @subject = result.installation
  end

  context "validations" do
    test "requires a parent installation" do
      @subject.parent = nil

      refute_predicate @subject, :valid?
      assert_includes @subject.errors[:parent], "must exist"
    end

    test "requires a persisted installation" do
      @subject.parent = IntegrationInstallation.new

      refute_predicate @subject, :valid?
      assert_includes @subject.errors[:integration_installation_id], "can't be blank"
    end
  end

  test "#async_target returns a Promise with the parent's target" do
    assert_kind_of Promise, @subject.async_target
    assert_equal @installation.target, @subject.async_target.sync
  end

  test "#target_id and #target_type are delegated to the parent's target" do
    assert_equal @installation.target_id,   @subject.target_id
    assert_equal @installation.target_type, @subject.target_type
  end

  test "#integration_id is the parent's integration_id" do
    assert_equal @installation.integration_id, @subject.integration_id
  end

  context "#bot" do
    test "returns the integration's bot" do
      integration = @subject.integration
      assert_equal integration.bot, @subject.bot
    end

    test "sets the installation as the bot's current installation context" do
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

      assert_equal @subject, token&.authenticatable
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
      user = create(:user)
      repo_1 = create(:private_repository, :minimal, owner: user)
      repo_2 = create(:repository, :minimal, owner: user)

      installation = make_integration_installation(
        target: user,
        permissions: { "metadata" => :read, "contents" => :read },
      )

      scoped_installation = make_scoped_integration_installation(
        parent: installation, repositories: :all,
      )

      assert_predicate scoped_installation, :installed_on_all_repositories?
      assert_includes scoped_installation.repositories, repo_1
      assert_includes scoped_installation.repositories, repo_2
    end
  end

  test "#launch_github_app?" do
    GitHub.stubs(:launch_github_app).returns(@installation.integration)
    assert_predicate @subject, :launch_github_app?
  end

  test "#launch_lab_github_app?" do
    GitHub.stubs(:launch_lab_github_app).returns(@installation.integration)
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
      assert_equal GitHub.api_default_rate_limit, @subject.rate_limit
    end

    test "leans on the parent's custom permanent rate limit" do
      @installation.update(rate_limit: 20000)
      assert_equal 20000, @subject.rate_limit
    end

    test "returns the parent's temporary_rate_limit if one is set" do
      @installation.update(rate_limit: 20000, dynamic_rate_limit: 20020)
      @installation.set_temporary_rate_limit(30000)
      assert_equal 30000, @subject.rate_limit
    end

    test "returns the parent's override limit if one is set, and there is no temporary limit" do
      GitHub.flipper[:override_actions_per_repo_rate_limit].disable

      @installation.update(
        temporary_rate_limit_expires_at: 1.day.ago,
        dynamic_rate_limit: 20020,
        rate_limit: 40000)

      assert_equal 40000, @subject.rate_limit
    end

    test "returns the parent's dynamic rate limit if one is set, and there is no override or temporary limit" do
      GitHub.flipper[:override_actions_per_repo_rate_limit].disable

      @installation.update(
        temporary_rate_limit_expires_at: 1.day.ago,
        dynamic_rate_limit: 20000,
        rate_limit: nil)

      assert_equal 20000, @subject.rate_limit
    end

    test "returns its own rate limit when the App has per-repo rate limit capability" do
      GitHub.flipper[:override_actions_per_repo_rate_limit].disable

      app = create_privileged_app_with_capabilities(
        capabilities: { per_repo_rate_limit: true },
        properties: { hourly_per_repo_rate_limit: 500 },
      )

      installation = make_integration_installation(
        integration: app, target: @user, permissions: { "metadata" => :read },
      )

      result = ScopedIntegrationInstallation::Creator.perform(
        installation, repositories: [@repo], entry_point: :test_case
      )
      assert_predicate result, :success?

      assert_equal 500, result.installation.rate_limit
    end

    test "returns the default per repo rate limit when the App has per-repo rate limit capability but the quota is not configured" do
      GitHub.flipper[:override_actions_per_repo_rate_limit].disable

      app = create_privileged_app_with_capabilities(
        capabilities: { per_repo_rate_limit: true },
      )

      installation = make_integration_installation(integration: app, target: @user, permissions: { "metadata" => :read })

      result = ScopedIntegrationInstallation::Creator.perform(
        installation, repositories: [@repo], entry_point: :test_case
      )
      assert_predicate result, :success?

      assert_equal 1000, result.installation.rate_limit
    end

    test "returns the parent limit when the App has per-repo rate limit capability _and_ multiple repositories" do
      GitHub.flipper[:override_actions_per_repo_rate_limit].disable

      app = create_privileged_app_with_capabilities(capabilities: { per_repo_rate_limit: true })
      repo_two = create(:repository, :minimal, owner: @user)

      installation = make_integration_installation(integration: app, target: @user, permissions: { "metadata" => :read })

      result = ScopedIntegrationInstallation::Creator.perform(
        installation, repositories: [@repo, repo_two], entry_point: :test_case
      )
      assert_predicate result, :success?

      ScopedIntegrationInstallation.stub_const(:PER_REPO_RATE_LIMIT, 10) do
        assert_equal installation.rate_limit, result.installation.rate_limit
      end
    end

    test "returns the per repo limit when the override_actions_per_repo_rate_limit flag is set and the app is not Actions" do
      GitHub.flipper[:override_actions_per_repo_rate_limit].enable

      per_repo_limit = 1234
      app = create_privileged_app_with_capabilities(
        capabilities: { per_repo_rate_limit: true },
        properties: { hourly_per_repo_rate_limit: per_repo_limit },
      )

      installation = make_integration_installation(
        integration: app, target: @user, permissions: { "metadata" => :read },
      )

      result = ScopedIntegrationInstallation::Creator.perform(
        installation, repositories: [@repo], entry_point: :test_case
      )
      assert_predicate result, :success?

      refute_equal installation.rate_limit, result.installation.rate_limit
      assert_equal per_repo_limit, result.installation.rate_limit
    end

    test "returns the parent limit when the override_actions_per_repo_rate_limit flag is set" do
      GitHub.flipper[:override_actions_per_repo_rate_limit].enable

      per_repo_limit = 1234
      app = create_privileged_app_with_capabilities(
        capabilities: { per_repo_rate_limit: true },
        properties: { hourly_per_repo_rate_limit: per_repo_limit },
      )

      GitHub.stubs(:launch_github_app).returns(app)

      installation = make_integration_installation(
        integration: app, target: @user, permissions: { "metadata" => :read },
      )

      result = ScopedIntegrationInstallation::Creator.perform(
        installation, repositories: [@repo], entry_point: :test_case
      )
      assert_predicate result, :success?

      refute_equal per_repo_limit, result.installation.rate_limit
      assert_equal installation.rate_limit, result.installation.rate_limit
    end
  end

  context "#repository_ids" do
    test "returns an Array of ids for the repositories this installation has any permission on" do
      parent   = make_integration_installation(repositories: [@repo], permissions: { "metadata" => :read })
      @subject = make_scoped_integration_installation(parent: parent, repositories: [@repo])

      assert_same_elements [@repo.id], @subject.repository_ids
    end

    test "limits results to a minimum specified permission" do
      parent   = make_integration_installation(repositories: [@repo], permissions: { "metadata" => :read })
      @subject = make_scoped_integration_installation(parent: parent, repositories: [@repo])

      assert_empty @subject.repository_ids(min_action: :write)
    end

    test "limits results to repos with access via a specified resource" do
      parent   = make_integration_installation(repositories: [@repo], permissions: { "statuses" => :read })
      @subject = make_scoped_integration_installation(parent: parent, repositories: [@repo])

      assert_same_elements [@repo.id], @subject.repository_ids(resource: "statuses")
    end

    test "does not include repos, with access other than the specified resource" do
      parent   = make_integration_installation(repositories: [@repo], permissions: { "statuses" => :read })
      @subject = make_scoped_integration_installation(parent: parent, repositories: [@repo])

      assert_empty @subject.repository_ids(resource: "issues")
    end

    test "returns an empty Array if passed an invalid resource" do
      parent   = make_integration_installation(repositories: [@repo], permissions: { "statuses" => :read })
      @subject = make_scoped_integration_installation(parent: parent, repositories: [@repo])

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

  test "#repository_selection returns 'selected' when installing on selected repos" do
    assert_equal "selected", @subject.repository_selection
  end

  test "#repository_selection returns 'all' when installing on all repos" do
    user = create(:user)
    repo = create(:private_repository, :minimal, owner: user)

    installation = make_integration_installation(
      target: user,
      permissions: { "metadata" => :read, "contents" => :read },
    )

    scoped_installation = make_scoped_integration_installation(
      parent: installation, repositories: :all,
    )

    assert_equal "all", scoped_installation.repository_selection
  end

  test "#target returns the parent's target" do
    assert_equal @installation.target, @subject.target
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
    assert_equal "scoped_integration_installation-#{@subject.id}", @subject.name
  end

  test "#extend_expires_at! updates the expires_at timestamp of the installation and all associated permissions" do
    parent   = make_integration_installation(repositories: [@repo], permissions: { "metadata" => :read, "issues" => :write })
    @subject = make_scoped_integration_installation(parent: parent, repositories: [@repo])

    Timecop.freeze do
      @subject.extend_expires_at!(1.hour.from_now, entry_point: :test_case)

      assert_equal 1.hour.from_now.to_i, @subject.reload.expires_at.to_i
      @subject.abilities.each do |permission|
        assert_equal 1.hour.from_now.to_i, permission.expires_at.to_i
      end
    end
  end

  test "#extend_expires_at! updates the expires_at timestamp of the installation and all associated permissions if the new timestamp is equivalent and skips reporting metrics when metrics and skip flags are disabled" do
    GitHub.flipper[:measure_noop_extending_equivalent_expires_at].disable
    GitHub.flipper[:skip_extending_equivalent_expires_at].disable

    parent   = make_integration_installation(repositories: [@repo], permissions: { "metadata" => :read, "issues" => :write })
    @subject = make_scoped_integration_installation(parent: parent, repositories: [@repo])

    Timecop.freeze do
      entry_point = Permissions::Service::EntryPoint.lookup(:test_case)
      @subject.extend_expires_at!(@subject.expires_at, entry_point: entry_point)
      assert_dogstats_distribution(1, "permissions_service.update_rows_requested")
    end
  end

  test "#extend_expires_at! updates the expires_at timestamp of the installation and all associated permissions if the new timestamp is equivalent when metrics flag is enabled but skip flag is disabled" do
    GitHub.flipper[:measure_noop_extending_equivalent_expires_at].enable
    GitHub.flipper[:skip_extending_equivalent_expires_at].disable

    parent   = make_integration_installation(repositories: [@repo], permissions: { "metadata" => :read, "issues" => :write })
    @subject = make_scoped_integration_installation(parent: parent, repositories: [@repo])

    Timecop.freeze do
      entry_point = Permissions::Service::EntryPoint.lookup(:test_case)
      @subject.extend_expires_at!(@subject.expires_at, entry_point: entry_point)
      assert_dogstats_distribution(1, "permissions_service.update_rows_requested")
    end
  end

  test "#extend_expires_at! skips updating the expires_at timestamp of the installation and all associated permissions if the new timestamp is equivalent when metrics and skip flags are enabled" do
    GitHub.flipper[:measure_noop_extending_equivalent_expires_at].enable
    GitHub.flipper[:skip_extending_equivalent_expires_at].enable

    parent   = make_integration_installation(repositories: [@repo], permissions: { "metadata" => :read, "issues" => :write })
    @subject = make_scoped_integration_installation(parent: parent, repositories: [@repo])

    ::Permissions::Service.expects(:update_expires_at_for_permissions).never

    Timecop.freeze do
      entry_point = Permissions::Service::EntryPoint.lookup(:test_case)
      @subject.extend_expires_at!(@subject.expires_at, entry_point: entry_point)
      assert_dogstats_distribution(0, "permissions_service.update_rows_requested")
    end
  end

  test "#extend_expires_at is synchronous by default" do
    parent   = make_integration_installation(repositories: [@repo], permissions: { "metadata" => :read, "issues" => :write })
    @subject = make_scoped_integration_installation(parent: parent, repositories: [@repo])

    timestamp = 1.hour.from_now
    @subject.expects(:extend_expires_at!).with(timestamp, entry_point: :test_case)

    @subject.extend_expires_at(timestamp, entry_point: :test_case)
  end

  test "#extend_expires_at is asynchronous when the flag is passed" do
    parent   = make_integration_installation(repositories: [@repo], permissions: { "metadata" => :read, "issues" => :write })
    @subject = make_scoped_integration_installation(parent: parent, repositories: [@repo])

    Timecop.freeze do
      timestamp = 1.hour.from_now
      expected_job = ScopedIntegrationInstallableExpirationExtensionJob
      assert_performed_with(job: expected_job, args: [@subject, timestamp, { entry_point: :test_case }]) do
        @subject.extend_expires_at(timestamp, async: true, entry_point: :test_case)

        assert_equal timestamp.to_i, @subject.reload.expires_at.to_i
        @subject.abilities.each do |permission|
          assert_equal timestamp.to_i, permission.expires_at.to_i
        end
      end
    end
  end

  test "it's expired when expires_at is in the past" do
    subject = Timecop.freeze(1.week.ago) do
      parent   = make_integration_installation(repositories: [@repo], permissions: { "metadata" => :read, "issues" => :write })
      make_scoped_integration_installation(parent: parent, repositories: [@repo])
    end

    assert_predicate subject, :expired?
  end

  test "it's expired when expires_at is in the past even with some permissions updated" do
    subject = Timecop.freeze(1.week.ago) do
      parent   = make_integration_installation(repositories: [@repo], permissions: { "metadata" => :read, "issues" => :write })
      make_scoped_integration_installation(parent: parent, repositories: [@repo])
    end

    Permissions::Service.update_expires_at_for_permissions(
      permission_ids: subject.abilities.map(&:id),
      timestamp: Time.current
    )

    assert_predicate subject, :expired?
  end

  test "it's not expired when expires_at is in the future" do
    parent = make_integration_installation(repositories: [@repo], permissions: { "metadata" => :read, "issues" => :write })
    subject = make_scoped_integration_installation(parent: parent, repositories: [@repo])

    refute_predicate subject, :expired?
  end

  test "it's not expired when expires_at is null" do
    parent = make_integration_installation(repositories: [@repo], permissions: { "metadata" => :read, "issues" => :write })
    subject = make_scoped_integration_installation(parent: parent, repositories: [@repo])
    subject.update_attribute(:expires_at, nil)
    assert_nil subject.reload.expires_at
    refute_predicate subject, :expired?
  end

  context "instrumentation" do
    test "#event_context" do
      expected_context = {
        scoped_integration_installation: @subject.name,
        scoped_integration_installation_id: @subject.id,
      }
      assert_equal @subject.event_context, expected_context

      expected_context_with_custom_prefix = {
        foo: @subject.name,
        foo_id: @subject.id,
      }
      assert_equal @subject.event_context(prefix: :foo), expected_context_with_custom_prefix
    end

    test "#extend_expires_at instruments the extension" do
      events = subscribe "scoped_integration_installation.extend_expires_at"

      created_at = 2.hours.ago
      @subject = Timecop.freeze(created_at) do
        parent = make_integration_installation(
          repositories: [@repo], permissions: { "metadata" => :read, "issues" => :write },
        )
        make_scoped_integration_installation(parent: parent, repositories: [@repo])
      end

      Timecop.freeze do
        @subject.extend_expires_at(1.hour.from_now, entry_point: :test_case)

        assert event = events.pop, "expected an instrument extend_expires_at event"
        assert_equal "scoped_integration_installation.extend_expires_at", event.name
        assert_equal 1.hour.from_now.to_i, event.payload[:expires_at]&.to_i
        assert_equal created_at.to_i, event.payload[:created_at].to_i
      end
    end

    test "#extend_expires_at instruments the extension even when the target is missing" do
      events = subscribe "scoped_integration_installation.extend_expires_at"

      created_at = 2.hours.ago
      @subject = Timecop.freeze(created_at) do
        parent = make_integration_installation(
          repositories: [@repo], permissions: { "metadata" => :read, "issues" => :write },
        )
        make_scoped_integration_installation(parent: parent, repositories: [@repo])
      end

      @user.delete
      @subject.reload

      assert_nil @subject.target

      Timecop.freeze do
        @subject.extend_expires_at(1.hour.from_now, entry_point: :test_case)

        assert event = events.pop, "expected an instrument extend_expires_at event"
        assert_equal "scoped_integration_installation.extend_expires_at", event.name
      end
    end
  end

  test "#clear_abilities_per_destroyed_record?" do
    refute_predicate @subject, :clear_abilities_per_destroyed_record?
  end

  context "suspension" do
    context "#integrator_suspended?" do
      test "is only true when integrator_suspended and integrator_suspended_at are both set on the parent" do
        @installation.update(integrator_suspended: true)

        @installation.reload
        @subject.reload

        refute_predicate @installation, :integrator_suspended?
        refute_predicate @subject,      :integrator_suspended?

        @installation.update(integrator_suspended: false, integrator_suspended_at: Time.zone.now)

        @installation.reload
        @subject.reload

        refute_predicate @installation, :integrator_suspended?
        refute_predicate @subject,      :integrator_suspended?

        @installation.update(integrator_suspended: true, integrator_suspended_at: Time.zone.now)

        @installation.reload
        @subject.reload

        assert_predicate @installation, :integrator_suspended?
        assert_predicate @subject,      :integrator_suspended?
      end
    end

    context "#user_suspended?" do
      test "is only true when both user_suspended_by_id and user_suspended_at are set on the parent" do
        @installation.update(user_suspended_by: @user)

        @installation.reload
        @subject.reload

        refute_predicate @installation, :user_suspended?
        refute_predicate @subject,      :user_suspended?

        @installation.update(user_suspended_by: nil, user_suspended_at: Time.zone.now)

        @installation.reload
        @subject.reload

        refute_predicate @installation, :user_suspended?
        refute_predicate @subject,      :user_suspended?

        @installation.update(user_suspended_by: @user, user_suspended_at: Time.zone.now)

        @installation.reload
        @subject.reload

        assert_predicate @installation, :user_suspended?
        assert_predicate @subject,      :user_suspended?
      end
    end

    context "#suspended?" do
      test "is true if the parent is suspended by the integrator" do
        @installation.update(integrator_suspended: true, integrator_suspended_at: Time.zone.now)

        @installation.reload
        @subject.reload

        assert_predicate @installation, :suspended?
        assert_predicate @subject,      :suspended?
      end

      test "is true if the parent is suspended by a User" do
        @installation.update(user_suspended_by: @user, user_suspended_at: Time.zone.now)

        @installation.reload
        @subject.reload

        assert_predicate @installation, :suspended?
        assert_predicate @subject,      :suspended?
      end
    end
  end

  context "dual writing", skip_enterprise: true, skip_in_multitenant_mode: true do
    test "does not write to lodge if the feature flag isn't enabled", feature_disabled: :dual_write_scoped_integration_installations_to_lodge do
      lodge_id = ApplicationRecord::Lodge.connection.select_value(Arel.sql(<<-SQL, id: @subject.id))
        SELECT id FROM scoped_integration_installations
        WHERE id = :id
      SQL

      assert_nil lodge_id
    end

    test "inserted the same record to lodge on create", feature_enabled: :dual_write_scoped_integration_installations_to_lodge do
      rows = ApplicationRecord::Lodge.connection.select_rows(Arel.sql(<<-SQL, id: @subject.id))
        SELECT id,
               integration_installation_id,
               created_at,
               updated_at,
               expires_at,
               authorization_details
        FROM scoped_integration_installations
        WHERE id = :id
      SQL

      assert_equal 1, rows.size
      row = rows.first

      # Remove `authorization_details` from the row and compare as a hash.
      actual_authorization_details = JSON.parse(row.delete_at(-1))

      expected = @subject.attributes_for_database.values_at("id", "integration_installation_id", "created_at", "updated_at", "expires_at")
      assert_same_elements expected, row

      assert_same_hash actual_authorization_details, @subject.authorization_details
    end

    test "updates the record on lodge", feature_enabled: :dual_write_scoped_integration_installations_to_lodge do
      Timecop.travel(2.days) { @subject.touch }; @subject.reload

      rows = ApplicationRecord::Lodge.connection.select_rows(Arel.sql(<<-SQL, id: @subject.id))
        SELECT updated_at
        FROM scoped_integration_installations
        WHERE id = :id
      SQL

      assert_equal 1, rows.size
      assert_same_elements [@subject.attributes_for_database["updated_at"]], rows.first
    end

    test "deletes the record on lodge", feature_enabled: :dual_write_scoped_integration_installations_to_lodge do
      @subject.destroy

      rows = ApplicationRecord::Lodge.connection.select_rows(Arel.sql(<<-SQL, id: @subject.id))
        SELECT id
        FROM scoped_integration_installations
        WHERE id = :id
      SQL

      assert_empty rows
    end

    test "does not delete the record on lodge if the records are out of sync", feature_enabled: :dual_write_scoped_integration_installations_to_lodge do
      @subject.update_column(:updated_at, 2.days.from_now); @subject.reload

      @subject.destroy

      rows = ApplicationRecord::Lodge.connection.select_rows(Arel.sql(<<-SQL, id: @subject.id))
        SELECT id
        FROM scoped_integration_installations
        WHERE id = :id
      SQL

      assert_equal 1, rows.size
      assert_same_elements [@subject.id], rows.first
    end
  end
end
