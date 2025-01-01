# typed: true
# frozen_string_literal: true

require "test_helper"

module Codespaces
  class WriteAllowedPermissionsTest < GitHub::TestCase
    fixtures do
      GitHub.flipper[:codespaces_prebuilds_show_permissions_granted].disable
      GitHub.flipper[:codespaces_prebuild_admin_repo_access].disable
      @user = create(:user)
      @user2 = create(:user)
      @org = create(:team_org)
      @org.add_member(@user)
      @org.add_member(@user2)
      @repo = create(:private_repository, owner: @user, from_example: :simple)
    end

    test "it properly saves permission rows during codespace creation proxima" do
      on_multi_tenant_enterprise do
        emu = create(:emu)
        business = emu.enterprise_managed_business
        GitHub::CurrentTenant.set(business)

        org = create(:organization, admins: [emu])
        repo = create(:repository, owner: org, from_example: :simple)

        existing = Codespaces::AllowedPermission.new(user: emu, repository: repo, target_id: repo.id, target_type: "Repository", resource: "contents", action: "read")
        existing.save!

        existing_updated_at = existing.updated_at

        dc_contents = %{
          {
            "codespaces": {
              "repositories": [
                {
                  "name": "#{repo.name_with_display_owner}",
                  "permissions": {
                    "contents": "read", // existing permission should not be overwritten
                    "notreal": "read",
                    "issues": "read"
                  }
                },
                {
                  "name": "#{repo.owner.display_login}/*",
                  "permissions": {
                    "contents": "write"
                  }
                },
              ]
            }
          }
        }

        repo.refs.find("master").append_commit({ message: "add devcontainer json file", committer: repo.owner }, repo.owner) do |files|
          files.add(".devcontainer/devcontainer.json", dc_contents)
        end

        events = subscribe "codespaces.allow_permissions"

        Codespaces::WriteAllowedPermissions.new(
          user: emu,
          repository: repo,
          ref: "master",
          repository_permissions: { "#{repo.name_with_display_owner}" => { "contents" => "read", "issues" => "read", "metadata" => "read" } }, # metadata:read is mandatory and added by default
          owner_permissions: { "#{repo.owner.display_login}" => { "contents" => "write", "metadata" => "read" } }                # during devcontainer permission validation
        ).perform

        assert Codespaces::AllowedPermission.where(repository_id: repo.id, target_type: :repository, resource: "contents", action: "read").exists?
        assert Codespaces::AllowedPermission.where(repository_id: repo.id, target_type: :repository, resource: "issues", action: "read").exists?
        assert Codespaces::AllowedPermission.where(repository_id: repo.id, target_type: :user, resource: "contents", action: "write").exists?

        # mandatory permissions
        assert Codespaces::AllowedPermission.where(repository_id: repo.id, target_type: :repository, resource: "metadata", action: "read").exists?
        assert Codespaces::AllowedPermission.where(repository_id: repo.id, target_type: :user, resource: "metadata", action: "read").exists?

        # the original permission record should not be deleted
        existing.reload

        requested_permissions = {}
        requested_permissions[repo.name_with_display_owner] = { "contents" => "read", "issues" => "read", "metadata" => "read" }
        requested_permissions[repo.owner.display_login] = { "contents" => "write", "metadata" => "read" }

        expected_payload = { origin_repository: repo.name_with_display_owner, requested_permissions: requested_permissions, revoked_permissions: {} }
        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end
    end

    test "it properly saves permission rows during codespace creation" do
      existing = Codespaces::AllowedPermission.new(user: @user, repository: @repo, target_id: @repo.id, target_type: "Repository", resource: "contents", action: "read")
      existing.save!

      existing_updated_at = existing.updated_at

      dc_contents = %{
        {
          "codespaces": {
            "repositories": [
              {
                "name": "#{@repo.nwo}",
                "permissions": {
                  "contents": "read", // existing permission should not be overwritten
                  "notreal": "read",
                  "issues": "read"
                }
              },
              {
                "name": "#{@repo.owner.login}/*",
                "permissions": {
                  "contents": "write"
                }
              },
            ]
          }
        }
      }

      @repo.refs.find("master").append_commit({ message: "add devcontainer json file", committer: @repo.owner }, @repo.owner) do |files|
        files.add(".devcontainer/devcontainer.json", dc_contents)
      end

      events = subscribe "codespaces.allow_permissions"

      Codespaces::WriteAllowedPermissions.new(
        user: @user,
        repository: @repo,
        ref: "master",
        repository_permissions: { "#{@repo.nwo}" => { "contents" => "read", "issues" => "read", "metadata" => "read" } }, # metadata:read is mandatory and added by default
        owner_permissions: { "#{@repo.owner.login}" => { "contents" => "write", "metadata" => "read" } }                # during devcontainer permission validation
      ).perform

      assert Codespaces::AllowedPermission.where(repository_id: @repo.id, target_type: :repository, resource: "contents", action: "read").exists?
      assert Codespaces::AllowedPermission.where(repository_id: @repo.id, target_type: :repository, resource: "issues", action: "read").exists?
      assert Codespaces::AllowedPermission.where(repository_id: @repo.id, target_type: :user, resource: "contents", action: "write").exists?

      # mandatory permissions
      assert Codespaces::AllowedPermission.where(repository_id: @repo.id, target_type: :repository, resource: "metadata", action: "read").exists?
      assert Codespaces::AllowedPermission.where(repository_id: @repo.id, target_type: :user, resource: "metadata", action: "read").exists?

      # the original permission record should not be deleted
      existing.reload

      requested_permissions = {}
      requested_permissions[@repo.nwo] = { "contents" => "read", "issues" => "read", "metadata" => "read" }
      requested_permissions[@repo.owner.login] = { "contents" => "write", "metadata" => "read" }

      expected_payload = { origin_repository: @repo.nwo, requested_permissions: requested_permissions, revoked_permissions: {} }
      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "it properly removes permission rows during codespace creation if they are no longer requested by devcontainer.json" do
      existing = Codespaces::AllowedPermission.new(user: @user, repository: @repo, target_id: @repo.id, target_type: "Repository", resource: "contents", action: "read")
      existing.save!

      existing_updated_at = existing.updated_at

      dc_contents = %{
        {
          "codespaces": {
            "repositories": [
              {
                "name": "#{@repo.nwo}",
                "permissions": {
                  "notreal": "read",
                  "issues": "read" // this should be the only permission for this repo at the end
                }
              },
              {
                "name": "#{@repo.owner.login}/*",
                "permissions": {
                  "contents": "write",
                  "workflows": "write"
                }
              },
            ]
          }
        }
      }

      @repo.refs.find("master").append_commit({ message: "add devcontainer json file", committer: @repo.owner }, @repo.owner) do |files|
        files.add(".devcontainer/devcontainer.json", dc_contents)
      end

      assert Codespaces::AllowedPermission.where(repository_id: @repo.id, target_type: :repository, resource: "contents", action: "read").exists?

      Codespaces::WriteAllowedPermissions.new(
        user: @user,
        repository: @repo,
        ref: "master",
        repository_permissions: { "#{@repo.nwo}" => { "issues" => "read", "metadata" => "read" } },       # metadata:read is mandatory and added by default
        owner_permissions: { "#{@repo.owner.login}" => { "contents" => "write", "workflows" => "write", "metadata" => "read" } } # workflows:write should not be overridden
      ).perform

      refute Codespaces::AllowedPermission.where(repository_id: @repo.id, target_type: :repository, resource: "contents", action: "read").exists?
      assert Codespaces::AllowedPermission.where(repository_id: @repo.id, target_type: :repository, resource: "issues", action: "read").exists?
      assert Codespaces::AllowedPermission.where(repository_id: @repo.id, target_type: :repository, resource: "metadata", action: "read").exists?
      assert Codespaces::AllowedPermission.where(repository_id: @repo.id, target_type: :user, resource: "contents", action: "write").exists?
      assert Codespaces::AllowedPermission.where(repository_id: @repo.id, target_type: :user, resource: "workflows", action: "write").exists?

      assert_raises ActiveRecord::RecordNotFound do
        existing.reload
      end
    end

    test "it removes all existing permission rows and does not write any new ones if user opted out of authorizing" do
      existing = Codespaces::AllowedPermission.new(user: @user, repository: @repo, target_id: @repo.id, target_type: "Repository", resource: "contents", action: "read")
      existing.save!

      existing_updated_at = existing.updated_at

      dc_contents = %{
        {
          "codespaces": {
            "repositories": [
              {
                "name": "#{@repo.nwo}",
                "permissions": {
                  "contents": "read"
                }
              },
              {
                "name": "#{@repo.owner.login}/*",
                "permissions": {
                  "contents": "write"
                }
              },
            ]
          }
        }
      }

      @repo.refs.find("master").append_commit({ message: "add devcontainer json file", committer: @repo.owner }, @repo.owner) do |files|
        files.add(".devcontainer/devcontainer.json", dc_contents)
      end

      assert Codespaces::AllowedPermission.where(repository_id: @repo.id, target_type: :repository, resource: "contents", action: "read").exists?

      Codespaces::AllowedPermission.any_instance.expects(:insert_all!).never

      Codespaces::WriteAllowedPermissions.new(
        user: @user,
        repository: @repo,
        ref: "master",
        opt_out: true,
        repository_permissions: { "#{@repo.nwo}" => { "issues" => "read" } },
        owner_permissions: { "#{@repo.owner.login}" => { "contents" => "write" } }
      ).perform

      refute Codespaces::AllowedPermission.where(repository_id: @repo.id, target_type: :repository, resource: "contents", action: "read").exists?
      refute Codespaces::AllowedPermission.where(repository_id: @repo.id, target_type: :user, resource: "contents", action: "write").exists?

      assert_raises ActiveRecord::RecordNotFound do
        existing.reload
      end
    end

    test "it does not save unknown repos to the DB" do
      user = create(:user)
      repo = create(:repository, owner: @org, from_example: :simple)
      repo.add_member(user)

      private_unowned_repo = create(:private_repository, owner: @org, from_example: :simple)

      dc_contents = %{
        {
          "codespaces": {
            "repositories": [
              {
                "name": "#{repo.nwo}",
                "permissions": {
                  "contents": "read",
                }
              },
              {
                "name": "#{private_unowned_repo.nwo}",
                "permissions": {
                  "contents": "read",
                  "notreal": "read"
                }
              },
              {
                "name": "#{repo.owner.login}/*",
                "permissions": {
                  "contents": "write"
                }
              },
            ]
          }
        }
      }

      repo.refs.find("master").append_commit({ message: "add devcontainer json file", committer: repo.owner }, repo.owner) do |files|
        files.add(".devcontainer/devcontainer.json", dc_contents)
      end

      Codespaces::WriteAllowedPermissions.new(
        user: user,
        repository: repo,
        ref: "master",
        repository_permissions: { "#{repo.nwo}" => { "contents" => "read", "metadata" => "read" } },
        owner_permissions: { "#{repo.owner.login}" => { "contents" => "write", "metadata" => "read" } }
      ).perform

      assert Codespaces::AllowedPermission.where(target_id: repo.id, target_type: :repository, resource: "contents", action: "read").exists?
      refute Codespaces::AllowedPermission.where(target_id: private_unowned_repo.id, target_type: :repository, resource: "contents", action: "write").exists?
    end

    test "it returns error if there is a diff between permissions params and actual permissions" do
      dc_contents = %{
        {
          "codespaces": {
            "repositories": [
              {
                "name": "#{@repo.nwo}",
                "permissions": {
                  "contents": "read", // existing permission should not be overwritten
                  "notreal": "read",
                  "issues": "read"
                }
              },
              {
                "name": "#{@repo.owner.login}/*",
                "permissions": {
                  "contents": "write"
                }
              },
            ]
          }
        }
      }

      @repo.refs.find("master").append_commit({ message: "add devcontainer json file", committer: @repo.owner }, @repo.owner) do |files|
        files.add(".devcontainer/devcontainer.json", dc_contents)
      end

      expected_error = %Q(The permissions in the devcontainer.json file do not match the requested permissions.)

      assert_raises_with_message(Codespaces::WriteAllowedPermissions::PermissionDifferenceError, expected_error) do
        Codespaces::WriteAllowedPermissions.new(
          user: @user,
          repository: @repo,
          ref: "master",
          repository_permissions: {
            "#{@repo.nwo}" => { "contents" => "read", "issues" => "read", "packages" => "read" },
          },
          owner_permissions: { "#{@repo.owner.login}" => { "contents" => "write" } }
        ).perform
      end

      refute Codespaces::AllowedPermission.where(target_id: @repo.id, target_type: :repository, resource: "contents", action: "read").exists?
    end

    test "works with a commit SHA as the ref" do
      dc_contents = %{
        {
          "codespaces": {
            "repositories": [
              {
                "name": "#{@repo.nwo}",
                "permissions": {
                  "contents": "read",
                }
              },
            ]
          }
        }
      }

      commit = @repo.refs.find("master").append_commit({ message: "add devcontainer json file", committer: @repo.owner }, @repo.owner) do |files|
        files.add(".devcontainer/devcontainer.json", dc_contents)
      end

      Codespaces::WriteAllowedPermissions.new(
        user: @user,
        repository: @repo,
        ref: commit.oid,
        repository_permissions: {
          "#{@repo.nwo}" => { "contents" => "read", "metadata" => "read" },
        },
        owner_permissions: {}
      ).perform
      assert Codespaces::AllowedPermission.where(target_id: @repo.id, target_type: :repository, resource: "contents", action: "read").exists?
    end

    test "defaults to default branch when ref is empty string" do
      dc_contents = %{
        {
          "codespaces": {
            "repositories": [
              {
                "name": "#{@repo.nwo}",
                "permissions": {
                  "contents": "read",
                }
              },
            ]
          }
        }
      }

      @repo.refs.find("master").append_commit({ message: "add devcontainer json file", committer: @repo.owner }, @repo.owner) do |files|
        files.add(".devcontainer/devcontainer.json", dc_contents)
      end

      Codespaces::WriteAllowedPermissions.new(
        user: @user,
        repository: @repo,
        ref: "",
        repository_permissions: {
          "#{@repo.nwo}" => { "contents" => "read", "metadata" => "read" },
        },
        owner_permissions: {}
      ).perform
      assert Codespaces::AllowedPermission.where(target_id: @repo.id, target_type: :repository, resource: "contents", action: "read").exists?
    end

    test "it does not return error if there is a diff between permissions params and actual permissions if there are no unconsented" do
      existing_perm = create(:allowed_permission, repository: @repo, target: @repo, user: @user, resource: "contents", action: "read")
      create(:allowed_permission, repository: @repo, target: @repo, user: @user, resource: "metadata", action: "read")

      dc_contents = %{
        {
          "codespaces": {
            "repositories": [
              {
                "name": "#{@repo.nwo}",
                "permissions": {
                  "contents": "read", // existing permission should not be overwritten
                }
              },
            ]
          }
        }
      }

      @repo.refs.find("master").append_commit({ message: "add devcontainer json file", committer: @repo.owner }, @repo.owner) do |files|
        files.add(".devcontainer/devcontainer.json", dc_contents)
      end

      Codespaces::WriteAllowedPermissions.new(
        user: @user,
        repository: @repo,
        ref: "master",
        repository_permissions: {},
        owner_permissions: {}
      ).perform

      assert existing_perm.reload.persisted?
      assert Codespaces::AllowedPermission.where(target_id: @repo.id, target_type: :repository, resource: "contents", action: "read").size == 1
    end

    test "it saves is_prebuild property when it is supplied" do

      dc_contents = %{
        {
          "codespaces": {
            "repositories": [
              {
                "name": "#{@repo.nwo}",
                "permissions": {
                  "contents": "read"
                }
              },
            ]
          }
        }
      }

      @repo.refs.find("master").append_commit({ message: "add devcontainer json file", committer: @repo.owner }, @repo.owner) do |files|
        files.add(".devcontainer/devcontainer.json", dc_contents)
      end

      Codespaces::WriteAllowedPermissions.call(
        user: @user,
        repository: @repo,
        ref: "master",
        repository_permissions: {
          "#{@repo.nwo}" => { "contents" => "read", "metadata" => "read" },
        },
        owner_permissions: {},
        is_prebuild: true,
      )
      assert Codespaces::AllowedPermission.where(target_id: @repo.id, target_type: :repository, resource: "contents", action: "read", is_prebuild: true).exists?

    end

    test "it default is_prebuild property to false when not supplied" do

      dc_contents = %{
        {
          "codespaces": {
            "repositories": [
              {
                "name": "#{@repo.nwo}",
                "permissions": {
                  "contents": "read"
                }
              },
            ]
          }
        }
      }

      @repo.refs.find("master").append_commit({ message: "add devcontainer json file", committer: @repo.owner }, @repo.owner) do |files|
        files.add(".devcontainer/devcontainer.json", dc_contents)
      end

      Codespaces::WriteAllowedPermissions.new(
        user: @user,
        repository: @repo,
        ref: "master",
        repository_permissions: {
          "#{@repo.nwo}" => { "contents" => "read", "metadata" => "read" },
        },
        owner_permissions: {}
      ).perform

      assert Codespaces::AllowedPermission.where(target_id: @repo.id, target_type: :repository, resource: "contents", action: "read", is_prebuild: false).exists?

    end

    test "it saves codespace_prebuild_configuration_id property when it is supplied" do
      dc_contents = %{
        {
          "codespaces": {
            "repositories": [
              {
                "name": "#{@repo.nwo}",
                "permissions": {
                  "contents": "read"
                }
              },
            ]
          }
        }
      }

      @repo.refs.find("master").append_commit({ message: "add devcontainer json file", committer: @repo.owner }, @repo.owner) do |files|
        files.add(".devcontainer/devcontainer.json", dc_contents)
      end

      Codespaces::WriteAllowedPermissions.call(
        user: @user,
        repository: @repo,
        ref: "master",
        repository_permissions: {
          "#{@repo.nwo}" => { "contents" => "read", "metadata" => "read" },
        },
        owner_permissions: {},
        is_prebuild: true,
        prebuild_configuration_id: 99,
      )
      assert Codespaces::AllowedPermission.where(target_id: @repo.id, target_type: :repository,
        resource: "contents", action: "read", is_prebuild: true, codespace_prebuild_configuration_id: 99).exists?

    end

    test "it defaults codespace_prebuild_configuration_id property to nil when not supplied" do
      Codespaces::WriteAllowedPermissions.new(
        user: @user,
        repository: @repo,
        ref: "master",
        repository_permissions: {
          "#{@repo.nwo}" => { "contents" => "read", "metadata" => "read" },
        },
        owner_permissions: {}
      ).perform

      assert Codespaces::AllowedPermission.where(target_id: @repo.id, target_type: :repository,
        resource: "contents", action: "read", is_prebuild: false, codespace_prebuild_configuration_id: nil).exists?

    end

    test "it downgrades write permissions to read if provided for prebuild" do
      dc_contents = %{
        {
          "codespaces": {
            "repositories": [
              {
                "name": "#{@repo.nwo}",
                "permissions": {
                  "contents": "write"
                }
              },
            ]
          }
        }
      }

      @repo.refs.find("master").append_commit({ message: "add devcontainer json file", committer: @repo.owner }, @repo.owner) do |files|
        files.add(".devcontainer/devcontainer.json", dc_contents)
      end

      Codespaces::WriteAllowedPermissions.call(
        user: @user,
        repository: @repo,
        ref: "master",
        repository_permissions: {
          "#{@repo.nwo}" => { "contents" => "read", "metadata" => "read" },
        },
        owner_permissions: {},
        is_prebuild: true,
      )
      assert Codespaces::AllowedPermission.where(target_id: @repo.id, target_type: :repository, resource: "contents", action: "read", is_prebuild: true).exists?
    end

    test "it does not write repo permissions for prebuild if the user does not have access" do
      GitHub.flipper[:codespaces_prebuild_admin_repo_access].enable
      dc_contents = %{
        {
          "codespaces": {
            "repositories": [
              {
                "name": "#{@repo.nwo}",
                "permissions": {
                  "contents": "read"
                }
              },
            ]
          }
        }
      }

      @repo.refs.find("master").append_commit({ message: "add devcontainer json file", committer: @repo.owner }, @repo.owner) do |files|
        files.add(".devcontainer/devcontainer.json", dc_contents)
      end

      Codespaces::WriteAllowedPermissions.call(
        user: @user2,
        repository: @repo,
        ref: "master",
        repository_permissions: {
          "#{@repo.nwo}" => { "contents" => "read", "metadata" => "read" },
        },
        owner_permissions: {},
        is_prebuild: true,
      )
      refute Codespaces::AllowedPermission.where(target_id: @repo.id, target_type: :repository, resource: "contents", action: "read", is_prebuild: true).exists?
      refute Codespaces::AllowedPermission.where(target_id: @repo.id, target_type: :repository, resource: "metadata", action: "read", is_prebuild: true).exists?
    end

    test "it doesn't break when Codespaces::DevContainer::ReadError happens if both permission sets are nil" do
      @repo.stubs(:tree_entry).raises(Codespaces::DevContainer::ReadError)
      assert_nothing_raised do
        Codespaces::WriteAllowedPermissions.new(
          user: @user,
          repository: @repo,
          ref: "abc",
          repository_permissions: nil,
          owner_permissions: nil
        ).perform
      end
    end

    context "all_repository_params" do
      test "it returns error if there is a diff between permissions params and actual permissions" do
        dc_contents = %{
          {
            "codespaces": {
              "repositories": [
                {
                  "name": "#{@repo.nwo}",
                  "permissions": {
                    "contents": "read",
                    "issues": "read"
                  }
                },
                {
                  "name": "#{@repo.owner.login}/*",
                  "permissions": {
                    "contents": "write"
                  }
                },
              ]
            }
          }
        }

        @repo.refs.find("master").append_commit({ message: "add devcontainer json file", committer: @repo.owner }, @repo.owner) do |files|
          files.add(".devcontainer/devcontainer.json", dc_contents)
        end

        expected_error = %Q(The permissions in the devcontainer.json file do not match the requested permissions.)

        assert_raises_with_message(Codespaces::WriteAllowedPermissions::PermissionDifferenceError, expected_error) do
          Codespaces::WriteAllowedPermissions.new(
            user: @user,
            repository: @repo,
            ref: "master",
            repository_permissions: { "#{@repo.nwo}" => { "contents" => "read", "issues" => "read" } },
            owner_permissions: { "#{@repo.owner}" => { "contents" => "read", "issues" => "read" } }
          ).perform
        end

        refute Codespaces::AllowedPermission.where(target_id: @repo.id, target_type: :repository, resource: "contents", action: "read").exists?
      end
    end
  end
end
