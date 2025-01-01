# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryNetworkDependencyTest < GitHub::TestCase
  fixtures do
    @defunkt  = create(:user, login: "defunkt",  plan: "medium")
    @admin    = create(:user, login: "d12")
    @admin_2  = create(:user, login: "iolsen")
    @member   = create(:user, login: "member")
    @mojombo  = create(:user, login: "mojombo2", plan: "medium")

    @business = create(:business)
    @org = create(:organization, business: @business)
    @org.add_admin(@admin)
    @org.add_admin(@admin_2)
    @org.add_member(@member, action: :read)

    @ambition = create(:private_repository, name: "ambition", owner: @defunkt)
    @simple   = create(:repository, name: "simple",   owner: @defunkt)
    @internal = create(:internal_repository, owner: @org)
    @internal.allow_private_repository_forking(actor: @admin)
  end

  context "#fork" do
    test "fork with success" do
      forked_repo, reason, errors = @simple.fork(forker: @mojombo)

      assert forked_repo
      assert_predicate forked_repo, :fork?
      assert reason, :created
      refute errors
    end

    test "use default arguments" do
      forker = create(:user)
      repository = stub
      orchestration = stub(repository: repository)
      orchestration.expects(:valid?).returns(true)
      orchestration.expects(:execute)
      orchestration.stubs(:skipped?).returns(false)
      orchestration.stubs(:failed?).returns(false)

      RepositoryOrchestration.expects(:fork)
        .with(equals({
          parent_repository: @simple,
          actor: forker,
          owner: forker,
          name: nil,
          description: nil,
          one_branch: nil
        }))
        .returns(orchestration)

      result, reason, errors = @simple.fork(forker: forker)

      assert_same repository, result
      assert reason, :created
      refute errors
    end

    test "receive custom owner" do
      owner = create(:user)
      forker = create(:user)
      repository = stub
      orchestration = stub(repository: repository)
      orchestration.expects(:valid?).returns(true)
      orchestration.expects(:execute)
      orchestration.stubs(:skipped?).returns(false)
      orchestration.stubs(:failed?).returns(false)

      RepositoryOrchestration.expects(:fork)
        .with(equals({
          parent_repository: @simple,
          actor: forker,
          owner: owner,
          name: nil,
          description: nil,
          one_branch: nil
        }))
        .returns(orchestration)

      result, reason, errors = @simple.fork(forker: forker, owner: owner)

      assert_same repository, result
      assert reason, :created
      refute errors
    end

    test "receive org and send as owner" do
      org = create(:user)
      forker = create(:user)
      repository = stub
      orchestration = stub(repository: repository)
      orchestration.expects(:valid?).returns(true)
      orchestration.expects(:execute)
      orchestration.stubs(:skipped?).returns(false)
      orchestration.stubs(:failed?).returns(false)

      RepositoryOrchestration.expects(:fork)
        .with(equals({
          parent_repository: @simple,
          actor: forker,
          owner: org,
          name: nil,
          description: nil,
          one_branch: nil
        }))
        .returns(orchestration)

      result, reason, errors = @simple.fork(forker: forker, org: org)

      assert_same repository, result
      assert reason, :created
      refute errors
    end

    test "receive custom new_name, description, and one_branch" do
      name = stub
      description = stub
      one_branch = stub
      forker = create(:user)
      repository = stub
      orchestration = stub(repository: repository)
      orchestration.expects(:valid?).returns(true)
      orchestration.expects(:execute)
      orchestration.stubs(:skipped?).returns(false)
      orchestration.stubs(:failed?).returns(false)

      RepositoryOrchestration.expects(:fork)
        .with(equals({
          parent_repository: @simple,
          actor: forker,
          owner: forker,
          name: name,
          description: description,
          one_branch: one_branch
        }))
        .returns(orchestration)

      result, reason, errors = @simple.fork(
        forker: forker,
        new_name: name,
        description: description,
        one_branch: one_branch
      )

      assert_same repository, result
      assert reason, :created
      refute errors
    end

    test "raise error if orchestration creation fail" do
      RepositoryOrchestration.stubs(:fork).with(anything, anything).raises(StandardError, "boom")
      assert_raises(StandardError, "boom") do
        @simple.fork(forker: @mojombo)
      end
    end

    test "raise error if orchestration execution fails" do
      RepositoryOrchestration.any_instance.stubs(:execute)
        .raises(Orchestration::Error, "boom")

      assert_raises(Orchestration::Error, "boom") do
        @simple.fork(forker: @mojombo)
      end
    end

    test "return :forking reason if orchestration execution error_message is :forking" do
      mutex = GitHub::Redis::Mutex.new("repo-fork-lock:#{@mojombo.id}:#{@simple.network_id}", timeout: 1.minute)
      result = T.let(nil, T.untyped)
      reason = T.let(nil, T.untyped)
      errors = T.let(nil, T.untyped)
      mutex.lock do
        result, reason, errors = @simple.fork(forker: @mojombo)
      end

      refute result
      assert_equal :duplicate_of_existing_fork, reason
      refute errors
    end

    test "return existing_repository when :exists fork_repository_error " do
      fork_repository_error = stub(type: :exists)
      errors = stub
      errors.stubs(:where).with(:fork_repository).returns([fork_repository_error])
      existing_repository = create(:repository)
      orchestration = stub(errors: errors, existing_repository: existing_repository)
      orchestration.stubs(:valid?).returns(false)

      RepositoryOrchestration.stubs(:fork)
        .with(anything, anything)
        .returns(orchestration)

      result, reason, errors  = @simple.fork(forker: @mojombo)

      assert_same result, existing_repository
      assert_equal :exists, reason
      refute errors
    end

    test "return fork_repository error reason with no errors" do
      fork_repository_error = stub(type: :reason)
      errors = stub
      errors.stubs(:where).with(:fork_repository).returns([fork_repository_error])
      existing_repository = create(:repository)
      orchestration = stub(errors: errors, fork_repository_errors: nil)
      orchestration.stubs(:valid?).returns(false)

      RepositoryOrchestration.stubs(:fork)
        .with(anything, anything)
        .returns(orchestration)

      result, reason, errors = @simple.fork(forker: @mojombo)

      refute result
      refute errors
      assert_equal :reason, reason
    end

    test "return reason and errors" do
      fork_repository_error = stub(type: :reason)
      errors = stub
      errors.stubs(:where).with(:fork_repository).returns([fork_repository_error])
      existing_repository = create(:repository)
      fork_repository_errors = stub
      orchestration = stub(errors: errors, fork_repository_errors: fork_repository_errors)
      orchestration.stubs(:valid?).returns(false)

      RepositoryOrchestration.stubs(:fork)
        .with(anything, anything)
        .returns(orchestration)

      result, reason, errors = @simple.fork(forker: @mojombo)

      refute result
      assert_equal :reason, reason
      assert_same fork_repository_errors, errors
    end

  end

  context "#internal_fork?" do
    test "returns false if not a fork" do
      refute @simple.fork?
      refute @simple.internal_fork?
    end

    test "returns false if a fork of a public repo" do
      assert @simple.public?

      forked_repo = create(:fork_repository, forker: @defunkt, fork_repo: @simple)
      assert forked_repo.public?

      refute forked_repo.internal_fork?
    end

    test "returns false if a fork of a private repo" do
      assert @ambition.private?

      forked_repo = create(:fork_repository, forker: @defunkt, fork_repo: @ambition)
      assert forked_repo.private?

      refute forked_repo.internal_fork?
    end

    test "returns true if a fork of an internal repo" do
      # Fork permission logic coming in a later PR. Stub this for now, we aren't
      # testing the permissions here.
      User.any_instance.stubs(:can_fork?).returns(true)

      assert_equal Repository::INTERNAL_VISIBILITY, @internal.visibility

      forked_repo = create(:fork_repository, forker: @admin, fork_repo: @internal)
      assert forked_repo.private?
      assert_equal Repository::PRIVATE_VISIBILITY, forked_repo.visibility

      assert forked_repo.internal_fork?
    end
  end

  test "knows about forks" do
    @ambition.add_member(@mojombo)
    fork = create(:fork_repository, forker: @mojombo, fork_repo: @ambition)
    assert fork.fork?
  end

  test "don't ensure uniqueness of intra-org fork" do

    org_admin = create(:user, login: "org-admin")
    org = create(:organization, admin: org_admin, plan: "bronze", business: GitHub.global_business)
    org.allow_private_repository_forking(actor: org.admins.first)
    repo = create(:private_repository, owner: org)
    forked, result = repo.fork(forker: org_admin, org: org)
    assert_equal :created, result
    assert_equal 2, org.repositories.size
    assert repo.ensure_uniqueness_of_fork_in_network
  end

  context "#calculate_network_counts!" do
    # Getting in this state is rare but we think it's due to ownership transfer. Until we 100% prevent this we
    # need to handle it gracefully
    # https://github.com/github/repos/issues/7704
    test "cyclical network doesn't cause infinite loop when calculating public fork counts" do
      forker = create(:user)
      repo = create(:public_repository)
      forked = create(:fork_repository, forker: forker, fork_repo: repo)
      forked2 = create(:fork_repository, forker: create(:user), fork_repo: forked)
      forked3 = create(:fork_repository, forker: create(:user), fork_repo: forked)
      forked.parent = forked3
      forked.save

      forked3.calculate_network_counts!
    end
  end
end
