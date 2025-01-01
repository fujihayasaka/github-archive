# typed: true
# frozen_string_literal: true

require "test_helper"

class ScopedInstallations::AuthorizationDetails::Loaders::PermissionTest < GitHub::TestCase
  fixtures do
    @integration = create(:integration, default_permissions: { "metadata" => :read, "contents" => :write, "members" => :read })
    @global_integration = create_unlimited_global_integration(permissions: { "metadata" => :read, "contents" => :write, "members" => :read })

    @target = create(:organization)
    @repository = create(:repository, :minimal, owner: @target)
  end

  setup do
    GitHub.flipper[:disabled_global_apps].disable
    GitHub.flipper[:scoped_installation_with_authorization_details].enable
    GitHub.flipper[:write_authorization_details_for_site_scoped_integration_installations].enable
  end

  def load_permissions(actor_type, actor_id, subject_type, subject_ids)
    ScopedInstallations::AuthorizationDetails::Loaders::Permission.load(
      actor_type, actor_id, subject_type, subject_ids
    )
  end

  test "returns permissions records if authorization details were not written" do
    ssii = SiteScopedIntegrationInstallation.create!(integration: @integration, target: @target)

    subject = @repository.resources.metadata
    Permissions::Service.grant_app_permission(actor: ssii, subject: subject, action: :read, entry_point: :test_case)

    assert_nil ssii.authorization_details

    expected = [[ssii.ability_id, subject.ability_id, 0]]
    actual = load_permissions(ssii.ability_type, ssii.ability_id, subject.ability_type, [subject.ability_id])

    assert_same_elements(expected, actual)
  end

  context "#load_actor" do
    context "global installations" do
      test "returns nothing if the integration no longer exists" do
        @integration.destroy

        subject = @target.repository_resources.metadata # => User/repositories/metadata
        permissions = load_permissions("GlobalIntegrationInstallation", @integration.id, subject.ability_type, [subject.ability_id])

        assert_empty permissions
      end
    end

    context "scoped installations" do
      test "queries the permissions table if the actor isn't found" do
        ssii = SiteScopedIntegrationInstallation.create!(integration: @integration, target: @target)

        subject = @repository.resources.metadata # => User/repositories/metadata
        Permissions::Service.grant_app_permission(actor: ssii, subject: subject, action: :read, entry_point: :test_case)

        ssii.delete

        subject = @repository.resources.metadata # => User/repositories/metadata
        permissions = load_permissions("ScopedIntegrationInstallation", ssii.ability_id, subject.ability_type, [subject.ability_id])

        expected = [[ssii.ability_id, subject.ability_id, 0]]
        actual = load_permissions(ssii.ability_type, ssii.ability_id, subject.ability_type, [subject.ability_id])

        assert_same_elements(expected, actual)
      end
    end
  end

  context "individual type subject types" do
    context "global installations" do
      test "loads permissions that match the parent integration" do
        subject = @repository.resources.metadata # => User/repositories/metadata
        permissions = load_permissions("GlobalIntegrationInstallation", @integration.id, subject.ability_type, [subject.ability_id])

        assert_same_elements([[@integration.id, subject.ability_id, 0]], permissions)
      end

      test "does not load permissions if none are granted" do
        subject = @repository.resources.administration # => User/repositories/metadata
        permissions = load_permissions("GlobalIntegrationInstallation", @integration.id, subject.ability_type, [subject.ability_id])

        assert_empty permissions
      end
    end

    context "scoped installations" do
      context "parent selection" do
        test "loads permissions if the actor and parent both have access" do
          parent = make_integration_installation(repository: @repository, permissions: { "metadata" => :read, "contents" => :read })

          selection = ScopedIntegrationInstallation::Creator::INSTALL_ON_ALL_SELECTED_REPOSITORIES
          result = ScopedIntegrationInstallation::Creator.perform(parent, repositories: selection, permissions: { "metadata" => :read }, entry_point: :test_case)

          assert_predicate result, :success?

          installation = result.installation
          subject = @repository.resources.metadata # => Repository/metadata

          expected = [[installation.ability_id, subject.ability_id, 0]]
          actual = load_permissions(installation.ability_type, installation.ability_id, subject.ability_type, [subject.ability_id])

          assert_same_elements(expected, actual)
        end

        test "does not return permissions if the parent has access on 'all'" do
          parent = make_integration_installation(target: @target, permissions: { "metadata" => :read, "contents" => :read })

          selection = ScopedIntegrationInstallation::Creator::INSTALL_ON_ALL_REPOSITORIES
          result = ScopedIntegrationInstallation::Creator.perform(parent, repositories: selection, permissions: { "metadata" => :read }, entry_point: :test_case)

          assert_predicate result, :success?

          installation = result.installation
          subject = @repository.resources.metadata # => Repository/metadata

          assert_empty load_permissions(installation.ability_type, installation.ability_id, subject.ability_type, [subject.ability_id])
        end

        test "returns the lesser access if the parent's access has degraded" do
          Timecop.freeze do
            parent = make_integration_installation(repository: @repository, permissions: { "metadata" => :read, "contents" => :write, "issues" => :read })

            selection = ScopedIntegrationInstallation::Creator::INSTALL_ON_ALL_SELECTED_REPOSITORIES
            result = ScopedIntegrationInstallation::Creator.perform(parent, repositories: selection, permissions: { "metadata" => :read, "contents" => :write }, entry_point: :test_case)

            assert_predicate result, :success?

            installation = result.installation
            AuthenticationToken.create_for(installation) # make a token so it's 'active'.

            parent.integration.update(default_permissions: { "metadata" => :read, "contents" => :read })
            parent.integration.reload

            perform_enqueued_jobs(only: [SyncScopedIntegrationInstallationsJob]) do
              parent.update_version(editor: @target.admins.first, version: parent.integration.latest_version, entry_point: :test_case)
            end

            subject = @repository.resources.contents # => Repository/contents

            expected = [[installation.ability_id, subject.ability_id, 0]]
            actual = load_permissions(installation.ability_type, installation.ability_id, subject.ability_type, [subject.ability_id])

            assert_same_elements(expected, actual)
          end
        end

        test "does not upgrade the access if the parent's access has been elevated" do
          parent = make_integration_installation(repository: @repository, permissions: { "metadata" => :read, "contents" => :read })

          selection = ScopedIntegrationInstallation::Creator::INSTALL_ON_ALL_SELECTED_REPOSITORIES
          result = ScopedIntegrationInstallation::Creator.perform(parent, repositories: selection, permissions: { "metadata" => :read, "contents" => :read }, entry_point: :test_case)

          assert_predicate result, :success?

          installation = result.installation

          parent.integration.update(default_permissions: { "metadata" => :read, "contents" => :write })
          parent.integration.reload

          parent.update_version(editor: @target.admins.first, version: parent.integration.latest_version, entry_point: :test_case)

          subject = @repository.resources.contents # => Repository/contents

          expected = [[installation.ability_id, subject.ability_id, 0]]
          actual = load_permissions(installation.ability_type, installation.ability_id, subject.ability_type, [subject.ability_id])

          assert_same_elements(expected, actual)
        end

        test "returns nothing if the parent has no longer has the permission" do
          Timecop.freeze do
            parent = make_integration_installation(repository: @repository, permissions: { "metadata" => :read, "contents" => :write, "issues" => :read })

            selection = ScopedIntegrationInstallation::Creator::INSTALL_ON_ALL_SELECTED_REPOSITORIES
            result = ScopedIntegrationInstallation::Creator.perform(parent, repositories: selection, permissions: { "metadata" => :read, "contents" => :write }, entry_point: :test_case)

            assert_predicate result, :success?

            installation = result.installation
            AuthenticationToken.create_for(installation) # make a token so it's 'active'.

            parent.integration.update(default_permissions: { "metadata" => :read })
            parent.integration.reload

            perform_enqueued_jobs(only: [SyncScopedIntegrationInstallationsJob]) do
              parent.update_version(editor: @target.admins.first, version: parent.integration.latest_version, entry_point: :test_case)
            end

            subject = @repository.resources.contents # => Repository/contents
            assert_empty load_permissions(installation.ability_type, installation.ability_id, subject.ability_type, [subject.ability_id])
          end
        end
      end

      context "subset selection" do
        test "loads permissions if the actor and parent both have access" do
          parent = make_integration_installation(repository: @repository, permissions: { "metadata" => :read, "contents" => :read })
          result = ScopedIntegrationInstallation::Creator.perform(parent, repositories: [@repository], permissions: { "metadata" => :read }, entry_point: :test_case)

          assert_predicate result, :success?

          installation = result.installation
          subject = @repository.resources.metadata # => Repository/metadata

          expected = [[installation.ability_id, subject.ability_id, 0]]
          actual = load_permissions(installation.ability_type, installation.ability_id, subject.ability_type, [subject.ability_id])

          assert_same_elements(expected, actual)
        end

        test "returns permissions if the parent has access on 'all'" do
          parent = make_integration_installation(target: @target, permissions: { "metadata" => :read, "contents" => :read })
          result = ScopedIntegrationInstallation::Creator.perform(parent, repositories: [@repository], permissions: { "metadata" => :read }, entry_point: :test_case)

          assert_predicate result, :success?

          installation = result.installation
          subject = @repository.resources.metadata # => Repository/metadata

          expected = [[installation.ability_id, subject.ability_id, 0]]
          actual = load_permissions(installation.ability_type, installation.ability_id, subject.ability_type, [subject.ability_id])

          assert_same_elements(expected, actual)
        end

        test "does not return permissions if the target does not own the repository" do
          parent = make_integration_installation(target: @target, permissions: { "metadata" => :read, "contents" => :read })
          result = ScopedIntegrationInstallation::Creator.perform(parent, repositories: [@repository], permissions: { "metadata" => :read }, entry_point: :test_case)

          assert_predicate result, :success?

          installation = result.installation

          rando_repository = create(:repository, :minimal)
          subject = rando_repository.resources.metadata # => Repository/metadata

          assert_empty load_permissions(installation.ability_type, installation.ability_id, subject.ability_type, [subject.ability_id])
        end

        test "returns the lesser access if the parent's access on 'all' has degraded" do
          Timecop.freeze do
            parent = make_integration_installation(target: @target, permissions: { "metadata" => :read, "contents" => :write, "issues" => :read })
            result = ScopedIntegrationInstallation::Creator.perform(parent, repositories: [@repository], permissions: { "metadata" => :read, "contents" => :write }, entry_point: :test_case)

            assert_predicate result, :success?

            installation = result.installation
            AuthenticationToken.create_for(installation) # make a token so it's 'active'.

            parent.integration.update(default_permissions: { "metadata" => :read, "contents" => :read })
            parent.integration.reload

            perform_enqueued_jobs(only: [SyncScopedIntegrationInstallationsJob]) do
              parent.update_version(editor: @target.admins.first, version: parent.integration.latest_version, entry_point: :test_case)
            end

            subject = @repository.resources.contents # => Repository/contents

            expected = [[installation.ability_id, subject.ability_id, 0]]
            actual = load_permissions(installation.ability_type, installation.ability_id, subject.ability_type, [subject.ability_id])

            assert_same_elements(expected, actual)
          end
        end

        test "returns the lesser access if the parent's access has degraded" do
          Timecop.freeze do
            parent = make_integration_installation(repository: @repository, permissions: { "metadata" => :read, "contents" => :write, "issues" => :read })
            result = ScopedIntegrationInstallation::Creator.perform(parent, repositories: [@repository], permissions: { "metadata" => :read, "contents" => :write }, entry_point: :test_case)

            assert_predicate result, :success?

            installation = result.installation
            AuthenticationToken.create_for(installation) # make a token so it's 'active'.

            parent.integration.update(default_permissions: { "metadata" => :read, "contents" => :read })
            parent.integration.reload

            perform_enqueued_jobs(only: [SyncScopedIntegrationInstallationsJob]) do
              parent.update_version(editor: @target.admins.first, version: parent.integration.latest_version, entry_point: :test_case)
            end

            subject = @repository.resources.contents # => Repository/contents

            expected = [[installation.ability_id, subject.ability_id, 0]]
            actual = load_permissions(installation.ability_type, installation.ability_id, subject.ability_type, [subject.ability_id])

            assert_same_elements(expected, actual)
          end
        end

        test "does not upgrade the access if the parent's access has been elevated" do
          parent = make_integration_installation(repository: @repository, permissions: { "metadata" => :read, "contents" => :read })
          result = ScopedIntegrationInstallation::Creator.perform(parent, repositories: [@repository], permissions: { "metadata" => :read, "contents" => :read }, entry_point: :test_case)

          assert_predicate result, :success?

          installation = result.installation

          parent.integration.update(default_permissions: { "metadata" => :read, "contents" => :write })
          parent.integration.reload

          parent.update_version(editor: @target.admins.first, version: parent.integration.latest_version, entry_point: :test_case)

          subject = @repository.resources.contents # => Repository/contents

          expected = [[installation.ability_id, subject.ability_id, 0]]
          actual = load_permissions(installation.ability_type, installation.ability_id, subject.ability_type, [subject.ability_id])

          assert_same_elements(expected, actual)
        end

        test "returns nothing if the parent has no longer has the permission" do
          Timecop.freeze do
            parent = make_integration_installation(repository: @repository, permissions: { "metadata" => :read, "contents" => :write, "issues" => :read })
            result = ScopedIntegrationInstallation::Creator.perform(parent, repositories: [@repository], permissions: { "metadata" => :read, "contents" => :write }, entry_point: :test_case)

            assert_predicate result, :success?

            installation = result.installation
            AuthenticationToken.create_for(installation) # make a token so it's 'active'.

            parent.integration.update(default_permissions: { "metadata" => :read })
            parent.integration.reload

            perform_enqueued_jobs(only: [SyncScopedIntegrationInstallationsJob]) do
              parent.update_version(editor: @target.admins.first, version: parent.integration.latest_version, entry_point: :test_case)
            end

            subject = @repository.resources.contents # => Repository/contents
            assert_empty load_permissions(installation.ability_type, installation.ability_id, subject.ability_type, [subject.ability_id])
          end
        end
      end
    end

    context "site scoped installations" do
      test "loads the permissions granted to the installation" do
        result = SiteScopedIntegrationInstallation::Creator.perform(@global_integration, @target, repositories: [@repository], permissions: { "metadata" => :read }, entry_point: :test_case)
        assert_predicate result, :success?

        installation = result.installation
        subject = @repository.resources.metadata # => Repository/metadata

        expected = [[installation.ability_id, subject.ability_id, 0]]
        actual = load_permissions(installation.ability_type, installation.ability_id, subject.ability_type, [subject.ability_id])

        assert_same_elements(expected, actual)
      end

      test "does not load permissions if the installation has access on 'all'" do
        result = SiteScopedIntegrationInstallation::Creator.perform(@global_integration, @target, repositories: :all, permissions: { "metadata" => :read }, entry_point: :test_case)
        assert_predicate result, :success?

        installation = result.installation
        subject = @repository.resources.metadata # => Repository/metadata

        assert_empty load_permissions(installation.ability_type, installation.ability_id, subject.ability_type, [subject.ability_id])
      end
    end
  end

  context "all type subject types" do
    context "GlobalIntegrationInstallation" do
      test "loads permissions that match the parent integration" do
        subject = @target.repository_resources.metadata # => User/repositories/metadata
        permissions = load_permissions("GlobalIntegrationInstallation", @integration.id, subject.ability_type, [subject.ability_id])

        assert_same_elements([[@integration.id, subject.ability_id, 0]], permissions)
      end

      test "does not load permissions if none are granted" do
        subject = @target.repository_resources.administration # => User/repositories/metadata
        permissions = load_permissions("GlobalIntegrationInstallation", @integration.id, subject.ability_type, [subject.ability_id])

        assert_empty permissions
      end
    end

    context "scoped installations" do
      context "parent selection" do
        test "loads permissions if the actor and parent both have access" do
          parent = make_integration_installation(target: @target, permissions: { "metadata" => :read, "contents" => :read })
          result = ScopedIntegrationInstallation::Creator.perform(parent, repositories: :all, permissions: { "metadata" => :read }, entry_point: :test_case)

          assert_predicate result, :success?

          installation = result.installation
          subject = @target.repository_resources.metadata # => User/repositories/metadata

          expected = [[installation.ability_id, subject.ability_id, 0]]
          actual = load_permissions(installation.ability_type, installation.ability_id, subject.ability_type, [subject.ability_id])

          assert_same_elements(expected, actual)
        end

        test "does not return permissions if the parent has access on 'subset'" do
          parent = make_integration_installation(repository: @repository, permissions: { "metadata" => :read, "contents" => :read })
          result = ScopedIntegrationInstallation::Creator.perform(parent, repositories: :selected, permissions: { "metadata" => :read }, entry_point: :test_case)

          assert_predicate result, :success?

          installation = result.installation
          subject = @target.repository_resources.metadata # => User/repositories/metadata

          assert_empty load_permissions(installation.ability_type, installation.ability_id, subject.ability_type, [subject.ability_id])
        end

        test "returns the lesser access if the parent's access has degraded" do
          Timecop.freeze do
            parent = make_integration_installation(target: @target, permissions: { "metadata" => :read, "contents" => :write, "issues" => :read })
            result = ScopedIntegrationInstallation::Creator.perform(parent, repositories: :all, permissions: { "metadata" => :read, "contents" => :write }, entry_point: :test_case)

            assert_predicate result, :success?

            installation = result.installation
            AuthenticationToken.create_for(installation) # make a token so it's 'active'.

            parent.integration.update(default_permissions: { "metadata" => :read, "contents" => :read })
            parent.integration.reload

            perform_enqueued_jobs(only: [SyncScopedIntegrationInstallationsJob]) do
              parent.update_version(editor: @target.admins.first, version: parent.integration.latest_version, entry_point: :test_case)
            end

            subject = @target.repository_resources.contents # => Repository/contents

            expected = [[installation.ability_id, subject.ability_id, 0]]
            actual = load_permissions(installation.ability_type, installation.ability_id, subject.ability_type, [subject.ability_id])

            assert_same_elements(expected, actual)
          end
        end

        test "does not upgrade the access if the parent's access has been elevated" do
          parent = make_integration_installation(target: @target, permissions: { "metadata" => :read, "contents" => :read })
          result = ScopedIntegrationInstallation::Creator.perform(parent, repositories: :all, permissions: { "metadata" => :read, "contents" => :read }, entry_point: :test_case)

          assert_predicate result, :success?

          installation = result.installation

          parent.integration.update(default_permissions: { "metadata" => :read, "contents" => :write })
          parent.integration.reload

          parent.update_version(editor: @target.admins.first, version: parent.integration.latest_version, entry_point: :test_case)

          subject = @target.repository_resources.contents # => User/repositories/contents

          expected = [[installation.ability_id, subject.ability_id, 0]]
          actual = load_permissions(installation.ability_type, installation.ability_id, subject.ability_type, [subject.ability_id])

          assert_same_elements(expected, actual)
        end

        test "returns nothing if the parent has no longer has the permission" do
          Timecop.freeze do
            parent = make_integration_installation(target: @target, permissions: { "metadata" => :read, "contents" => :write, "issues" => :read })
            result = ScopedIntegrationInstallation::Creator.perform(parent, repositories: :all, permissions: { "metadata" => :read, "contents" => :write }, entry_point: :test_case)

            assert_predicate result, :success?

            installation = result.installation
            AuthenticationToken.create_for(installation) # make a token so it's 'active'.

            parent.integration.update(default_permissions: { "metadata" => :read })
            parent.integration.reload

            perform_enqueued_jobs(only: [SyncScopedIntegrationInstallationsJob]) do
              parent.update_version(editor: @target.admins.first, version: parent.integration.latest_version, entry_point: :test_case)
            end

            subject = @target.repository_resources.contents # => User/repositories/contents
            assert_empty load_permissions(installation.ability_type, installation.ability_id, subject.ability_type, [subject.ability_id])
          end
        end
      end

      context "subset selection" do
        test "does not load permissions" do
          parent = make_integration_installation(repository: @repository, permissions: { "metadata" => :read, "contents" => :read })
          result = ScopedIntegrationInstallation::Creator.perform(parent, repositories: [@repository], permissions: { "metadata" => :read }, entry_point: :test_case)

          assert_predicate result, :success?

          installation = result.installation
          subject = @target.repository_resources.metadata # => User/repositories/metadata

          assert_empty load_permissions(installation.ability_type, installation.ability_id, subject.ability_type, [subject.ability_id])
        end
      end
    end
  end

  context "site scoped installations" do
    test "loads the permissions granted to the installation" do
      result = SiteScopedIntegrationInstallation::Creator.perform(@global_integration, @target, repositories: :all, permissions: { "metadata" => :read }, entry_point: :test_case)
      assert_predicate result, :success?

      installation = result.installation
      subject = @target.repository_resources.metadata # => User/repositories/metadata

      expected = [[installation.ability_id, subject.ability_id, 0]]
      actual = load_permissions(installation.ability_type, installation.ability_id, subject.ability_type, [subject.ability_id])

      assert_same_elements(expected, actual)
    end

    test "does not load permissions if the targets don't match" do
      result = SiteScopedIntegrationInstallation::Creator.perform(@global_integration, @target, repositories: :all, permissions: { "metadata" => :read }, entry_point: :test_case)
      assert_predicate result, :success?

      installation = result.installation

      random_target = create(:organization)
      subject = random_target.repository_resources.metadata # => User/repositories/metadata

      assert_empty load_permissions(installation.ability_type, installation.ability_id, subject.ability_type, [subject.ability_id])
    end

    test "does not load permissions if the installation has access on 'subset'" do
      result = SiteScopedIntegrationInstallation::Creator.perform(@global_integration, @target, repositories: [@repository], permissions: { "metadata" => :read }, entry_point: :test_case)
      assert_predicate result, :success?

      installation = result.installation
      subject = @target.repository_resources.metadata # => User/repositories/metadata

      assert_empty load_permissions(installation.ability_type, installation.ability_id, subject.ability_type, [subject.ability_id])
    end

    test "does not load permissions if the installation does not have access" do
      result = SiteScopedIntegrationInstallation::Creator.perform(@global_integration, @target, repositories: :all, permissions: { "metadata" => :read }, entry_point: :test_case)
      assert_predicate result, :success?

      installation = result.installation
      subject = @target.repository_resources.contents # => User/repositories/metadata

      assert_empty load_permissions(installation.ability_type, installation.ability_id, subject.ability_type, [subject.ability_id])
    end
  end
end
