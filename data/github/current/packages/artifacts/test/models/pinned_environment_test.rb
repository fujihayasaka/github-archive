# typed: true
# frozen_string_literal: true

require "test_helper"

class PinnedEnvironmentTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo_admin = create(:user)
    @writer = create(:user)
    @anon = create(:user)
    @org = create(:organization, admin: @user)
    @repo = create(:repository, owner: @org)
    @repo.add_member(@repo_admin, action: :admin)
    @repo.add_member(@writer, action: :write)

    @environment = create(:environment, repository: @repo)
  end

  setup do
    GitHub.stubs(:actions_enabled?).returns(true)
    Repository.any_instance.stubs(:can_use_environments?).returns(true)
  end

  test "sets position of newly pinned environments" do
    10.times do
      create(:environment, repository: @repo)
    end
    @repo.environments.each do |env|
      @repo.pinned_environments.create(environment: env)
    end

    @repo.pinned_environments.order(:created_at).each_with_index do |env, n|
      assert_equal env.position, n + 1 # 1-indexed position
    end
  end

  test "pins environment as owner" do
    @environment.pin(actor: @user)
    assert @environment.pinned?
  end

  test "pins environment as admin" do
    @environment.pin(actor: @repo_admin)
    assert @environment.pinned?
  end

  test "does not pin environment as writer" do
    @environment.pin(actor: @writer)
    refute @environment.pinned?
  end

  test "does not pin environment as reader" do
    @environment.pin(actor: @anon)
    refute @environment.pinned?
  end

  test "does not pin when limit is reached" do
    environment1 = create(:environment, repository: @repo)
    environment2 = create(:environment, repository: @repo)
    environment3 = create(:environment, repository: @repo)
    environment4 = create(:environment, repository: @repo)
    environment5 = create(:environment, repository: @repo)
    environment6 = create(:environment, repository: @repo)
    environment7 = create(:environment, repository: @repo)
    environment8 = create(:environment, repository: @repo)
    environment9 = create(:environment, repository: @repo)
    environment10 = create(:environment, repository: @repo)

    environment1.pin(actor: @user)
    environment2.pin(actor: @user)
    environment3.pin(actor: @user)
    environment4.pin(actor: @user)
    environment5.pin(actor: @user)
    environment6.pin(actor: @user)
    environment7.pin(actor: @user)
    environment8.pin(actor: @user)
    environment9.pin(actor: @user)
    environment10.pin(actor: @user)

    @environment.pin(actor: @user)
    refute @environment.pinned?
  end

  test "unpins environment as owner" do
    @environment.pin(actor: @user)
    assert @environment.pinned?

    @environment.unpin(actor: @user)
    refute @environment.reload.pinned?
  end

  test "unpins environment as admin" do
    @environment.pin(actor: @user)
    assert @environment.pinned?

    @environment.unpin(actor: @repo_admin)
    refute @environment.reload.pinned?
  end

  test "does not unpin environment as writer" do
    @environment.pin(actor: @user)
    assert @environment.pinned?

    @environment.unpin(actor: @writer)
    assert @environment.reload.pinned?
  end

  test "does not unpin environment as reader" do
    @environment.pin(actor: @user)
    assert @environment.pinned?

    @environment.unpin(actor: @anon)
    assert @environment.reload.pinned?
  end

  context "list environment" do
    test "list pinned environments" do
      environment1 = create(:environment, repository: @repo)
      environment2 = create(:environment, repository: @repo)
      environment3 = create(:environment, repository: @repo)

      environment1.pin(actor: @user)
      environment2.pin(actor: @user)
      environment3.pin(actor: @user)

      assert_equal 3, @repo.pinned_environments.size
    end
  end
end
