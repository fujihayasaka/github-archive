# typed: true
# frozen_string_literal: true

require "test_helper"

class DevContainerTest < GitHub::TestCase
  include CodespacesRepoHelper
  include DogstatsTestHelpers

  context "parsing & existence" do
    test "parses well-formatted devcontainer.json" do
      repo = repo_with_devcontainer <<-JSON5
        {
          "postCreateCommand": "post-create.sh",
          "hostRequirements": {
            "cpus": 4,
            "gpus": 1,
            "memory": "8gb",
            "storage": "32gb",
          }
        }
      JSON5

      dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid)

      assert_equal 4, dc.host_requirements.cpus
      assert_equal 1, dc.host_requirements.gpus
      assert_equal 8.gigabytes, dc.host_requirements.memory
      assert_equal 32.gigabytes, dc.host_requirements.storage
      assert_equal "post-create.sh", dc["postCreateCommand"]
      assert_equal "8gb", dc.dig("hostRequirements", "memory")
      assert dc.exists?
    end

    test "parses well-formatted devcontainer.json in nondefault path" do
      devcontainers = {}
      devcontainers[".devcontainer/foobar/devcontainer.json"] = <<-JSON5
        {
          "postCreateCommand": "post-create.sh",
          "hostRequirements": {
            "cpus": 3,
            "gpus": 1,
            "memory": "4gb",
            "storage": "16gb",
          }
        }
      JSON5

      repo = repo_with_devcontainers(devcontainers)

      dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, filepath: ".devcontainer/foobar/devcontainer.json")

      assert dc.exists?
      assert_equal 3, dc.host_requirements.cpus
      assert_equal 1, dc.host_requirements.gpus
      assert_equal 4.gigabytes, dc.host_requirements.memory
      assert_equal 16.gigabytes, dc.host_requirements.storage
      assert_equal "post-create.sh", dc["postCreateCommand"]
    end

    test "parses devcontainer.json when it has duplicate keys" do
      repo = repo_with_devcontainer <<-JSON5
        {
          "name": "Declarative secrets",
          "secrets": {
            "SECRET_ONE": {
              "description": "Use this",
            },
            // Duplicate key should get ignored
            "SECRET_ONE": {
              "description": "Not this",
            },
            "SECRET_TWO": {
              "description": "Secret two description",
            }
          }
        }
      JSON5

      dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid)

      assert dc.exists?
      assert_equal "Declarative secrets", dc["name"]
      secrets = dc["secrets"]
      assert_equal 2, secrets.count
      assert_equal "Use this", secrets["SECRET_ONE"]["description"]
      assert_equal "Secret two description", secrets["SECRET_TWO"]["description"]
    end

    test "fails silently when parsing invalid json (random string)" do
      repo = repo_with_devcontainer <<-JSON5
        some trash instead of json
      JSON5
      dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid)

      assert_equal 0, dc.host_requirements.cpus
      assert_equal 0, dc.host_requirements.gpus
      assert_equal 0, dc.host_requirements.memory
      assert_equal 0, dc.host_requirements.storage
      assert_nil dc["postCreateCommand"]
      refute dc.exists?
    end

    test "fails silently when parsing invalid json (hanging bracket)" do
      repo = repo_with_devcontainer <<-JSON5
        {
          "foo": "bar"
      JSON5
      dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid)
      refute dc.exists?
    end

    test "fails silently when parsing entirely-escaped json" do
      repo = repo_with_devcontainer("// {\n//")
      dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid)

      assert_equal 0, dc.host_requirements.cpus
      assert_equal 0, dc.host_requirements.gpus
      assert_equal 0, dc.host_requirements.memory
      assert_equal 0, dc.host_requirements.storage
      assert_nil dc["postCreateCommand"]
      refute dc.exists?
    end

    test "Does not raise error when parsing json fails" do
      devcontainers = {}
      devcontainers[".devcontainer/foobar/devcontainer.json"] = <<-JSON5
        {uhoh}
      JSON5

      devcontainers[".devcontainer/almost.correct.json"] = <<-JSON5
        {}
      JSON5

      repo = repo_with_devcontainers(devcontainers)

      assert_nothing_raised do
        Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, filepath: ".devcontainer/foobar/devcontainer.json").exists?
      end
    end

    test "raises Codespaces::DevContainer::ReadError when GitRPC::InvalidFullOid occurs" do
      repo = repo_with_devcontainer <<-JSON5
        {
          "postCreateCommand": "post-create.sh",
          "hostRequirements": {
            "cpus": 4,
            "gpus": 1,
            "memory": "8gb",
            "storage": "32gb",
          }
        }
      JSON5

      assert_raises Codespaces::DevContainer::ReadError do
        Codespaces::DevContainer.new(repository: repo, oid: "abc", filepath: ".devcontainer/foobar/devcontainer.json").diff_all_permissions
      end
    end

    test "raises errors when devcontainer path is specified and there are errors" do
      devcontainers = {}
      devcontainers[".devcontainer/foobar/devcontainer.json"] = <<-JSON5
        {uhoh}
      JSON5

      devcontainers[".devcontainer/almost.correct.json"] = <<-JSON5
        {}
      JSON5

      repo = repo_with_devcontainers(devcontainers)

      # file path not valid string
      assert_raises_with_message Codespaces::DevContainer::ReadError, /must be valid string location to a devcontainer.json file/ do
        Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, filepath: :invalid).exists?
      end

      assert_raises_with_message Codespaces::DevContainer::ReadError, /must be valid string location to a devcontainer.json file/ do
        Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, filepath: ".devcontainer/almost.correct.json").exists?
      end

      # file path not found
      assert_raises_with_message Codespaces::DevContainer::ReadError, /does not exist in this repository/ do
        Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, filepath: ".devcontainer/barbaz/devcontainer.json").exists?
      end

    end

    test "returns defaults when there is no devcontainer in the repo" do
      repo = create(:repository, from_example: :simple)

      dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid)

      assert_equal 0, dc.host_requirements.cpus
      assert_equal 0, dc.host_requirements.gpus
      assert_equal 0, dc.host_requirements.memory
      assert_equal 0, dc.host_requirements.storage
      assert_nil dc["postCreateCommand"]
    end

    test "devcontainer.json file path validations allow valid paths" do
      valid_paths = [
        ".devcontainer.json",
        ".devcontainer/devcontainer.json",
        ".devcontainer/foobar/devcontainer.json",
        ".devcontainer/\"foobar\"/devcontainer.json",
        ".devcontainer/foo bar/devcontainer.json",
        ".devcontainer/foo ' \" bar/devcontainer.json",
        ".devcontainer/f/devcontainer.json",
        ".devcontainer/\"/devcontainer.json",
        ".devcontainer/-/devcontainer.json",
      ]

      assert valid_paths.all? { |path| path.match(Codespaces::DevContainer::VALID_DEVCONTAINER_PATH_GLOB) }

      invalid_paths = [
        ".devcontainer/foobar.devcontainer.json",
        ".devcontainer/ /devcontainer.json",
        ".devcontainer/fo ' \" bar /devcontainer.json",
        ".devcontainer/foo$/devcontainer.json",
        ".devcontainer/devcontainerfoo.json",
      ]

      refute invalid_paths.any? { |path| path.match(Codespaces::DevContainer::VALID_DEVCONTAINER_PATH_GLOB) }
    end
  end

  context "list devcontainers" do
    test "finds non-default devcontainer.json files" do
      user = create(:user)
      repo = create(:repository, owner: user)

      metadata = { message: "Add devcontainer.json", committer: user }
      repo.heads.find_or_build(repo.default_branch).append_commit(metadata, user) do |files|
        files.add ".devcontainer/devcontainer.json", "{\"name\": \"testname\"}" # valid
        files.add ".devcontainer/foobar/devcontainer.json", "{}" # valid
        files.add ".devcontainer/foobar/bazquu/devcontainer.json", "{}" # invalid, can only be one directory deep from .devcontainer
        files.add ".devcontainer/devcontainer.bazqux.json", "{}" # wrong filepath, must end in devcontainer.json
        files.add ".devcontainer/actions/devcontainer.json", "{}" # also valid
        files.add ".devcontainer/random-file.txt", "loremipsum" # random file, will not be picked up
        files.add ".devcontainer/devcontainer.invalid.json", "{notgood}" # not valid JSON so won't be returned
        # This makes JSON5.parse blow up with a TypeError for $reasons
        files.add ".devcontainer/parse-error/devcontainer.json", <<-JSON5
          {
            "name": "testname",
            "secrets": {
              "NAME": {
                "description": "Name of the person to greet"
        JSON5
      end

      devcontainers = Codespaces::DevContainer.list_dev_containers(
        repo,
        Codespaces::GetTargetRef.call(repository: repo, name_or_oid: repo.default_branch)&.target_oid
      )

      assert_equal 3, devcontainers.size
      # order is deliberate and .devcontainer/devcontainer.json will always come before non-default devcontainer.json files
      assert_equal ".devcontainer/devcontainer.json", devcontainers.first.path
      assert_equal "testname", devcontainers.first.name
      # then it is lexicographically sorted by custom directory from there
      assert_equal ".devcontainer/actions/devcontainer.json", devcontainers.second.path
      assert_equal ".devcontainer/foobar/devcontainer.json", devcontainers.third.path


      # specific branch

      repo.heads.find_or_build("new-branch").append_commit(metadata, user) do |files|
        files.add ".devcontainer/new-branch/devcontainer.json", "{}"
        files.add ".devcontainer/random-file.txt", "loremipsum" # not a devcontainer
      end

      devcontainers = Codespaces::DevContainer.list_dev_containers(
        repo,
        Codespaces::GetTargetRef.call(repository: repo, name_or_oid: "new-branch")&.target_oid
      )

      assert_equal 1, devcontainers.size
      assert_equal ".devcontainer/new-branch/devcontainer.json", devcontainers.first.path
    end

    test "caches devcontainer presence when listing devcontainers on the default OID with flag enabled" do
      GitHub.flipper[:codespaces_devcontainer_caching].enable
      repo = repo_with_devcontainer

      refute Codespaces::DevContainer.any_devcontainers?(repo)

      Codespaces::DevContainer.list_dev_containers(
        repo,
        repo.default_oid
      )

      assert Codespaces::DevContainer.any_devcontainers?(repo)
    end

    test "doesn't unset cached devcontainers when listing on a non-default OID that doesn't have them with flag enabled" do
      GitHub.flipper[:codespaces_devcontainer_caching].enable
      repo = repo_with_devcontainer
      user = repo.owner

      Codespaces::DevContainer.list_dev_containers(
        repo,
        repo.default_oid
      )

      assert Codespaces::DevContainer.any_devcontainers?(repo)

      # Create another branch without the devcontainer.json file
      metadata = { message: "Remove devcontainer.json", committer: user }
      repo.heads.find_or_build("new-branch").append_commit(metadata, user)

      # Now we list them for this other branch.
      Codespaces::DevContainer.list_dev_containers(
        repo,
        Codespaces::GetTargetRef.call(repository: repo, name_or_oid: "new-branch")&.target_oid
      )

      assert Codespaces::DevContainer.any_devcontainers?(repo)
    end

    test "returns empty set when no devcontainer.json files detected" do
      user = create(:user)
      repo = create(:repository, owner: user)

      metadata = { message: "Add devcontainer.json", committer: user }
      repo.heads.find_or_build(repo.default_branch).append_commit(metadata, user) do |files|
        files.add ".devcontainer/random-file.txt", "loremipsum" # not a devcontainer
      end

      devcontainers = Codespaces::DevContainer.list_dev_containers(
        repo,
        Codespaces::GetTargetRef.call(repository: repo, name_or_oid: repo.default_branch)&.target_oid
      )

      assert_empty devcontainers
    end

    test "returns empty set when provided repo or oid is nil" do
      user = create(:user)
      repo = create(:repository, owner: user)

      metadata = { message: "Add devcontainer.json", committer: user }
      repo.heads.find_or_build(repo.default_branch).append_commit(metadata, user) do |files|
        files.add ".devcontainer/foobar.devcontainer.json", "{}"
      end

      devcontainers = Codespaces::DevContainer.list_dev_containers(
        nil,
        Codespaces::GetTargetRef.call(repository: repo, name_or_oid: repo.default_branch)&.target_oid
      )

      assert_empty devcontainers

      devcontainers = Codespaces::DevContainer.list_dev_containers(repo, nil)

      assert_empty devcontainers
    end
  end

  context "get default devcontainer path" do
    test "returns default devcontainer path .devcontainer/devcontainer.json if it exists" do
      user = create(:user)
      repo = create(:repository, owner: user)

      metadata = { message: "Add devcontainer.json", committer: user }
      repo.heads.find_or_build(repo.default_branch).append_commit(metadata, user) do |files|
        files.add ".devcontainer/devcontainer.json", "{\"name\": \"testname\"}" # valid
        files.add ".devcontainer/foobar/devcontainer.json", "{}" # valid
        files.add ".devcontainer/foo/devcontainer.json", "{}" # valid
      end

      assert_equal ".devcontainer/devcontainer.json", Codespaces::DevContainer.get_default_path(repo, Codespaces::GetTargetRef.call(repository: repo, name_or_oid: repo.default_branch)&.target_oid)
    end

    test "returns default devcontainer path .devcontainer.json if it exists" do
      user = create(:user)
      repo = create(:repository, owner: user)

      metadata = { message: "Add devcontainer.json", committer: user }
      repo.heads.find_or_build(repo.default_branch).append_commit(metadata, user) do |files|
        files.add ".devcontainer.json", "{\"name\": \"testname\"}" # valid
      end

      assert_equal ".devcontainer.json", Codespaces::DevContainer.get_default_path(repo, Codespaces::GetTargetRef.call(repository: repo, name_or_oid: repo.default_branch)&.target_oid)
    end

    test "returns nil if no default devcontainer path exists" do
      user = create(:user)
      repo = create(:repository, owner: user)

      metadata = { message: "Add devcontainer.json", committer: user }
      repo.heads.find_or_build(repo.default_branch).append_commit(metadata, user) do |files|
        files.add ".devcontainer/foobar/devcontainer.json", "{}" # valid
        files.add ".devcontainer/foo/devcontainer.json", "{}" # valid
      end

      assert_nil Codespaces::DevContainer.get_default_path(repo, Codespaces::GetTargetRef.call(repository: repo, name_or_oid: repo.default_branch)&.target_oid)
    end
  end

  context "host requirements" do
    test "defaults to 0 for all requirements if not present" do
      repo = repo_with_devcontainer <<-JSON5
        {
          "postCreateCommand": "post-create.sh"
        }
      JSON5
      dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner)

      assert_equal 0, dc.host_requirements.cpus
      assert_equal 0, dc.host_requirements.gpus
      assert_equal 0, dc.host_requirements.memory
      assert_equal 0, dc.host_requirements.storage
      assert_equal "post-create.sh", dc["postCreateCommand"]
    end

    test "each individual requirement defaults to 0 if missing" do
      repo = repo_with_devcontainer <<-JSON5
        {
          "postCreateCommand": "post-create.sh",
          "hostRequirements": {
            "gpus": 1,
            "memory": "8gb",
            "storage": "32gb",
          }
        }
      JSON5
      dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner)

      assert_equal 0, dc.host_requirements.cpus

      repo = repo_with_devcontainer <<-JSON5
        {
          "postCreateCommand": "post-create.sh",
          "hostRequirements": {
            "cpus": 4,
            "gpus": 1,
            "storage": "32gb",
          }
        }
      JSON5
      dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner)

      assert_equal 0, dc.host_requirements.memory

      repo = repo_with_devcontainer <<-JSON5
        {
          "postCreateCommand": "post-create.sh",
          "hostRequirements": {
            "cpus": 4,
            "gpus": 1,
            "memory": "8gb",
          }
        }
      JSON5
      dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner)

      assert_equal 0, dc.host_requirements.storage

      repo = repo_with_devcontainer <<-JSON5
        {
          "postCreateCommand": "post-create.sh",
          "hostRequirements": {
            "cpus": 4,
            "memory": "8gb",
            "storage": "32gb",
          }
        }
      JSON5
      dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner)

      assert_equal 0, dc.host_requirements.gpus
    end

    test "requirements default to zero if they are invalid" do
      repo = repo_with_devcontainer <<-JSON5
        {
          "postCreateCommand": "post-create.sh",
          "hostRequirements": {
            "cpus": "four",
            "gpus": "one",
            "memory": "8gigglybibblies",
            "storage": "a good amount of storage"
          }
        }
      JSON5
      dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner)

      assert_equal 0, dc.host_requirements.cpus
      assert_equal 0, dc.host_requirements.gpus
      assert_equal 0, dc.host_requirements.memory
      assert_equal 0, dc.host_requirements.storage
    end
  end

  context "image" do
    test "defaults to nil if not present" do
      repo = repo_with_devcontainer <<-JSON5
        {
          "postCreateCommand": "post-create.sh"
        }
      JSON5
      dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner)

      refute dc.image
    end

    test "returns the image if present" do
      repo = repo_with_devcontainer <<-JSON5
        {
          "postCreateCommand": "post-create.sh",
          "image": "ghcr.io/github/github/bootstrap-nightly:latest"
        }
      JSON5
      dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner)

      assert_equal dc.image, "ghcr.io/github/github/bootstrap-nightly:latest"
    end
  end

  context "deprecated syntax" do
    context "codespaces" do
      test "defaults to empty Codespaces if not present" do
        repo = repo_with_devcontainer <<-JSON5
          {
            "postCreateCommand": "post-create.sh"
          }
        JSON5
        dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner)

        refute_nil dc.codespaces
        refute dc.codespaces.has_custom_permissions?
      end

      test "returns empty Codespaces if codespaces is empy" do
        repo = repo_with_devcontainer <<-JSON5
          {
            "postCreateCommand": "post-create.sh",
            "codespaces": {}
          }
          JSON5
        dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner)

        refute_nil dc.codespaces
        refute dc.codespaces.has_custom_permissions?
      end

      context "repository_permissions" do
        test "defaults to empty array if not present" do
          repo = repo_with_devcontainer <<-JSON5
          {
            "postCreateCommand": "post-create.sh",
            "codespaces": {
              "repositories": {}
            }
          }
          JSON5
          dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner)

          refute_nil dc.codespaces
          refute dc.codespaces.has_custom_permissions?
        end

        test "captures error for repository_permissions with names but with no permissions" do
          repo = repo_with_devcontainer do |r|
            <<-JSON5
            {
              "postCreateCommand": "post-create.sh",
              "codespaces": {
                "repositories": [
                  {
                    "name": "#{r.owner.login}/bar"
                  },
                  {
                    "name": "#{r.owner.login}/baz"
                  },
                ]
              }
            }
            JSON5
          end

          dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner).codespaces

          refute_empty dc.errors
          assert_equal "Repository \'#{repo.owner.login}\/bar\' cannot have empty permissions", dc.errors.first.message
        end

        test "captures error for repository_permissions with names but with empty permissions" do
          repo = repo_with_devcontainer do |r|
            <<-JSON5
            {
              "postCreateCommand": "post-create.sh",
              "codespaces": {
                "repositories": [
                  {
                    "name": "#{r.owner.login}/bar",
                    "permissions": {}
                  },
                  {
                    "name": "#{r.owner.login}/baz"
                  },
                ]
              }
            }
            JSON5
          end

          dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner).codespaces

          refute_empty dc.errors
          assert_equal "Repository \'#{repo.owner.login}\/bar\' cannot have empty permissions", dc.errors.first.message
        end

        test "captures error for all_repository_permissions with no permissions" do
          repo = repo_with_devcontainer do |r|
            <<-JSON5
            {
              "postCreateCommand": "post-create.sh",
              "codespaces": {
                "repositories": [
                  {
                    "name": "#{r.owner.login}/*"
                  },
                ]
              }
            }
            JSON5
          end

          dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner).codespaces

          refute_empty dc.errors
          assert_equal "Repository \'#{repo.owner.login}\/*\' cannot have empty permissions", dc.errors.first.message
        end

        test "captures error for all_repository_permissions with empty permissions" do
          repo = repo_with_devcontainer do |r|
            <<-JSON5
            {
              "postCreateCommand": "post-create.sh",
              "codespaces": {
                "repositories": [
                  {
                    "name": "#{r.owner.login}/*",
                    "permissions": {}
                  },
                ]
              }
            }
            JSON5
          end

          dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner).codespaces

          refute_empty dc.errors
          assert_equal "Repository \'#{repo.owner.login}\/*\' cannot have empty permissions", dc.errors.first.message
        end

        test "captures error if invalid repo name" do
          repo = repo_with_devcontainer do |r|
            <<-JSON5
            {
              "postCreateCommand": "post-create.sh",
              "codespaces": {
                "repositories": [
                  {
                    "name": "foo",
                    "permissions": {
                      "contents": "read",
                      "notreal": "read"
                    }
                  },
                  {
                    "name": "#{r.owner.login}/baz",
                    "permissions": {
                      "contents": "write"
                    }
                  },
                ]
              }
            }
            JSON5
          end

          dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner).codespaces

          refute_empty dc.errors
          assert_equal "\'foo\' is not a valid repository name", dc.errors.first.message
        end

        test "raises error if called unknown_repository_permissions without first calling validate_repository_permissions_for_user" do
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
                      "notreal": "read"
                    }
                  },
                  {
                    "name": "#{r.owner.login}/*",
                    "permissions": {
                      "contents": "write"
                    }
                  },
                ]
              }
            }
            JSON5
          end

          dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid)
          assert_raises "You must call validate_repository_permissions_for_user before calling unknown_repository_permissions" do
            dc.codespaces.unknown_repository_permissions
          end
        end

        test "returns repository_permissions with repos and valid permissions" do
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
                      "notreal": "read"
                    }
                  },
                  {
                    "name": "#{r.owner.login}/*",
                    "permissions": {
                      "contents": "write"
                    }
                  },
                ]
              }
            }
            JSON5
          end

          dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner)

          refute_nil dc.codespaces
          assert dc.codespaces.has_custom_permissions?
          refute_empty dc.codespaces.repository_permissions

          assert_equal "read", dc.codespaces.repository_permissions[repo]["contents"]

          # assert that it added the mandatory metadata permission
          assert_equal "read", dc.codespaces.repository_permissions[repo]["metadata"]

          refute_empty dc.codespaces.all_repository_permissions
          assert_equal "write", dc.codespaces.all_repository_permissions[repo.owner]["contents"]
        end

        test "returns repository_permissions with repos read-all permissions" do
          repo = repo_with_devcontainer do |r|
            <<-JSON5
            {
              "postCreateCommand": "post-create.sh",
              "codespaces": {
                "repositories": [
                  {
                    "name": "#{r.nwo}",
                    "permissions": "read-all",
                  },
                  {
                    "name": "#{r.owner.login}/*",
                    "permissions": {
                      "contents": "write"
                    }
                  },
                ]
              }
            }
            JSON5
          end

          dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner)

          refute_nil dc.codespaces
          assert dc.codespaces.has_custom_permissions?
          refute_empty dc.codespaces.repository_permissions

          Codespaces::DevContainerConfig::Codespaces::Repository::ALLOWED_ALL_SUBJECTS.each do |subject_type|
            actual = dc.codespaces.repository_permissions[repo][subject_type]
            assert_equal "read", actual, "Expected read for '#{subject_type}' but got '#{actual}'"
          end

          refute_empty dc.codespaces.all_repository_permissions
          assert_equal "write", dc.codespaces.all_repository_permissions[repo.owner]["contents"]
        end

        test "allowed subjects returns packages permission" do
          user = create(:user)
          assert(Codespaces::DevContainerConfig::Codespaces::Repository::ALLOWED_ALL_SUBJECTS.include?("packages"))
        end

        test "returns repository_permissions with repos write-all permissions" do
          repo = repo_with_devcontainer do |r|
            <<-JSON5
            {
              "postCreateCommand": "post-create.sh",
              "codespaces": {
                "repositories": [
                  {
                    "name": "#{r.nwo}",
                    "permissions": "write-all",
                  },
                  {
                    "name": "#{r.owner.login}/*",
                    "permissions": {
                      "contents": "write"
                    }
                  },
                ]
              }
            }
            JSON5
          end

          dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner)

          refute_nil dc.codespaces
          assert dc.codespaces.has_custom_permissions?
          refute_empty dc.codespaces.repository_permissions

          Codespaces::DevContainerConfig::Codespaces::Repository::ALLOWED_ALL_SUBJECTS.each do |subject_type|
            actual = dc.codespaces.repository_permissions[repo][subject_type]
            assert_equal "write", actual, "Expected write for '#{subject_type}' but got '#{actual}'"
          end

          refute_empty dc.codespaces.all_repository_permissions
          assert_equal "write", dc.codespaces.all_repository_permissions[repo.owner]["contents"]
        end

        test "captures error with string permission that is not read-all or write-all" do
          repo = repo_with_devcontainer do |r|
            <<-JSON5
            {
              "postCreateCommand": "post-create.sh",
              "codespaces": {
                "repositories": [
                  {
                    "name": "#{r.nwo}",
                    "permissions": 'paul-wall',
                  },
                  {
                    "name": "#{r.owner.login}/*",
                    "permissions": {
                      "contents": "write"
                    }
                  },
                ]
              }
            }
            JSON5
          end

          dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner).codespaces

          refute_empty dc.errors
          assert_equal "Repository '#{repo.nwo}' has invalid permissions", dc.errors.first.message
        end

        test "captures error with permissions that are not a hash or string" do
          repo = repo_with_devcontainer do |r|
            <<-JSON5
            {
              "postCreateCommand": "post-create.sh",
              "codespaces": {
                "repositories": [
                  {
                    "name": "#{r.nwo}",
                    "permissions": ["write-all", "read-all"],
                  },
                  {
                    "name": "#{r.owner.login}/*",
                    "permissions": {
                      "contents": "write"
                    }
                  },
                ]
              }
            }
            JSON5
          end

          dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner).codespaces

          refute_empty dc.errors
          assert_equal "Repository '#{repo.nwo}' has invalid permissions", dc.errors.first.message
        end
      end

      context "repositories" do
        test "returns found repositories specified in array" do
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
                      "notreal": "read"
                    }
                  },
                  {
                    "name": "#{r.owner.login}/*",
                    "permissions": {
                      "contents": "write"
                    }
                  },
                ]
              }
            }
            JSON5
          end

          dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner)

          refute_nil dc.codespaces
          assert dc.codespaces.has_custom_permissions?
          refute_empty dc.codespaces.repository_permissions
          refute_nil dc.codespaces.repository_permissions[repo]
        end
      end
    end
  end
  context "codespaces" do
    test "defaults to empty Codespaces if not present" do
      repo = repo_with_devcontainer <<-JSON5
        {
          "postCreateCommand": "post-create.sh"
        }
      JSON5
      dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner)

      refute_nil dc.codespaces
      refute dc.codespaces.has_custom_permissions?
    end

    test "returns empty Codespaces if codespaces is empy" do
      repo = repo_with_devcontainer <<-JSON5
        {
          "postCreateCommand": "post-create.sh",
          "customizations": {
            "codespaces": {}
          }
        }
        JSON5
      dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner)

      refute_nil dc.codespaces
      refute dc.codespaces.has_custom_permissions?
    end

    context "repository_permissions" do
      test "defaults to empty array if not present" do
        repo = repo_with_devcontainer <<-JSON5
        {
          "postCreateCommand": "post-create.sh",
          "customizations": {
            "codespaces": {
              "repositories": {}
            }
          }
        }
        JSON5
        dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner)

        refute_nil dc.codespaces
        refute dc.codespaces.has_custom_permissions?
      end

      test "captures error for repository_permissions with names but with no permissions" do
        repo = repo_with_devcontainer do |r|
          <<-JSON5
          {
            "postCreateCommand": "post-create.sh",
            "customizations": {
              "codespaces": {
                "repositories": {
                  "#{r.owner.login}/bar": {},
                  "#{r.owner.login}/baz": null,
                }
              }
            }
          }
          JSON5
        end

        dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner).codespaces

        refute_empty dc.errors
        assert_equal "Repository \'#{repo.owner.login}\/bar\' cannot have empty permissions", dc.errors.first.message
      end

      test "captures error for repository_permissions with names but with empty permissions" do
        repo = repo_with_devcontainer do |r|
          <<-JSON5
          {
            "postCreateCommand": "post-create.sh",
            "customizations": {
              "codespaces": {
                "repositories": {
                  "#{r.owner.login}/bar": {
                    "permissions": {}
                  },
                  "#{r.owner.login}/baz": {},
                }
              }
            }
          }
          JSON5
        end

        dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner).codespaces

        refute_empty dc.errors
        assert_equal "Repository \'#{repo.owner.login}\/bar\' cannot have empty permissions", dc.errors.first.message
      end

      test "captures error for all_repository_permissions with no permissions" do
        repo = repo_with_devcontainer do |r|
          <<-JSON5
          {
            "postCreateCommand": "post-create.sh",
            "customizations": {
              "codespaces": {
                "repositories": {
                  "#{r.owner.login}/*": {},
                }
              }
            }
          }
          JSON5
        end

        dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner).codespaces

        refute_empty dc.errors
        assert_equal "Repository \'#{repo.owner.login}\/*\' cannot have empty permissions", dc.errors.first.message
      end

      test "captures error for all_repository_permissions with empty permissions" do
        repo = repo_with_devcontainer do |r|
          <<-JSON5
          {
            "postCreateCommand": "post-create.sh",
            "customizations": {
              "codespaces": {
                "repositories": {
                  "#{r.owner.login}/*":{
                    "permissions": {}
                  },
                }
              }
            }
          }
          JSON5
        end

        dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner).codespaces

        refute_empty dc.errors
        assert_equal "Repository \'#{repo.owner.login}\/*\' cannot have empty permissions", dc.errors.first.message
      end

      test "captures error if invalid repo name" do
        repo = repo_with_devcontainer do |r|
          <<-JSON5
          {
            "postCreateCommand": "post-create.sh",
            "customizations": {
              "codespaces": {
                "repositories": {
                  "foo": {
                    "permissions": {
                      "contents": "read",
                      "notreal": "read"
                    }
                  },
                  "#{r.owner.login}/baz": {
                    "permissions": {
                      "contents": "write"
                    }
                  },
                }
              }
            }
          }
          JSON5
        end

        dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner).codespaces

        refute_empty dc.errors
        assert_equal "\'foo\' is not a valid repository name", dc.errors.first.message
      end

      test "raises error if called unknown_repository_permissions without first calling validate_repository_permissions_for_user" do
        repo = repo_with_devcontainer do |r|
          <<-JSON5
          {
            "postCreateCommand": "post-create.sh",
            "customizations": {
              "codespaces": {
                "repositories": {
                  "#{r.nwo}": {
                    "permissions": {
                      "contents": "read",
                      "notreal": "read"
                    }
                  },
                  "#{r.owner.login}/*": {
                    "permissions": {
                      "contents": "write"
                    }
                  }
                }
              }
            }
          }
          JSON5
        end

        dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid)
        assert_raises "You must call validate_repository_permissions_for_user before calling unknown_repository_permissions" do
          dc.codespaces.unknown_repository_permissions
        end
      end

      test "returns repository_permissions with repos and valid permissions" do
        repo = repo_with_devcontainer do |r|
          <<-JSON5
          {
            "postCreateCommand": "post-create.sh",
            "customizations": {
              "codespaces": {
                "repositories": {
                  "#{r.nwo}": {
                    "permissions": {
                      "contents": "read",
                      "notreal": "read"
                    }
                  },
                  "#{r.owner.login}/*": {
                    "permissions": {
                      "contents": "write"
                    }
                  }
                }
              }
            }
          }
          JSON5
        end

        dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner)

        refute_nil dc.codespaces
        assert dc.codespaces.has_custom_permissions?
        refute_empty dc.codespaces.repository_permissions

        assert_equal "read", dc.codespaces.repository_permissions[repo]["contents"]

        # assert that it added the mandatory metadata permission
        assert_equal "read", dc.codespaces.repository_permissions[repo].fetch("metadata")

        refute_empty dc.codespaces.all_repository_permissions
        assert_equal "write", dc.codespaces.all_repository_permissions[repo.owner]["contents"]
      end

      test "returns repository_permissions with repos read-all permissions" do
        repo = repo_with_devcontainer do |r|
          <<-JSON5
          {
            "postCreateCommand": "post-create.sh",
            "customizations": {
              "codespaces": {
                "repositories": {
                  "#{r.nwo}": {
                    "permissions": "read-all",
                  },
                  "#{r.owner.login}/*": {
                    "permissions": {
                      "contents": "write"
                    }
                  },
                }
              }
            }
          }
          JSON5
        end

        dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner)

        refute_nil dc.codespaces
        assert dc.codespaces.has_custom_permissions?
        refute_empty dc.codespaces.repository_permissions

        Codespaces::DevContainerConfig::Codespaces::Repository::ALLOWED_ALL_SUBJECTS.each do |subject_type|
          actual = dc.codespaces.repository_permissions[repo][subject_type]
          assert_equal "read", actual, "Expected read for '#{subject_type}' but got '#{actual}'"
        end

        refute_empty dc.codespaces.all_repository_permissions
        assert_equal "write", dc.codespaces.all_repository_permissions[repo.owner]["contents"]
      end

      test "returns repository_permissions with repos write-all permissions" do
        repo = repo_with_devcontainer do |r|
          <<-JSON5
          {
            "postCreateCommand": "post-create.sh",
            "customizations": {
              "codespaces": {
                "repositories": {
                  "#{r.nwo}": {
                    "permissions": "write-all",
                  },
                  "#{r.owner.login}/*": {
                    "permissions": {
                      "contents": "write"
                    }
                  },
                }
              }
            }
          }
          JSON5
        end

        dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner)

        refute_nil dc.codespaces
        assert dc.codespaces.has_custom_permissions?
        refute_empty dc.codespaces.repository_permissions

        Codespaces::DevContainerConfig::Codespaces::Repository::ALLOWED_ALL_SUBJECTS.each do |subject_type|
          actual = dc.codespaces.repository_permissions[repo][subject_type]
          assert_equal "write", actual, "Expected write for '#{subject_type}' but got '#{actual}'"
        end

        refute_empty dc.codespaces.all_repository_permissions
        assert_equal "write", dc.codespaces.all_repository_permissions[repo.owner]["contents"]
      end

      test "captures error with string permission that is not read-all or write-all" do
        repo = repo_with_devcontainer do |r|
          <<-JSON5
          {
            "postCreateCommand": "post-create.sh",
            "customizations": {
              "codespaces": {
                "repositories": {
                  "#{r.nwo}": {
                    "permissions": 'paul-wall',
                  },
                  "#{r.owner.login}/*": {
                    "permissions": {
                      "contents": "write"
                    }
                  },
                }
              }
            }
          }
          JSON5
        end

        dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner).codespaces

        refute_empty dc.errors
        assert_equal "Repository '#{repo.nwo}' has invalid permissions", dc.errors.first.message
      end

      test "captures error with permissions that are not a hash or string" do
        repo = repo_with_devcontainer do |r|
          <<-JSON5
          {
            "postCreateCommand": "post-create.sh",
            "customizations": {
              "codespaces": {
                "repositories": {
                  "#{r.nwo}": {
                    "permissions": ["write-all", "read-all"],
                  },
                  "#{r.owner.login}/*": {
                    "permissions": {
                      "contents": "write"
                    }
                  },
                }
              }
            }
          }
          JSON5
        end

        dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner).codespaces

        refute_empty dc.errors
        assert_equal "Repository '#{repo.nwo}' has invalid permissions", dc.errors.first.message
      end
    end

    context "annotated tag" do
      test "returns repository_permissions with repos and valid permissions when using annotated tag" do
        GitHub.flipper[:codespaces_devcontainer_annoted_tag_fix].enable
        repo = create(:repository, from_example: :refs_test)

        find_ref = repo.heads.find_or_build("master")

        dc_contents = <<-JSON5
          {
            "postCreateCommand": "post-create.sh",
            "customizations": {
              "codespaces": {
                "repositories": {
                  "#{repo.nwo}": {
                    "permissions": {
                      "contents": "read",
                    }
                  },
                }
              }
            }
          }
          JSON5

        repo.refs.find("master").append_commit({ message: "add devcontainer json file", committer: repo.owner }, repo.owner) do |files|
          files.add(".devcontainer/devcontainer.json", dc_contents)
        end

        commit_oid = repo.default_oid

        annotated_tag_oid = repo.rpc.create_tag_annotation("annotated_tag", commit_oid, message: "hello", tagger: {
          email: repo.owner.git_author_email,
          name: repo.owner.git_author_name,
          time: repo.owner.time_zone.now.iso8601,
        })
        ref = "refs/tags/annotated_tag"
        newvalue = annotated_tag_oid

        oldvalue = RefUpdater.rev_parse(repo, ref)
        res = RefUpdater.update_ref(repo, ref, newvalue, oldvalue)

        dc = Codespaces::DevContainer.new(repository: repo, oid: annotated_tag_oid, user: repo.owner)

        refute_nil dc.codespaces
        assert dc.codespaces.has_custom_permissions?
        refute_empty dc.codespaces.repository_permissions

        assert_equal "read", dc.codespaces.repository_permissions[repo]["contents"]

        # assert that it added the mandatory metadata permission
        assert_equal "read", dc.codespaces.repository_permissions[repo].fetch("metadata")
      end
    end

    context "repositories" do
      test "returns found repositories specified in array" do
        repo = repo_with_devcontainer do |r|
          <<-JSON5
          {
            "postCreateCommand": "post-create.sh",
            "customizations": {
              "codespaces": {
                "repositories": {
                  "#{r.nwo}": {
                    "permissions": {
                      "contents": "read",
                      "notreal": "read"
                    }
                  },
                  "#{r.owner.login}/*": {
                    "permissions": {
                      "contents": "write"
                    }
                  },
                }
              }
            }
          }
          JSON5
        end

        dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner)

        refute_nil dc.codespaces
        assert dc.codespaces.has_custom_permissions?
        refute_empty dc.codespaces.repository_permissions
        refute_nil dc.codespaces.repository_permissions[repo]
      end
    end
  end

  context "repository_permissions" do
    test "delegates to codespaces" do
      repo = repo_with_devcontainer do |r|
        <<-JSON5
        {
          "postCreateCommand": "post-create.sh",
          "customizations": {
            "codespaces": {
              "repositories": {
                "#{r.nwo}": {
                  "permissions": {
                    "contents": "read",
                    "notreal": "read"
                  }
                },
                "#{r.owner.login}/*": {
                  "permissions": {
                    "contents": "write"
                  }
                },
              }
            }
          }
        }
        JSON5
      end

      dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner)
      assert dc.has_custom_permissions?
      refute_empty dc.repository_permissions

      assert_equal "read", dc.repository_permissions[repo]["contents"]
      assert_nil dc.repository_permissions[repo]["notreal"]

      refute_empty dc.all_repository_permissions
      assert_equal "write", dc.all_repository_permissions[repo.owner]["contents"]
    end

    test "does not care about casing" do
      repo = repo_with_devcontainer do |r|
        <<-JSON5
        {
          "postCreateCommand": "post-create.sh",
          "customizations": {
            "codespaces": {
              "repositories": {
                "#{r.nwo.capitalize}": {
                  "permissions": {
                    "contents": "read",
                    "notreal": "read"
                  }
                },
                "#{r.owner.login.upcase}/*": {
                  "permissions": {
                    "contents": "write"
                  }
                },
              }
            }
          }
        }
        JSON5
      end

      dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner)
      assert dc.has_custom_permissions?
      refute_empty dc.repository_permissions

      assert_equal "read", dc.repository_permissions[repo]["contents"]
      assert_nil dc.repository_permissions[repo]["notreal"]

      refute_empty dc.all_repository_permissions
      assert_equal "write", dc.all_repository_permissions[repo.owner]["contents"]
    end

  end

  context "failed_checks" do
    test "returns permissions user requests but does not have" do
      random_repo = create(:private_repository)
      user = create(:user)

      # we request read permissions on random private repo
      permissions = {}
      permissions[random_repo.nwo] = { "contents" => "read" }
      config = Codespaces::DevContainerConfig::Codespaces.build(source_repository: nil, errors: nil, all_repository_permissions: nil, unvalidated_permissions: permissions, user: user)
      # read is returned for that repo because user does not have it
      assert_equal "read", config.unknown_repository_permissions[random_repo.nwo]["contents"]

      permissions[random_repo.nwo] = { "contents" => "write", "issues" => "read" }
      config = Codespaces::DevContainerConfig::Codespaces.build(source_repository: nil, errors: nil, all_repository_permissions: nil, unvalidated_permissions: permissions, user: user)
      assert_equal "write", config.unknown_repository_permissions[random_repo.nwo]["contents"]
      assert_equal "read", config.unknown_repository_permissions[random_repo.nwo]["issues"]
    end

    test "returns permissions user requests but does not have - different org" do
      repo = repo_with_devcontainer do |_r|
        <<-JSON5
        {
          "postCreateCommand": "post-create.sh",
          "customizations": {
            "codespaces": {
              "repositories": {
                "foobar/fake_repo": {
                  "permissions": {
                    "contents": "read",
                  }
                },
              }
            }
          }
        }
        JSON5
      end

      dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner)
      assert_equal "read", dc.unknown_repository_permissions["foobar/fake_repo"]["contents"]
    end

    test "returns permissions other than read and write to unknown permissions hash" do
      repo = repo_with_devcontainer do |r|
        <<-JSON5
        {
          "postCreateCommand": "post-create.sh",
          "customizations": {
            "codespaces": {
              "repositories": {
                "#{r.nwo}": {
                  "permissions": {
                    "contents": "foobar",
                  }
                },
              }
            }
          }
        }
        JSON5
      end

      dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner)
      assert_equal "foobar", dc.unknown_repository_permissions[repo.nwo]["contents"]
    end

    test "returns permissions other than read and write to unknown permissions hash - all namespace" do
      repo = repo_with_devcontainer do |r|
        <<-JSON5
        {
          "postCreateCommand": "post-create.sh",
          "customizations": {
            "codespaces": {
              "repositories": {
                "#{r.owner.name}/*": {
                  "permissions": {
                    "contents": "foobar",
                  }
                },
              }
            }
          }
        }
        JSON5
      end

      dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner)

      assert_equal "foobar", dc.unknown_repository_permissions["#{repo.owner.name}/*"]["contents"]
    end

    test "returns permissions user requests but does not have when repo does not exist" do
      user = create(:user)

      # we request read permissions on random private repo
      permissions = {}
      permissions["foobar"] = { "contents": "read" }
      config = Codespaces::DevContainerConfig::Codespaces.build(source_repository: nil, errors: nil, all_repository_permissions: nil, unvalidated_permissions: permissions, user: user)

      # read is returned for that repo because user does not have it
      assert_equal "read", config.unknown_repository_permissions["foobar"][:contents]
      permissions["foobar"] = { "contents": "write", "issues": "read" }
      config = Codespaces::DevContainerConfig::Codespaces.build(source_repository: nil, errors: nil, all_repository_permissions: nil, unvalidated_permissions: permissions, user: user)
      assert_equal "write", config.unknown_repository_permissions["foobar"][:contents]
      assert_equal "read", config.unknown_repository_permissions["foobar"][:issues]
    end
  end

  context "passed_checks" do
    test "returns an empty hash if user has all permissions" do
      user = create(:user)
      user_owned_repo = create(:repository, owner: user)

      permissions = {}
      permissions[user_owned_repo.nwo] = { "contents": "read", "issues": "write" }

      # @user totally owns this repository so we should be able to do everything
      config = Codespaces::DevContainerConfig::Codespaces.build(
        source_repository: nil,
        errors: nil,
        all_repository_permissions: nil,
        unvalidated_permissions: permissions,
        user: user
      )

      assert_empty config.unknown_repository_permissions
      assert_equal "read", config.repository_permissions[user_owned_repo][:contents]
      assert_equal "write", config.repository_permissions[user_owned_repo][:issues]
    end
  end

  context "#permissions_need_allowance? and #permissions_accepted?" do

    test "returns true if there are only unknown repos" do
      repo = repo_with_devcontainer do |r|
        <<-JSON5
        {
          "postCreateCommand": "post-create.sh",
          "customizations": {
            "codespaces": {
              "repositories": {
                "#{r.owner.name}/*": {
                  "permissions": {
                    "contents": "foobar",
                  }
                },
              }
            }
          }
        }
        JSON5
      end

      dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner)

      assert dc.permissions_need_allowance?
      refute dc.permissions_accepted?
    end

    test "returns true if there are unconsented repos" do
      repo = repo_with_devcontainer do |r|
        <<-JSON5
        {
          "postCreateCommand": "post-create.sh",
          "customizations": {
            "codespaces": {
              "repositories": {
                "#{r.owner.name}/*": {
                  "permissions": {
                    "contents": "read",
                  }
                },
              }
            }
          }
        }
        JSON5
      end

      dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner)
      assert dc.diff_all_permissions.unconsented.present?
      assert dc.permissions_need_allowance?
      refute dc.permissions_accepted?
    end

    test "returns true if there are revoked repos" do
      repo = repo_with_devcontainer do |_r|
        <<-JSON5
        {
          "postCreateCommand": "post-create.sh",
          "customizations": {
            "codespaces": {
              "repositories": {}
            }
          }
        }
        JSON5
      end
      create(:allowed_permission, user: repo.owner, repository: repo, target: repo, action: :write, resource: :contents)

      dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner)
      refute dc.diff_all_permissions.unconsented.present?
      assert dc.diff_all_permissions.revoked.present?

      assert dc.permissions_need_allowance?
      refute dc.permissions_accepted?
    end

    test "returns true if there are unconsented repos with unknown repo/permission" do
      repo = repo_with_devcontainer do |r|
        <<-JSON5
        {
          "postCreateCommand": "post-create.sh",
          "customizations": {
            "codespaces": {
              "repositories": {
                "#{r.nwo}": {
                  "permissions": {
                    "contents": "read",
                  }
                },
                "#{r.owner.name}/*": {
                  "permissions": {
                    "contents": "foobar",
                  }
                },
              }
            }
          }
        }
        JSON5
      end

      dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner)
      assert dc.diff_all_permissions.unconsented.present?
      assert dc.permissions_need_allowance?
      refute dc.permissions_accepted?
    end

    test "returns true if there are revoked repos with unknown repo/permission" do
      repo = repo_with_devcontainer do |r|
        <<-JSON5
        {
          "postCreateCommand": "post-create.sh",
          "customizations": {
            "codespaces": {
              "repositories": {
                "#{r.owner.name}/*": {
                  "permissions": {
                    "contents": "foobar",
                  }
                }
              }
            }
          }
        }
        JSON5
      end
      create(:allowed_permission, user: repo.owner, repository: repo, target: repo, action: :write, resource: :contents)

      dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner)
      refute dc.diff_all_permissions.unconsented.present?
      assert dc.diff_all_permissions.revoked.present?

      assert dc.permissions_need_allowance?
      refute dc.permissions_accepted?
    end

    test "returns false if there is nothing to accept" do
      repo = repo_with_devcontainer do |_r|
        <<-JSON5
        {
          "postCreateCommand": "post-create.sh",
          "customizations": {
            "codespaces": {
              "repositories": {}
            }
          }
        }
        JSON5
      end

      dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, user: repo.owner)
      refute dc.diff_all_permissions.unconsented.present?
      refute dc.diff_all_permissions.revoked.present?
      refute dc.permissions_need_allowance?
      assert dc.permissions_accepted?
    end
  end

  context "#path" do
    test "returns provided path" do
      repo = repo_with_devcontainer
      dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid, filepath: ".devcontainer/example/devcontainer.json")

      assert_equal dc.filepath, ".devcontainer/example/devcontainer.json"
    end
  end
end
