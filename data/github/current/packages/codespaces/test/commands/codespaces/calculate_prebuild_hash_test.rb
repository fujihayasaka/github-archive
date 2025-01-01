# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::CalculatePrebuildHashTest < GitHub::TestCase
  test "is deterministic" do
    repository = create_base_repository
    oid = repository.refs.find("master").sha

    hash1 = Codespaces::CalculatePrebuildHash.call(repository: repository, oid: oid)
    refute_nil hash1

    hash2 = Codespaces::CalculatePrebuildHash.call(repository: repository, oid: oid)
    assert_equal hash1, hash2
  end

  test "returns the OID when there is no devcontainer.json" do
    repository = create(:repository, from_example: :simple)
    oid = repository.refs.find("master").sha
    assert_equal oid, Codespaces::CalculatePrebuildHash.call(repository: repository, oid: oid)
  end

  test "parsing garbage JSON" do
    repository = create_base_repository
    devcontainer_json = <<-JSON5
      this is not even JSON!
    JSON5

    repository.refs.find("master").append_commit({ message: "changes", committer: repository.owner }, repository.owner) do |files|
      files.add(".devcontainer/devcontainer.json", devcontainer_json)
    end

    oid = repository.refs.find("master").sha
    hash = Codespaces::CalculatePrebuildHash.call(repository: repository, oid: oid)
    assert_equal oid, hash
  end

  context "devcontainer.json" do
    test "it varies with changes" do
      assert_prebuild_hash_changed do |files|
        devcontainer_json = <<-JSON5
          {
            "postCreateCommand": "post-create.sh",
          }
        JSON5
        files.add(".devcontainer/devcontainer.json", devcontainer_json)
      end

      assert_prebuild_hash_changed do |files|
        files.remove(".devcontainer/devcontainer.json")
      end

      repository = create_base_repository

      repository.refs.find("master").append_commit({ message: "changes", committer: repository.owner }, repository.owner) do |files|
        files.add(".devcontainer/foobar/devcontainer.json", '{"postCreateCommand": "post-create.sh"}')
      end

      hash1 = Codespaces::CalculatePrebuildHash.call(repository: repository, oid: repository.refs.find("master").sha, devcontainer_path: ".devcontainer/foobar/devcontainer.json")
      refute_nil hash1

      repository.refs.find("master").append_commit({ message: "changes", committer: repository.owner }, repository.owner) do |files|
        files.remove(".devcontainer/foobar/devcontainer.json")
      end

      hash2 = Codespaces::CalculatePrebuildHash.call(repository: repository, oid: repository.refs.find("master").sha)
      refute_equal hash1, hash2
    end
  end

  context "postCreateCommand" do
    test "it varies with changes" do
      assert_prebuild_hash_changed do |files|
        files.add("post-create.sh", "#!/usr/bin/env ruby")
      end

      assert_prebuild_hash_changed do |files|
        files.remove("post-create.sh")
      end
    end

    test "it works without it" do
      repository = create_base_repository
      devcontainer_json = <<-JSON5
        {
          "prebuildHashPaths": "other-file.txt",
        }
      JSON5

      repository.refs.find("master").append_commit({ message: "changes", committer: repository.owner }, repository.owner) do |files|
        files.add(".devcontainer/devcontainer.json", devcontainer_json)
      end

      hash = Codespaces::CalculatePrebuildHash.call(repository: repository, oid: repository.refs.find("master").sha)
      refute_nil hash
    end

    test "it works with inline commands" do
      repository = create_base_repository
      devcontainer_json = <<-JSON5
        {
          "postCreateCommand": "/bin/sh ls",
        }
      JSON5

      repository.refs.find("master").append_commit({ message: "changes", committer: repository.owner }, repository.owner) do |files|
        files.add(".devcontainer/devcontainer.json", devcontainer_json)
      end

      hash = Codespaces::CalculatePrebuildHash.call(repository: repository, oid: repository.refs.find("master").sha)
      refute_nil hash
    end
  end

  context "onCreateCommand" do
    test "it varies with changes" do
      assert_prebuild_hash_changed do |files|
        files.add("on-create-command.sh", "#!/usr/bin/env ruby")
      end

      assert_prebuild_hash_changed do |files|
        files.remove("on-create-command.sh")
      end
    end

    test "it works without it" do
      repository = create_base_repository
      devcontainer_json = <<-JSON5
        {
          "prebuildHashPaths": "other-file.txt",
        }
      JSON5

      repository.refs.find("master").append_commit({ message: "changes", committer: repository.owner }, repository.owner) do |files|
        files.add(".devcontainer/devcontainer.json", devcontainer_json)
      end

      hash = Codespaces::CalculatePrebuildHash.call(repository: repository, oid: repository.refs.find("master").sha)
      refute_nil hash
    end
  end

  context "prebuildHashPaths" do
    test "it varies with changes" do
      assert_prebuild_hash_changed do |files|
        files.add("other-file.txt", "this changed!")
      end

      assert_prebuild_hash_changed do |files|
        files.remove("other-file.txt")
      end
    end

    test "it can match multiple files" do
      repository = create_base_repository
      devcontainer_json = <<-JSON5
        {
          "prebuildHashPaths": [
            "other-file.txt",
            "neato-file.txt",
          ],
        }
      JSON5

      repository.refs.find("master").append_commit({ message: "changes", committer: repository.owner }, repository.owner) do |files|
        files.add(".devcontainer/devcontainer.json", devcontainer_json)
        files.add("neato-file.txt", "")
      end

      assert_prebuild_hash_changed(repository: repository) do |files|
        files.add("neato-file.txt", "this changed!")
      end
    end

    test "it can match directories" do
      repository = create_base_repository
      devcontainer_json = <<-JSON5
        {
          "prebuildHashPaths": "my-dir",
        }
      JSON5

      repository.refs.find("master").append_commit({ message: "changes", committer: repository.owner }, repository.owner) do |files|
        files.add(".devcontainer/devcontainer.json", devcontainer_json)
        files.add("my-dir/neato-file.txt", "")
        files.add("my-dir/other-file.txt", "")
      end

      assert_prebuild_hash_changed(repository: repository) do |files|
        files.add("my-dir/neato-file.txt", "this changed!")
      end

      assert_prebuild_hash_changed(repository: repository) do |files|
        files.add("my-dir/other-file.txt", "this changed too!")
      end
    end

    test "it works without it" do
      repository = create_base_repository
      devcontainer_json = <<-JSON5
        {
          "postCreateCommand": "post-create.sh",
        }
      JSON5

      repository.refs.find("master").append_commit({ message: "changes", committer: repository.owner }, repository.owner) do |files|
        files.add(".devcontainer/devcontainer.json", devcontainer_json)
      end

      hash = Codespaces::CalculatePrebuildHash.call(repository: repository, oid: repository.refs.find("master").sha)
      refute_nil hash

      head_ref = repository.heads.create("patch-1", repository.heads.find_or_build("master").target, repository.owner)
      head_ref.append_commit({ message: "some changes", committer: repository.owner }, repository.owner) do |files|
        files.add ".devcontainer/bazbar/devcontainer.json", <<-JSON5
          {
            "postCreateCommand": "something-else.sh",
          }
        JSON5
      end

      base_hash = Codespaces::CalculatePrebuildHash.call(repository: repository, oid: head_ref.sha)
      refute_nil base_hash

      with_devcontainer_hash = Codespaces::CalculatePrebuildHash.call(repository: repository, oid: head_ref.sha, devcontainer_path: ".devcontainer/bazbar/devcontainer.json")
      refute_nil with_devcontainer_hash

      assert base_hash != with_devcontainer_hash
    end

    test "hash changes when build.dockerfile file changes" do
      repository = create_base_repository
      devcontainer_json = <<-JSON5
        {
          "build": {
            "dockerfile": "Dockerfile"
          }
        }
      JSON5

      repository.refs.find("master").append_commit({ message: "changes", committer: repository.owner }, repository.owner) do |files|
        files.add(".devcontainer/devcontainer.json", devcontainer_json)
      end

      assert_prebuild_hash_changed(repository: repository) do |files|
        files.add(".devcontainer/Dockerfile", "this changed!")
      end

      assert_prebuild_hash_changed(repository: repository) do |files|
        files.add(".devcontainer/Dockerfile", "another change")
      end
    end
  end

  Codespaces::CalculatePrebuildHash::HASHED_FILES.each do |file|
    context "hashing #{file}" do
      test "it varies with changes" do
        assert_prebuild_hash_changed do |files|
          files.add(file, "changed!")
        end

        assert_prebuild_hash_changed do |files|
          files.remove(file)
        end
      end
    end
  end

  def assert_prebuild_hash_changed(repository: create_base_repository)
    hash1 = Codespaces::CalculatePrebuildHash.call(repository: repository, oid: repository.refs.find("master").sha)
    refute_nil hash1

    repository.refs.find("master").append_commit({ message: "changes", committer: repository.owner }, repository.owner) do |files|
      yield(files)
    end

    hash2 = Codespaces::CalculatePrebuildHash.call(repository: repository, oid: repository.refs.find("master").sha)
    refute_equal hash1, hash2
  end

  def create_base_repository
    repository = create(:repository, from_example: :simple)
    devcontainer_json = <<-JSON5
      {
        "postCreateCommand": "post-create.sh",
        /*
          Multi
          Line
          Comment
        */
        "prebuildHashPaths": "other-file.txt",
        "onCreateCommand": "on-create-command.sh", // Single line comment and note the trailing comma
      }
    JSON5

    repository.refs.find("master").append_commit({ message: "First!", committer: repository.owner }, repository.owner) do |files|
      files.add(".devcontainer/devcontainer.json", devcontainer_json)
      files.add("post-create.sh", "#!/bin/sh")
      files.add("on-create-command.sh", "#!/bin/sh")
      files.add("other-file.txt", "")
      files.add(".devcontainer/Dockerfile", "FROM ubuntu")
      Codespaces::CalculatePrebuildHash::HASHED_FILES.each do |file|
        files.add(file, "")
      end
    end
    repository
  end
end
