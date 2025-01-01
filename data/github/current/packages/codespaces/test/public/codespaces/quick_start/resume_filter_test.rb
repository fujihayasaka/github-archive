# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::QuickStart::ResumeFilterTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repository = create(:repository)
    @other_repository = create(:repository)
  end

  test "returns nothing when explicitly provided no repository" do
    @codespace = build(:codespace, owner: @user, repository: @repository)
    finder = Codespaces::QuickStart::ResumeFilter.new(
      codespaces: [@codespace],
      repository: nil
    )
    refute finder.resumable_codespace
  end

  test "returns nothing when there are no codespaces" do
    @codespace = build(:codespace, owner: @user, repository: @repository)
    finder = Codespaces::QuickStart::ResumeFilter.new(
      codespaces: [],
      repository: nil
    )
    refute finder.resumable_codespace
  end

  test "when given a different repository it finds no results" do
    @codespace = build(:codespace, owner: @user, repository: @repository)
    finder = Codespaces::QuickStart::ResumeFilter.new(
      codespaces: [@codespace],
      repository: @other_repository
    )
    refute finder.resumable_codespace
  end

  test "when given a repository it finds only codespaces from that repository" do
    @codespace = build(:codespace, owner: @user, repository: @repository)
    @other_codespace = build(:codespace, owner: @user, repository: @other_repository)
    finder = Codespaces::QuickStart::ResumeFilter.new(
      codespaces: [@codespace, @other_codespace].shuffle,
      repository: @repository
    )
    assert_equal @codespace, finder.resumable_codespace
  end

  test "it uses the most recently used codespace when multiple are avaialble" do
    @codespace = build(:codespace, owner: @user, repository: @repository)
    @other_codespace = build(:codespace, owner: @user, repository: @repository, last_used_at: 10.minutes.ago)
    finder = Codespaces::QuickStart::ResumeFilter.new(
      codespaces: [@codespace, @other_codespace].shuffle,
      repository: @repository
    )
    assert_equal @codespace, finder.resumable_codespace
  end

  context "when provided with a ref" do
    test "it finds the most recently used codespace on that ref" do
      @codespace = build(:codespace, owner: @user, repository: @repository, last_used_at: 5.minutes.ago, ref: "my-ref")
      @other_codespace = build(:codespace, owner: @user, repository: @repository, last_used_at: 10.minutes.ago, ref: "my-ref")
      @another_codespace = build(:codespace, owner: @user, repository: @repository)
      finder = Codespaces::QuickStart::ResumeFilter.new(
        codespaces: [@codespace, @other_codespace, @another_codespace].shuffle,
        repository: @repository,
        ref: "my-ref"
      )
      assert_equal @codespace, finder.resumable_codespace
    end

    test "it finds the most recently used codespace on the appropriate ref if the ref has changed in the VM" do
      # Initially created on default branch but they checked out my-ref in the VM.
      @codespace = build(:codespace, owner: @user, repository: @repository, last_used_at: 5.minutes.ago, environment_data: { git_status: { branch: "my-ref" } })
      @other_codespace = build(:codespace, owner: @user, repository: @repository, last_used_at: 10.minutes.ago, ref: "my-ref")
      @another_codespace = build(:codespace, owner: @user, repository: @repository)
      finder = Codespaces::QuickStart::ResumeFilter.new(
        codespaces: [@codespace, @other_codespace, @another_codespace].shuffle,
        repository: @repository,
        ref: "my-ref"
      )
      assert_equal @codespace, finder.resumable_codespace
    end
  end

  context "when provided with a pull request" do
    test "it finds the most recently used codespace on that pull request" do
      pull = create(:pull_request, :disable_disk_access, repository: @repository, base_repository: @repository, head_repository: @repository)
      @codespace = build(:codespace, owner: @user, repository: @repository, last_used_at: 5.minutes.ago, pull_request: pull)
      @other_codespace = build(:codespace, owner: @user, repository: @repository, last_used_at: 10.minutes.ago, pull_request: pull)
      @another_codespace = build(:codespace, owner: @user, repository: @repository)
      finder = Codespaces::QuickStart::ResumeFilter.new(
        codespaces: [@codespace, @other_codespace, @another_codespace].shuffle,
        repository: @repository,
        pull_request: pull
      )
      assert_equal @codespace, finder.resumable_codespace
    end

    test "with a fork it looks for codespaces on the pull request's head repository because that's where we would expect them to live" do
      fork = create(:fork_repository, forker: @user, fork_repo: @repository)
      pull = create(:pull_request, :disable_disk_access, repository: @repository, head_repository: fork)
      @codespace = build(:codespace, owner: @user, repository: fork, last_used_at: 5.minutes.ago, pull_request: pull)
      @other_codespace = build(:codespace, owner: @user, repository: fork, last_used_at: 10.minutes.ago, pull_request: pull)
      @another_codespace = build(:codespace, owner: @user, repository: @repository)
      finder = Codespaces::QuickStart::ResumeFilter.new(
        codespaces: [@codespace, @other_codespace, @another_codespace].shuffle,
        repository: @repository,
        pull_request: pull
      )
      assert_equal @codespace, finder.resumable_codespace
    end
  end

  context "when provided a devcontainer_path" do
    test "it finds the most recently used codespace with that devcontainer_path" do
      @codespace = build(:codespace, owner: @user, repository: @repository, last_used_at: 5.minutes.ago, devcontainer_path: ".devcontainer/actions/devcontainer.json")
      @other_codespace = build(:codespace, owner: @user, repository: @repository, last_used_at: 10.minutes.ago, devcontainer_path: ".devcontainer/actions/devcontainer.json")
      @another_codespace = build(:codespace, owner: @user, repository: @repository)
      finder = Codespaces::QuickStart::ResumeFilter.new(
        codespaces: [@codespace, @other_codespace, @another_codespace].shuffle,
        repository: @repository,
        devcontainer_path: ".devcontainer/actions/devcontainer.json"
      )
      assert_equal @codespace, finder.resumable_codespace
    end
  end
end
