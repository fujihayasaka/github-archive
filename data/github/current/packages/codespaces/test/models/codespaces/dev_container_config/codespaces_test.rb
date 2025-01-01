# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/query_identifier_helper"

class Codespaces::DevContainerConfig::CodespacesTest < GitHub::TestCase
  include CodespacesRepoHelper
  include QueryIdentifierHelper

  fixtures do
    @target_repo = create(:repository)
    @user = create :user, :with_codespaces_basic_tier_access
  end

  context "::from_hash" do
    test "builds a Codespaces::DevContainerConfig::Codespaces from devcontainer configuration" do
      second_repo = create(:repository, owner: @target_repo.owner)
      codespace = Codespaces::DevContainerConfig::Codespaces.from_hash(@target_repo, @user, {
        "repositories" => [
          {
            "name" => second_repo.nwo,
            "permissions" => {
              "contents" => "read",
            }
          }
        ]
      })

      assert_equal({}, codespace.all_repository_permissions)
      assert_equal({ second_repo.nwo => { "contents" => "read", "metadata" => "read" } }, codespace.unvalidated_permissions)
      assert_equal({ second_repo.nwo => { "contents" => "read" } }, codespace.unknown_repository_permissions)
    end

    test "in proxima builds a Codespaces::DevContainerConfig::Codespaces from devcontainer configuration", skip_enterprise: true do
      emu = create(:emu)
      business = emu.enterprise_managed_business

      on_multi_tenant_enterprise(tenant: business) do
        org = create(:organization)

        first_repo = create(:repository, owner: org)
        second_repo = create(:repository, owner: first_repo.owner)

        codespace = Codespaces::DevContainerConfig::Codespaces.from_hash(first_repo, emu, {
          "repositories" => [
            {
              "name" => second_repo.name_with_display_owner, # User inputs name without suffix
              "permissions" => {
                "contents" => "read",
              }
            }
          ]
        })

        assert_equal({}, codespace.all_repository_permissions)
        assert_equal({ second_repo.name_with_display_owner => { "contents" => "read", "metadata" => "read" } }, codespace.unvalidated_permissions)
        assert_equal({ second_repo.name_with_display_owner => { "contents" => "read" } }, codespace.unknown_repository_permissions)
      end
    end

    test "ignores repos with empty permissions" do
      second_repo = create(:repository, owner: @target_repo.owner)
      codespace = Codespaces::DevContainerConfig::Codespaces.from_hash(@target_repo, @user, {
        "repositories" => [
          {
            "name" => second_repo.nwo,
            "permissions" => {}
          }
        ]
      })

      assert_equal({}, codespace.all_repository_permissions)
      assert_equal({}, codespace.unvalidated_permissions)
      assert_equal({}, codespace.unknown_repository_permissions)
    end

    test "ignores write permissions on read-only subjects" do
      second_repo = create(:repository, owner: @target_repo.owner)
      codespace = Codespaces::DevContainerConfig::Codespaces.from_hash(@target_repo, @user, {
        "repositories" => {
          second_repo.nwo => {
            "permissions" => {
              "metadata" => "write"
            }
          }
        }
      })

      assert_equal({}, codespace.all_repository_permissions)
      assert_equal({}, codespace.unvalidated_permissions)
      assert_equal({}, codespace.unknown_repository_permissions)
    end

    test "ignores read permissions on write-only subjects" do
      second_repo = create(:repository, owner: @target_repo.owner)
      codespace = Codespaces::DevContainerConfig::Codespaces.from_hash(@target_repo, @user, {
        "repositories" => {
          second_repo.nwo => {
            "permissions" => {
              "workflows" => "read"
            }
          }
        }
      })

      assert_equal({}, codespace.all_repository_permissions)
      assert_equal({}, codespace.unvalidated_permissions)
      assert_equal({}, codespace.unknown_repository_permissions)
    end
  end

  context "#diff_all_permissions" do
    test "dev container config has new permissions" do
      repo = repo_with_devcontainer do |r|
        <<-JSON5
        {
          "postCreateCommand": "post-create.sh",
          "codespaces": {
            "repositories": [
              {
                "name": "#{r.nwo}",
                "permissions": {
                  "contents": "read",
                }
              },
            ]
          }
        }
        JSON5
      end

      devcontainer = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: @user)
      build :codespace, owner: @user, repository: repo
      diff = devcontainer.diff_all_permissions

      assert_equal diff.requested, { repo => { "contents" => "read", "metadata" => "read" } }
      assert_equal diff.revoked, {}
      assert_equal diff.consented, {}
      assert_equal diff.unconsented, { repo => { "contents" => "read", "metadata" => "read" } }
    end

    test "dev container config has 1 permission removed for a repo" do
      repo = repo_with_devcontainer do |r|
        <<-JSON5
        {
          "postCreateCommand": "post-create.sh",
          "codespaces": {
            "repositories": [
              {
                "name": "#{r.nwo}",
                "permissions": {
                  "contents": "read"
                }
              },
            ]
          }
        }
        JSON5
      end

      # User previously authorized for "write" to "actions"
      create(:allowed_permission, user: @user, repository: repo, target: repo, action: :write, resource: :actions)

      devcontainer = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: @user)
      build :codespace, owner: @user, repository: repo
      diff = devcontainer.diff_all_permissions

      assert_equal diff.requested, { repo => { "contents" => "read", "metadata" => "read" } }
      assert_equal diff.revoked, { repo => { "actions" => "write" } }
      assert_equal diff.consented, {}
      assert_equal diff.unconsented, { repo => { "contents" => "read", "metadata" => "read" } }
    end

    test "dev container config has all permissions removed for a repo" do
      repo = repo_with_devcontainer do |_r|
        <<-JSON5
        {
          "postCreateCommand": "post-create.sh",
          "codespaces": {
          }
        }
        JSON5
      end

      # User previously authorized for "write" to "actions"
      create(:allowed_permission, user: @user, repository: repo, target: repo, action: :write, resource: :actions)

      devcontainer = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: @user)
      build :codespace, owner: @user, repository: repo
      diff = devcontainer.diff_all_permissions

      assert_equal diff.requested, {}
      assert_equal diff.revoked, { repo => { "actions" => "write" } }
      assert_equal diff.consented, {}
      assert_equal diff.unconsented, {}
    end

    test "dev container config has all permissions removed for a user" do
      repo = repo_with_devcontainer do |_r|
        <<-JSON5
        {
          "postCreateCommand": "post-create.sh",
          "codespaces": {
          }
        }
        JSON5
      end

      # User previously authorized for "write" to "actions"
      create(:allowed_permission, user: @user, repository: repo, target: @user, action: :write, resource: :actions)

      devcontainer = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: @user)
      build :codespace, owner: @user, repository: repo
      diff = devcontainer.diff_all_permissions

      assert_equal diff.requested, {}
      assert_equal diff.revoked, { @user => { "actions" => "write" } }
      assert_equal diff.consented, {}
      assert_equal diff.unconsented, {}
    end
  end

  context "#validate_repository_permissions_for_user" do
    test "the number of queries for permission checks for any number of repos is constant" do
      user = create(:user)
      org = create(:organization)
      org.add_member(user)
      repo = create(:repository, owner: org)
      second_repo = create(:repository, owner: org)
      [repo, second_repo].each do |r|
        r.add_member(user)
      end

      Codespaces::AllowedPermission.create!(user: user, repository: repo, target_id: second_repo.id, target_type: "Repository", resource: "contents", action: "write")
      _, queries_for_few_repos = log_cleaned_queries do
        codespace = Codespaces::DevContainerConfig::Codespaces.from_hash(repo, user, {
          "repositories" => [
            {
              "name" => second_repo.nwo,
              "permissions" => {
                "contents" => "write",
              }
            }
          ]
        })
      end

      repos = []
      10.times do
        r = create(:repository, owner: org)
        r.add_member(user)
        Codespaces::AllowedPermission.create!(user: user, repository: repo, target_id: r.id, target_type: "Repository", resource: "contents", action: "write")
        repos << r
      end

      repo_permissions = []
      repos.each do |r|
        repo_permissions << {
          "name" => r.nwo,
          "permissions" => {
            "contents" => "write",
          }
        }
      end

      _, queries_for_many_repos = log_cleaned_queries do
        codespace = Codespaces::DevContainerConfig::Codespaces.from_hash(repo, user, {
          "repositories" => repo_permissions
        })
      end

      assert_equal queries_for_few_repos.count, queries_for_many_repos.count
    end
  end
end
