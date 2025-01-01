# typed: true
# frozen_string_literal: true

require "test_helper"

class ForkRepositoryOrchestrationTest < GitHub::TestCase
  include HydroTestHelpers
  include DogstatsTestHelpers
  include HydroMessageJobTestHelpers

  fixtures do
    @forker = create(:user)
    @upstream_owner = create(:user)
    @upstream = create(:repository, owner: @upstream_owner, from_example: :simple)
    @upstream2 = create(:repository, owner: @upstream_owner, from_example: :simple)
    @private_upstream_owner = create(:user, plan: "medium")
    @private_upstream = create(:private_repository, name: "private_upstream", owner: @private_upstream_owner, from_example: :simple)

    @spammer1 = create(:user)
    @spammer2 = create(:user)
    @spammer3 = create(:user)
    @spammer4 = create(:user)
    @spammer5 = create(:user)
    @spammer6 = create(:user)
  end

  setup do
    disable_feature_flag(:discard_stratocaster_fanout)
    reset_repo_root
    example_repo :forkable, @upstream
    example_repo :defunkt_ambition, @private_upstream
  end

  def start_fork(repo, forker)
    o = RepositoryOrchestration.fork(parent_repository: repo, actor: forker, owner: forker)
    o.execute
    o
  end

  context "too many requests" do
    test "return 429" do
      GitHub.flipper[:fork_max_active_count].enable_percentage_of_time(2.0)
      o1 = start_fork(@upstream, @spammer1)
      assert_equal "running", o1.state
      assert_dogstats_distribution(0, "repo.fork_orchestration.concurrency_count")

      o2 = start_fork(@upstream, @spammer2)
      assert_equal "running", o2.state
      assert_dogstats_distribution(1, "repo.fork_orchestration.concurrency_count")
      assert_equal 1, assert_dogstats_distribution(1, "repo.fork_orchestration.concurrency_count")[0].value

      o3 = start_fork(@upstream, @spammer3)
      assert_equal :too_many_requests, o3.errors.first.type
      assert_equal "Too many requests. Please try again later.", o3.errors.first.options[:message]
      assert_nil o3.id
      assert_dogstats_distribution(2, "repo.fork_orchestration.concurrency_count")
      assert_equal 2, assert_dogstats_distribution(2, "repo.fork_orchestration.concurrency_count")[1].value

      # now fork a different repo
      o4 = start_fork(@upstream2, @spammer2)
      assert_equal "running", o4.state
      assert_dogstats_distribution(2, "repo.fork_orchestration.concurrency_count")

      o5 = start_fork(@upstream2, @spammer3)
      assert_equal "running", o5.state
      assert_dogstats_distribution(3, "repo.fork_orchestration.concurrency_count")
      assert_equal 1, assert_dogstats_distribution(3, "repo.fork_orchestration.concurrency_count")[2].value

      o6 = start_fork(@upstream2, @spammer1)
      assert_equal :too_many_requests, o6.errors.first.type
      assert_equal "Too many requests. Please try again later.", o6.errors.first.options[:message]
      assert_nil o6.id
      assert_dogstats_distribution(4, "repo.fork_orchestration.concurrency_count")
      assert_equal 2, assert_dogstats_distribution(4, "repo.fork_orchestration.concurrency_count")[3].value

      # finish o1 so there's only 1 in flight, to let spammer fork @upstream
      o1.execute
      o3 = start_fork(@upstream, @spammer3)
      assert_equal "running", o3.state
      assert_dogstats_distribution(5, "repo.fork_orchestration.concurrency_count")
      assert_equal 1, assert_dogstats_distribution(5, "repo.fork_orchestration.concurrency_count")[4].value
    end
  end

  test "it succeeds" do
    orchestration = RepositoryOrchestration.fork(
      parent_repository: @upstream,
      actor: @forker,
      owner: @forker,
    )

    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
      orchestration.execute
    end

    orchestration.reload

    assert_equal :succeeded, orchestration.state.to_sym
  end

  test "do not copy parent.updated_at" do
    @upstream.update!(updated_at: 90.days.ago)

    orchestration = RepositoryOrchestration.fork(
      parent_repository: @upstream,
      actor: @forker,
      owner: @forker,
    )

    ForkRepositoryOrchestration.stop_after_step = :create_fork

    orchestration.execute

    assert orchestration.repository
    assert T.must(orchestration.repository&.updated_at) > @upstream.updated_at
  end

  test "refuses to retry orchestration on create_fork step" do
    orchestration = RepositoryOrchestration.fork(
      parent_repository: @upstream,
      actor: @forker,
      owner: @forker
    )

    orchestration = orchestration.class.find(orchestration.id)
    orchestration.execute

    assert_equal :skipped, orchestration.state.to_sym
    assert_equal "Failed to build fork.", orchestration.error_message
    assert_nil orchestration.repository
  end

  test "retries orchestration steps when max_attempts is greater than 1 and create_fork fails then succeeds" do
    Repository.any_instance.stubs(:save!).raises(ActiveRecord::ConnectionFailed.new).then.returns(true)
    perform_fork_orchestration do |forked_repo, orchestration|
      assert_equal :succeeded, orchestration.state.to_sym
      assert forked_repo.persisted?
      assert forked_repo.exists_on_disk?
      assert_dogstats_increment(1, "repository_orchestration.step.error", tags: ["step:create_fork"])
      assert_dogstats_increment(1, "repository_orchestration.step.retry", tags: ["step:create_fork"])
    end
  end

  test "retries orchestration steps up to max_attempts when create_fork fails then succeeds" do
    orchestration = RepositoryOrchestration.fork(
      parent_repository: @upstream,
      actor: @forker,
      owner: @forker
    )
    Repository.any_instance.stubs(:save!).raises(ActiveRecord::ConnectionFailed.new)
    assert_raises ActiveRecord::ConnectionFailed do
      orchestration.execute
    end

    assert_equal :failed, orchestration.state.to_sym
    assert_nil orchestration.repository
    assert_dogstats_increment(2, "repository_orchestration.step.error", tags: ["step:create_fork"])
    assert_dogstats_increment(1, "repository_orchestration.step.retry", tags: ["step:create_fork"])
  end

  test "deletes git file system if replicas are missing" do
    orchestration = RepositoryOrchestration.fork(
      parent_repository: @upstream,
      actor: @forker,
      owner: @forker
    )

    # start the orchestration
    orchestration.execute

    # simulate a clone_fork failure
    orchestration.repository.stubs(:exists_on_disk?).returns(true)
    orchestration.repository&.rpc.stubs(:all_replicas_exist?).returns(false)

    # orchestration should delete the broken git file system
    orchestration.repository&.rpc.expects(:remove).once

    # finish the orchestration
    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
      orchestration.execute
    end

    assert_equal :succeeded, orchestration.state.to_sym
  end

  test "doesn't fail if Orchestration#data is too long" do
    max_repo_name = "a" * 100
    max_repo_form_description = ("a" * 20_035)

    orchestration = RepositoryOrchestration.fork(
      parent_repository: @upstream,
      actor: @forker,
      owner: @forker,
      name: max_repo_name,
      description: max_repo_form_description + ("b" * 50_000),
    )

    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
      orchestration.execute
    end

    orchestration.reload

    assert_equal :succeeded, orchestration.state.to_sym
  end

  test "doesn't fail if repo description is non-utf8" do
    bad_repo_form_description = "test \xC0\xAFrepo description"

    orchestration = RepositoryOrchestration.fork(
      parent_repository: @upstream,
      actor: @forker,
      owner: @forker,
      description: bad_repo_form_description,
    )

    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
      orchestration.execute
    end

    orchestration.reload

    assert_equal :succeeded, orchestration.state.to_sym
  end

  test "should publish Created event" do
    with_hydro_publisher(GitHub.sync_hydro_publisher) do
      orchestration = RepositoryOrchestration.fork(
        parent_repository: @upstream,
        actor: @forker,
        owner: @forker,
      )

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        orchestration.execute
      end

      orchestration.reload

      assert_equal :succeeded, orchestration.state.to_sym

      assert_hydro_messages(count: 1, schema: "github.repositories.v1.Created")

      message = RepositoryOrchestration.build_hydro_event_message(orchestration.repository_id).merge({
        repository: Hydro::EntitySerializer.repository(orchestration.repository),
        actor_id: @forker.id
      })

      assert_hydro_published(message, schema: "github.repositories.v1.Created")
    end
  end

  test "initializes new repo with git daemon serving and template" do
    perform_fork_orchestration do |forked_repo|
      assert File.directory?(forked_repo.shard_path)
      assert_equal %w(92f71b21f9625f538407e04cdbaa4a554aa304d2), forked_repo.revision_list(forked_repo.ref_to_sha("master"))
      assert_repo_exists   forked_repo
      assert_repo_chmodded forked_repo
      if GitHub.enterprise?
        assert_repo_hooks_symlink forked_repo
      else
        assert_no_repo_hooks_symlink forked_repo
      end
      assert_equal "ref: refs/heads/master\n", IO.read(File.join(forked_repo.shard_path, "HEAD"))
    end
  end

  test "changes default branch on fork to match parent" do
    ref = @upstream.heads.create("booya", "92f71b21f9625f538407e04cdbaa4a554aa304d2", @upstream_owner)
    @upstream.update_attribute :default_branch, "booya"

    perform_fork_orchestration do |forked_repo|
      assert File.directory?(forked_repo.shard_path)
      assert_equal %w(92f71b21f9625f538407e04cdbaa4a554aa304d2), forked_repo.revision_list(forked_repo.ref_to_sha("master"))
      assert_repo_exists forked_repo
      assert_equal "ref: refs/heads/booya\n", IO.read(File.join(forked_repo.shard_path, "HEAD"))
    end
  end

  test "creates network repository and fetches root repo and fork" do
    assert !@upstream.network.shared_storage_enabled?
    perform_fork_orchestration do |forked_repo|
      assert @upstream.network.shared_storage_enabled?
      assert @upstream.shared_storage_enabled?
      assert forked_repo.shared_storage_enabled?
    end
  end

  test "enables alternates in the source repository and the fork" do
    assert !@upstream.shared_storage_enabled?
    perform_fork_orchestration do |forked_repo|
      assert @upstream.shared_storage_enabled?
      assert forked_repo.shared_storage_enabled?
    end
  end

  test "forks all branches when false is passed" do
    multi_branch_repo = create(:repository, from_example: :simple)
    assert_equal 5, multi_branch_repo.refs.count
    perform_fork_orchestration(repo: multi_branch_repo, one_branch: false) do |forked_repo|
      assert_equal 5, forked_repo.refs.count
    end
  end

  test "forks one branch when true is passed" do
    multi_branch_repo = create(:repository, from_example: :simple)
    assert_equal 5, multi_branch_repo.refs.count
    perform_fork_orchestration(repo: multi_branch_repo, one_branch: true) do |forked_repo|
      assert_equal 1, forked_repo.refs.count
    end
  end

  test "can fork a repo with name & description" do
    assert_difference "Repository.count" do
      perform_fork_orchestration(name: "MyTest", description: "Test") do |forked_repo|
        assert_equal @upstream, forked_repo.parent
        assert_equal @upstream, forked_repo.root
        assert_equal @forker, forked_repo.created_by
        assert_equal "MyTest", forked_repo.name
        assert_equal "Test", forked_repo.description
      end
    end
  end

  test "can fork a repo when same named repo already exists" do
    create(:repository, owner: @forker, name: @upstream.name)

    perform_fork_orchestration do |forked_repo|
      assert_equal 2, @forker.repositories.size
      assert_equal @upstream, forked_repo.parent
      assert_equal @upstream, forked_repo.root
      assert_equal "#{@upstream.name}-1", forked_repo.name
    end
  end

  test "can peform an intra-org public fork" do
    org_admin = create(:user, login: "org-admin")
    org = create(:organization, admin: org_admin, plan: "bronze", business: GitHub.global_business)
    org.allow_private_repository_forking(actor: org.admins.first)
    repo = create :repository, owner: org
    perform_fork_orchestration(repo: repo, forker: org_admin, owner: org) do |forked_repo|
      assert_equal 2, org.repositories.size
      assert forked_repo.public?
    end
  end

  test "can peform an intra-org private fork" do
    org_admin = create(:user, login: "org-admin")
    org = create(:organization, admin: org_admin, plan: "bronze", business: GitHub.global_business)
    org.allow_private_repository_forking(actor: org.admins.first)
    repo = create(:private_repository, owner: org)
    perform_fork_orchestration(repo: repo, forker: org_admin, owner: org) do |forked_repo|
      assert_equal 2, org.repositories.size
      assert forked_repo.private?
    end
  end

  test "can peform an internal intra-org fork" do
    org_admin = create(:user, login: "org-admin")
    business_org = create(:organization, admin: org_admin, plan: "bronze", business: GitHub.global_business)
    business_org.allow_private_repository_forking(actor: business_org.admin)
    business = business_org.business || create(:business)
    business.add_organization(business_org)
    business_org.reload

    rando_org = create(:organization)
    rando_org.add_admin(business_org.admin)

    internal_repo = create(:internal_repository, name: "internal", owner: business_org)

    perform_fork_orchestration(repo: internal_repo, forker: org_admin, owner: business_org) do |forked_repo|
      assert_equal 2, business_org.repositories.size
      assert forked_repo.internal?
    end
  end

  test "forker should have admin access to the fork if forking to the same org" do
    org_admin = create(:user)
    org_member = create(:user)
    org = create(:organization, admin: org_admin)
    org.add_member(org_member)
    org.allow_private_repository_forking(actor: org.admin)

    repo = create(:private_repository, owner: org)

    perform_fork_orchestration(repo: repo, forker: org_member, owner: org) do |forked_repo|
      assert forked_repo.adminable_by?(org_member)
    end
  end

  test "fork returns false if trying to fork internal repo to a non enterprise org" do
    business = create(:business)
    business_org = create(:organization, business: business)
    business.add_organization(business_org)
    business_org.allow_private_repository_forking(actor: business_org.admin)

    rando_org = create(:organization)
    rando_org.add_admin(business_org.admin)

    internal_repo = create(:internal_repository, name: "internal", owner: business_org)

    perform_fork_orchestration(
      repo: internal_repo,
      forker: business_org.admin,
      owner: rando_org
    ) do |_, _, reason|
      assert_equal :policy, reason
    end
  end

  test "publishes a Hydro event with is_fork set to true" do
    schema = "github.v1.RepositoryCreate"
    owner = create(:user)
    create(:repository, :full_creation, name: "grit", owner: owner)

    assert_hydro_messages(count: 1, schema: schema)

    found = hydro_messages(schema: schema)
    found_repo = found.first[:repository]
    refute found_repo[:is_fork]

    reset_hydro

    perform_fork_orchestration

    assert_hydro_messages(count: 1, schema: schema)

    found = hydro_messages(schema: schema)
    found_repo = found.first[:repository]

    assert found_repo[:is_fork]
  end

  test "fork returns false if trying to fork a fork of an internal repo" do
    # Create an Org and Turn on Forking
    _, business_org, _ = apply_policy(Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)

    # Add the Admin to Another Org
    rando_org = create(:organization)
    rando_org.add_admin(business_org.admin)

    # Create an internal repo
    internal_repo = create(:internal_repository, name: "internal", owner: business_org)

    # Fork the internal repo to the Admin User
    perform_fork_orchestration(repo: internal_repo, forker: business_org.admin) do |forked_repo|
      assert forked_repo

      # Attempt to fork the fork to the other Org
      perform_fork_orchestration(repo: forked_repo, forker: business_org.admin, owner: rando_org) do |_, _, reason|
        # Should fail since forking a fork of an internal repo is not allowed
        assert_equal :fork_of_internal, reason
      end
    end
  end

  test "fork returns true if trying to fork a fork of a public repo" do
    business = create(:business)
    business_org = create(:organization, business: business)
    business.add_organization(business_org)

    business.allow_private_repository_forking(actor: business_org.admin)

    # Add the Admin to Another Org
    rando_org = create(:organization)
    rando_org.add_admin(business_org.admin)

    # Create a public repo
    public_repo = create(:public_repository, name: "public", owner: business_org)

    # Fork the public repo to the Admin User
    perform_fork_orchestration(repo: public_repo, forker: business_org.admin) do |forked_repo|
      assert forked_repo

      # Attempt to fork the fork to the other Org
      perform_fork_orchestration(repo: forked_repo, forker: business_org.admin, owner: rando_org) do |other_forked_repo|
        # Should succeed since forking a fork of a public repo is allowed
        assert other_forked_repo
      end
    end
  end

  test "fork returns false if repository creation returns nil" do
    # don't love this, but it's good to at least test this actual behavior
    mutex = GitHub::Redis::Mutex.new("repo-fork-lock:#{@forker.id}:#{@upstream.network_id}", timeout: 1.minute)
    orchestration = build_fork_orchestration
    mutex.lock do
      orchestration.execute
    end
    assert_equal "duplicate_of_existing_fork", orchestration.error_message
    assert_equal "skipped", orchestration.state
  end

  test "skips orchestration if name already exists with database validation" do
    repo = create(:public_repository)
    orchestration = build_fork_orchestration(repo: repo)
    ForkRepositoryOrchestration.stop_after_step = :initialize_replicas
    orchestration.execute

    fork = orchestration.repository
    duplicate = create(:repository, name: fork.name, owner: fork.owner)

    orchestration.execute

    orchestration.reload
    assert_equal "skipped", orchestration.state
    assert_equal :duplicate_of_existing_fork, orchestration.error_message.to_sym
    assert_nil fork.reload.active
  end

  test "skips orchestration if name already exists with model validation" do
    repo = create(:public_repository)
    orchestration = build_fork_orchestration(repo: repo)

    duplicate = create(:repository, name: repo.name, owner: @forker)

    orchestration.execute

    orchestration = ForkRepositoryOrchestration.find(orchestration.id)
    assert_equal "skipped", orchestration.state
    assert_equal :duplicate_of_existing_fork, T.must(orchestration.error_message).to_sym
    assert_nil orchestration.repository
  end

  test "fork returns false if forked repository is invalid" do
    Repository.any_instance.stubs(:valid?).returns(false)
    perform_fork_orchestration do |_, _, reason|
      assert_equal :invalid, reason
    end
  end

  test "does not fork the wiki as well" do
    @upstream.initialize_wiki(@upstream.owner)
    wiki = @upstream.unsullied_wiki

    example_repo :wiki, wiki

    perform_fork_orchestration do |forked_repo|
      refute forked_repo.unsullied_wiki.exist?, "forking a repo with a wiki is expected to not fork its wiki"
    end
  end

  test "does not fork the wiki when it is not enabled" do
    @upstream.initialize_wiki(@upstream_owner)
    wiki = @upstream.unsullied_wiki

    example_repo :wiki, wiki

    perform_fork_orchestration do |forked_repo|
      refute forked_repo.unsullied_wiki.exist?, "disabling the wiki means it does not get forked."
    end
  end

  test "restricts writes on the new repository's wiki to collaborators" do
    @upstream.wiki_access_to_pushers = false

    perform_fork_orchestration do |forked_repo|
      assert forked_repo.wiki_access_to_pushers?
    end
  end

  test "disables issues on the forked repository" do
    assert @upstream.has_issues?

    perform_fork_orchestration do |forked_repo|
      refute forked_repo.has_issues?
    end
  end

  test "fork returns false if repository we're forking from is locked" do
    @upstream.lock_for_billing
    perform_fork_orchestration do |_, _, reason|
      assert_equal :locked, reason
    end
  end

  test "fork returns false if owner is over repository limit" do
    if GitHub.single_or_multi_tenant_enterprise?
      apply_policy(Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)
    end

    create_list(:private_repository, 2, owner: @forker, force_user_owned: true)
    count = Repository.where(owner_id: @forker.id).count
    limiter = RepositoryLimit.new(@forker)
    limiter.override(soft: count - 1, hard: count)

    perform_fork_orchestration do |_, _, reason|
      if limiter.enabled?
        assert_equal :limited, reason
      else
        assert_nil reason
      end
    end
  end

  test "untouched fork" do
    # The pushed_at field will be copied to the forked repo, we need to set it to
    # something older so that the forked repo will be considered untouched.
    # Otherwise, the forked repo might be considered touched because the
    # the difference among created_at and pushed_at is ms level.
    @upstream.pushed_at = 1.minute.ago
    @upstream.save!

    perform_fork_orchestration do |forked_repo|
      forked_repo.reload

      refute @upstream.untouched_fork?
      assert forked_repo.untouched_fork?

      metadata = { message: "blah", committer: forked_repo.owner }

      perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
        forked_repo.heads.find("master").append_commit(metadata, forked_repo.owner) {}
      end

      forked_repo.reload
      refute forked_repo.untouched_fork?
    end
  end

  test "source is maintained in nested forks" do
    someone = create(:user)
    perform_fork_orchestration(forker: someone)
    assert_difference "Repository.count" do
      perform_fork_orchestration
    end

    assert_equal 1, @forker.repositories.size

    assert_equal @upstream, @forker.repositories.first.parent
    assert_equal @upstream, @forker.repositories.first.root
  end

  test "can find all parents" do
    someone = create(:user)

    perform_fork_orchestration(forker: someone) do |forked_repo|

      assert_difference "Repository.count" do
        perform_fork_orchestration(repo: forked_repo) do |forked_repo2|
          assert_equal 2, forked_repo2.parents.size
          assert_equal [forked_repo, @upstream], forked_repo2.parents
        end
      end
    end
  end

  test "forking creates an event" do
    event_key = "repo:#{@upstream.id}"
    GitHub.stratocaster.clear_timelines(event_key)

    assert_equal 0, GitHub.stratocaster.events(event_key).size
    only = [ProcessEventJob, UpdateEventFeedsJob]
    forked_repo = perform_fork_orchestration(jobs: only)
    assert_equal 1, (events = GitHub.stratocaster.events(event_key)).size
    assert_equal "ForkEvent", events.first.event_type
  end

  test "forking doesnt copy created at" do
    perform_fork_orchestration do |forked_repo|
      assert forked_repo.created_at > @upstream.created_at
    end
  end

  test "forking doesn't star the parent" do
    perform_fork_orchestration
    refute_includes @forker.reload.starred_repositories, @upstream
  end

  test "forking retains the default branch" do
    new_default = "diverge"
    grit = create(:repository, from_example: :mojombo_grit)
    grit.update_default_branch(new_default)
    assert_equal new_default, grit.default_branch

    perform_fork_orchestration(repo: grit) do |forked_repo|
      assert_equal new_default, forked_repo.default_branch
    end
  end

  test "knows public network count" do
    # no forks!
    assert_equal 0, @upstream.network_count

    # public fork!
    perform_fork_orchestration do |forked_repo, _, reason|
      assert forked_repo, "fork expected, #{reason} given"

      assert_equal 1, @upstream.calculate_public_fork_count!
      assert_equal 0, forked_repo.calculate_public_fork_count!

      assert_equal 1, @upstream.reload.network_count
      assert_equal 1, forked_repo.reload.network_count

      # fork the public fork
      someone = create(:user)
      perform_fork_orchestration(repo: forked_repo, forker: someone) do |forked_repo2, _, reason2|
        assert forked_repo2, "fork expected, #{reason2} given"

        assert_equal 2, @upstream.calculate_public_fork_count!
        assert_equal 1, forked_repo.calculate_public_fork_count!

        assert_equal 2, @upstream.reload.network_count
        assert_equal 2, forked_repo.reload.network_count

        # private fork!
        assert forked_repo2.update_attribute(:public, false)
        assert_equal 1, @upstream.calculate_public_fork_count!
        assert_equal 0, forked_repo.calculate_public_fork_count!

        assert_equal 1, @upstream.reload.network_count
        assert_equal 1, forked_repo.reload.network_count
      end
    end
  end

  test "knows public network count, filters spammy users" do
    skip unless GitHub.spamminess_check_enabled?

    # no forks!
    assert_equal 0, @upstream.network_count

    # public fork!
    perform_fork_orchestration do |forked_repo, _, reason|
      assert forked_repo, "fork expected, #{reason} given"

      assert_equal 1, @upstream.calculate_public_fork_count!
      assert_equal 0, forked_repo.calculate_public_fork_count!

      assert_equal 1, @upstream.reload.network_count
      assert_equal 1, forked_repo.reload.network_count

      # spammy fork
      spammer = create(:user)
      perform_fork_orchestration(repo: forked_repo, forker: spammer) do |forked_repo2, _, reason2|
        assert forked_repo2, "fork expected, #{reason2} given"

        perform_enqueued_jobs(only: UpdateTableUserHiddenJob) { spammer.mark_as_spammy }

        assert_equal 1, @upstream.calculate_public_fork_count!
        assert_equal 0, forked_repo.calculate_public_fork_count!

        assert_equal 1, @upstream.reload.network_count
        assert_equal 1, forked_repo.reload.network_count

        # private fork!
        assert forked_repo2.update_attribute(:public, false)
        assert_equal 1, @upstream.calculate_public_fork_count!
        assert_equal 0, forked_repo.calculate_public_fork_count!

        assert_equal 1, @upstream.reload.network_count
        assert_equal 1, forked_repo.reload.network_count
      end
    end
  end

  test "knows private network count with no forks" do
    someone = create(:user)
    # no forks!
    assert_equal 0, @upstream.network_count
    @upstream.add_member(@forker, @upstream_owner, false)
    @upstream.add_member(someone, @upstream_owner, false)
    @upstream.set_permission(Repository::PRIVATE_VISIBILITY)

    perform_fork_orchestration do |public_fork, _, reason|
      assert public_fork, "fork expected, #{reason} given"
      assert public_fork.update_attribute(:public, true)

      perform_fork_orchestration(repo: public_fork, forker: someone) do |private_fork, _, reason2|
        assert private_fork, "fork expected, #{reason2} given"

        assert_equal 2, @upstream.reload.network_count
        assert_equal 2, public_fork.network_count
        assert_equal 2, private_fork.network_count
      end
    end
  end

  test "copies languages on fork" do
    grit = create(:repository, from_example: :mojombo_grit)
    grit.analyze_languages
    perform_fork_orchestration(repo: grit) do |forked_repo|
      forked_repo.analyze_languages
      refute_empty forked_repo.language_breakdown
    end
  end

  test "sets licenses on fork" do
    user = create(:user)
    license = License.find("mit")
    create(:repository_license, repository: @upstream, license_id: license.id)

    perform_fork_orchestration do |forked_repo|
      assert_equal license, forked_repo.license
    end
  end

  test "can fork to enterprise org with forking policy set to enterprise orgs" do
    private_repository, business_org, second_business_org = apply_policy(Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS)

    perform_fork_orchestration(
      repo: private_repository,
      forker: business_org.admin,
      owner: second_business_org
    ) do |forked_repo, _, reason|
      assert forked_repo, "fork expected, #{reason} given"
    end
  end

  test "cannot fork to outside org with forking policy set to enterprise orgs" do
    private_repository, business_org, second_business_org = apply_policy(Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS)
    outside_org = create(:organization, admin: business_org.admin)

    perform_fork_orchestration(
      repo: private_repository,
      forker: business_org.admin,
      owner: outside_org
    ) do |forked_repo, _, reason|
      refute forked_repo
      assert_equal :policy, reason
    end
  end

  test "cannot fork to user account with forking policy set to enterprise orgs" do
    private_repository, business_org, _ = apply_policy(Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS)

    perform_fork_orchestration(
      repo: private_repository,
      forker: business_org.admin
    ) do |forked_repo, _, reason|
      refute forked_repo
      assert_equal :policy, reason
    end
  end

  test "can fork to user account with forking policy set to user accounts and enterprise orgs" do
    private_repository, business_org, _ = apply_policy(Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)

    perform_fork_orchestration(
      repo: private_repository,
      forker: business_org.admin
    ) do |forked_repo, _, reason|
      assert forked_repo, "fork expected, #{reason} given"
    end
  end

  test "can fork to enterprise org with forking policy set to user accounts and enterprise orgs" do
    private_repository, business_org, second_business_org = apply_policy(Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)

    perform_fork_orchestration(
      repo: private_repository,
      forker: business_org.admin,
      owner: second_business_org
    ) do |forked_repo, _, reason|
      assert forked_repo, "fork expected, #{reason} given"
    end
  end

  test "can fork to user account with forking policy set to user accounts and same org" do
    private_repository, business_org, _ = apply_policy(Configurable::AllowPrivateRepositoryForking::SAME_ORGANIZATION_USER_ACCOUNTS)

    perform_fork_orchestration(
      repo: private_repository,
      forker: business_org.admin
    ) do |forked_repo, _, reason|
      assert forked_repo, "fork expected, #{reason} given"
    end
  end

  test "cannot fork to enterprise org with forking policy set to user accounts and same org" do
    private_repository, business_org, second_business_org = apply_policy(Configurable::AllowPrivateRepositoryForking::SAME_ORGANIZATION_USER_ACCOUNTS)

    perform_fork_orchestration(
      repo: private_repository,
      forker: business_org.admin,
      owner: second_business_org
    ) do |forked_repo, _, reason|
      refute forked_repo
      assert_equal :policy, reason
    end
  end

  test "can fork to same org with forking policy set to user accounts and same org" do
    private_repository, business_org, _ = apply_policy(Configurable::AllowPrivateRepositoryForking::SAME_ORGANIZATION_USER_ACCOUNTS)

    perform_fork_orchestration(
      repo: private_repository,
      forker: business_org.admin,
      owner: private_repository.owner
    ) do |forked_repo, _, reason|
      assert forked_repo, "fork expected, #{reason} given"
    end
  end

  test "cannot fork to outside org with forking policy set to user accounts and same org" do
    private_repository, business_org, _ = apply_policy(Configurable::AllowPrivateRepositoryForking::SAME_ORGANIZATION_USER_ACCOUNTS)
    outside_org = create(:organization, admin: business_org.admin)

    perform_fork_orchestration(
      repo: private_repository,
      forker: business_org.admin,
      owner: outside_org
    ) do |forked_repo, _, reason|
      refute forked_repo
      assert_equal :policy, reason
    end
  end

  test "can fork to user account with forking policy set to user accounts" do
    private_repository, business_org, _ = apply_policy(Configurable::AllowPrivateRepositoryForking::USER_ACCOUNTS)

    perform_fork_orchestration(
      repo: private_repository,
      forker: business_org.admin,
    ) do |forked_repo, _, reason|
      assert forked_repo, "fork expected, #{reason} given"
    end
  end

  test "cannot fork to enterprise org with forking policy set to user accounts" do
    private_repository, business_org, second_business_org = apply_policy(Configurable::AllowPrivateRepositoryForking::USER_ACCOUNTS)

    perform_fork_orchestration(
      repo: private_repository,
      forker: business_org.admin,
      owner: second_business_org
    ) do |forked_repo, _, reason|
      refute forked_repo
      assert_equal :policy, reason
    end
  end

  test "cannot fork to same org with forking policy set to user accounts" do
    private_repository, business_org, _ = apply_policy(Configurable::AllowPrivateRepositoryForking::USER_ACCOUNTS)

    perform_fork_orchestration(
      repo: private_repository,
      forker: business_org.admin,
      owner: private_repository.owner
    ) do |forked_repo, _, reason|
      refute forked_repo
      assert_equal :policy, reason
    end
  end

  test "cannot fork to outside org with forking policy set to user accounts" do
    private_repository, business_org, _ = apply_policy(Configurable::AllowPrivateRepositoryForking::USER_ACCOUNTS)
    outside_org = create(:organization, admin: business_org.admin)

    perform_fork_orchestration(
      repo: private_repository,
      forker: business_org.admin,
      owner: outside_org
    ) do |forked_repo, _, reason|
      refute forked_repo
      assert_equal :policy, reason
    end
  end

  test "cannot fork to random org from allowed user account with forking policy set to user accounts and enterprise orgs" do
    private_repository, business_org, _ = apply_policy(Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)
    outside_org = create(:organization, admin: business_org.admin)

    perform_fork_orchestration(
      repo: private_repository,
      forker: business_org.admin
    ) do |forked_repo, _, reason|
      assert forked_repo, "fork expected, #{reason} given"
      perform_fork_orchestration(
        repo: forked_repo,
        forker: business_org.admin,
        owner: outside_org
      ) do |second_fork, _, reason|
        refute second_fork
        assert_equal :policy, reason
      end
    end
  end

  test "copies parent dco policy to fork" do
    @upstream.enable_dco_signoff(actor: @upstream_owner)
    perform_fork_orchestration do |forked_repo|
      assert_equal @upstream.dco_signoff_enabled?, forked_repo.dco_signoff_enabled?
    end
  end

  test "can fork a repo with a description that is no longer valid" do
    @upstream.description = "a" * (::Repository::DESCRIPTION_CHAR_LIMIT + 1)
    @upstream.save!(validate: false)

    assert_difference "Repository.count" do
      perform_fork_orchestration do |forked_repo|
        assert_equal "a" * ::Repository::DESCRIPTION_CHAR_LIMIT, forked_repo.description
      end
    end
  end

  test "creates inactive repository when spokes creation fails" do
    Repository.any_instance.stubs(:initialize_replicas_from_network).raises(StandardError.new)
    orchestration = build_fork_orchestration
    assert_raises StandardError do
      orchestration.execute
    end

    repo = orchestration.repository
    refute_predicate repo, :active?
  end

  test "creates inactive repository when owner is deleted" do
    org = create(:organization)

    orchestration = build_fork_orchestration(forker: org.admins.first, owner: org)
    assert_predicate orchestration, :valid?

    # We need to simualate an orchestration whose owner gets destroyed after create_fork but before
    # activate_repository. This is pretty realistic, since create_fork is long running
    ForkRepositoryOrchestration.stop_after_step = :create_fork
    orchestration.execute
    org.async_destroy(org.owner)
    orchestration.execute

    refute_predicate orchestration.repository, :active?
    assert_equal "skipped", orchestration.state
  end

  test "syncs org_owned_private_network_with_forks table" do
    org = create(:organization)
    org.allow_private_repository_forking(actor: org.admins.first)
    repo = create(:private_repository, name: "grit", owner: org, from_example: :simple)
    forker = create(:user)
    org.add_member(forker)

    perform_fork_orchestration(
      repo: repo,
      forker: forker
    ) do |_|
      assert OrgOwnedPrivateNetworkWithForks.where(network_id: repo.network_id, owner_id: repo.owner_id).exists?
    end
  end

  context "private repos" do
    test "adds to the owner's collaborators count" do
      assert_difference "@private_upstream_owner.reload.collaborators_count" do
        @private_upstream.add_member(@forker)
      end

      assert_no_difference "@private_upstream_owner.reload.collaborators_count" do
        perform_fork_orchestration(
          repo: @private_upstream,
        ) do |forked_repo|
          assert forked_repo
        end
      end
    end

    test "copies the parent's permissions" do
      @private_upstream.add_member(@forker)
      perform_fork_orchestration(
        repo: @private_upstream,
      ) do |forked_repo|
        assert_includes forked_repo.members, @private_upstream.owner
      end
    end

    test "counts that repo's disk usage against the owner" do
      forker_old_usage = @forker.disk_usage
      private_upstream_owner_old_usage = @private_upstream_owner.disk_usage
      perform_fork_orchestration(
        repo: @private_upstream,
      ) do |_|
        assert_equal forker_old_usage, @forker.reload.disk_usage
        assert @private_upstream_owner.reload.disk_usage >= private_upstream_owner_old_usage
      end
    end

    test "fails if you're not a member" do
      assert_no_difference "Repository.count" do
        perform_fork_orchestration(
          repo: @private_upstream,
        ) do |_, _, reason|
          assert_equal :account, reason
        end
      end
    end

    test "does not change the parent's public_fork_count" do
      assert_no_difference "@private_upstream.public_fork_count" do
        @private_upstream.add_member(@forker)
        perform_fork_orchestration(
          repo: @private_upstream,
        ) do |forked_repo|
          assert forked_repo
        end
      end
    end

    test "enables network alternates on parent and fork" do
      # ambition = create(:private_repository, name: "ambition_test", owner: @defunkt)
      # refute_predicate ambition, :shared_storage_enabled?
      refute_predicate @private_upstream, :shared_storage_enabled?

      @private_upstream.add_member(@forker)
      perform_fork_orchestration(
        repo: @private_upstream
      ) do |forked_repo|
        assert_predicate forked_repo, :shared_storage_enabled?
        assert_predicate @private_upstream, :shared_storage_enabled?
      end
    end

    test "allows forking into an org on a paid plan" do
      assert_predicate @private_upstream.owner, :user?

      org = create :organization, plan: GitHub::Plan.business
      @private_upstream.add_member(org.admin)
      perform_fork_orchestration(
        repo: @private_upstream,
        forker: org.admin,
        owner: org
      ) do |forked_repo|
        assert forked_repo
      end
    end

    test "allows forking into an org on a free plan" do
      assert_predicate @private_upstream.owner, :user?

      org = create :organization, plan: GitHub::Plan.free
      @private_upstream.add_member(org.admin)
      perform_fork_orchestration(
        repo: @private_upstream,
        forker: org.admin,
        owner: org
      ) do |forked_repo|
        assert forked_repo
      end
    end

    test "forks_count should exclude soft deleted repos" do
      @private_upstream.add_member(@forker)

      assert_equal 0, @private_upstream.forks_count
      perform_fork_orchestration(
        repo: @private_upstream
      ) do |forked_repo|
        assert forked_repo

        assert_equal 1, @private_upstream.reload.forks_count

        forked_repo.remove(@forker)

        assert_equal 0, @private_upstream.reload.forks_count
      end
    end
  end

  context "public repos" do
    test "upstream repo is public (sanity check for fixtures)" do
      assert @upstream.public?
    end

    test "doesn't do any collaborator stuff" do
      assert_equal 0, @upstream_owner.collaborators_count
      perform_fork_orchestration
      assert_equal 0, @upstream_owner.reload.collaborators_count
      assert_equal @forker, @forker.repositories.first.plan_owner
    end

    test "doesn't add the parent's owner as a member" do
      perform_fork_orchestration do |forked_repo|
        assert forked_repo.members.empty?
      end
    end

    test "doesn't keep parent's owner as plan owner if fork becomes private" do
      perform_fork_orchestration do |forked_repo|
        perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
          # Stub mimics behavior of `Repository#set_visibility!(:detach)`, which
          # is now private.
          forked_repo.stubs(:detach_on_visibility_change?).returns(true)
          forked_repo.toggle_visibility(actor: @forker)
        end

        forked_repo.reload
        assert_equal forked_repo.owner, forked_repo.plan_owner
      end
    end

    test "increments the parent's public_fork_count" do
      assert_difference "@upstream.public_fork_count" do
        perform_fork_orchestration
      end
    end
  end

  context "private organization repo" do
    test "copies the parent's teams" do
      org = create(:organization)
      org.allow_private_repository_forking(actor: org.admins.first)
      repo = create(:private_repository, name: "grit", owner: org, from_example: :simple)
      team = create(:team, organization: org)
      team.add_repository(repo, :pull)

      forker = create(:user)
      org.add_member(forker)

      perform_fork_orchestration(
        repo: repo,
        forker: forker,
        jobs: [RepositoryAddTeamsJob]
      ) do |new_repo|
        assert repo.fork_inherits_teams?(new_repo) # sanity check

        assert_equal repo.teams, new_repo.teams
        assert_equal team, new_repo.teams.first
      end
    end
  end

  context "internal repo" do
    test "can not be forked if forking is disabled at the repo level" do
      business = create(:business)
      business_org = create(:organization, business: business)

      internal_repo = create(:internal_repository, name: "internal", owner: business_org)

      business.allow_private_repository_forking(actor: business_org.admin)
      business_org.allow_private_repository_forking(actor: business_org.admin)
      internal_repo.block_private_repository_forking(actor: business_org.admin)

      assert_difference "Repository.count", 0 do
        perform_fork_orchestration(
          repo: internal_repo,
          forker: business_org.admin
        ) do |_, _, reason|
          assert_equal :disabled, reason
        end
      end
    end

    test "can not be forked if forking is disabled at the org level" do
      business = create(:business)
      business_org = create(:organization, business: business)

      internal_repo = create(:internal_repository, name: "internal", owner: business_org)

      business.allow_private_repository_forking(actor: business_org.admin)
      internal_repo.allow_private_repository_forking(actor: business_org.admin)
      business_org.block_private_repository_forking(actor: business_org.admin)

      assert_difference "Repository.count", 0 do
        perform_fork_orchestration(
          repo: internal_repo,
          forker: business_org.admin
        ) do |_, _, reason|
          assert_equal :disabled, reason
        end
      end
    end

    test "can not be forked if forking is disabled at the business level" do
      business = create(:business)
      business_org = create(:organization, business: business)

      internal_repo = create(:internal_repository, name: "internal", owner: business_org)

      business_org.allow_private_repository_forking(actor: business_org.admin)
      internal_repo.allow_private_repository_forking(actor: business_org.admin)

      business.block_private_repository_forking(actor: business_org.admin)

      assert_difference "Repository.count", 0 do
        perform_fork_orchestration(
          repo: internal_repo,
          forker: business_org.admin
        ) do |_, _, reason|
          assert_equal :disabled, reason
        end
      end
    end

    test "can be forked when enabled on the repo, org, and business" do
      _, business_org, _ = apply_policy(Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)
      internal_repo = create(:internal_repository, name: "internal", owner: business_org)
      internal_repo.allow_private_repository_forking(actor: business_org.admin)

      assert_difference "Repository.count" do
        perform_fork_orchestration(
          repo: internal_repo,
          forker: business_org.admin
        ) do |forked_repo|
          assert forked_repo
        end
      end
    end

    test "internal cannot be forked to a non-enterprise org" do
      business = create(:business)
      business_org = create(:organization, business: business)

      internal_repo = create(:internal_repository, name: "internal", owner: business_org)

      business.allow_private_repository_forking(actor: business_org.admin)
      business_org.allow_private_repository_forking(actor: business_org.admin)

      random_org = create(:organization)
      random_org.add_admin(business_org.admin)

      perform_fork_orchestration(
        repo: internal_repo,
        forker: business_org.admin,
        owner: random_org
      ) do |forked_repo, _, reason|
        refute forked_repo, "Expected #{forked_repo} to be false"
        assert_equal :policy, reason
      end
    end

    test "internal can be forked to an enterprise org" do
      business = create(:business)
      business_org = create(:organization, business: business)

      internal_repo = create(:internal_repository, name: "internal", owner: business_org)

      business.allow_private_repository_forking(actor: business_org.admin)
      business_org.allow_private_repository_forking(actor: business_org.admin)

      second_business_org = create(:organization, business: business, admin: business_org.admin)

      perform_fork_orchestration(
        repo: internal_repo,
        forker: business_org.admin,
        owner: second_business_org
      ) do |forked_repo|
        assert forked_repo
        assert_predicate forked_repo, :internal?
      end
    end

    test "forking internal repo to user account should create private fork" do
      _, business_org, _ = apply_policy(Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)
      internal_repo = create(:internal_repository, name: "internal", owner: business_org)

      perform_fork_orchestration(
        repo: internal_repo,
        forker: business_org.admin
      ) do |forked_repo|
        assert forked_repo
        assert_predicate forked_repo, :private?
        refute_predicate forked_repo, :internal?
      end
    end

    test "cannot fork to personal account with enable_restrict_create_repository_in_personal_namespace" do
      business = create(:business)
      business_org = create(:organization, business: business)

      internal_repo = create(:internal_repository, name: "internal", owner: business_org)

      business.allow_private_repository_forking(actor: business_org.admin)
      business_org.allow_private_repository_forking(actor: business_org.admin)

      business.enable_restrict_create_repository_in_personal_namespace(force: false, actor: business_org.admin)

      perform_fork_orchestration(
        repo: internal_repo,
        forker: business_org.admin
      ) do |_, _, reason|
        assert_equal :policy, reason
      end
    end
  end

  test "deletes shadowed redirects when forking a repo" do
    user = create(:user)
    redirect = create(:repository_redirect, repository_name: "#{user.name}/new-fork-name")

    assert RepositoryRedirect.where(repository_name: "#{user.name}/new-fork-name").exists?

    assert perform_fork_orchestration(repo: @upstream, forker: user, name: "new-fork-name")

    refute RepositoryRedirect.where(repository_name: "#{user.name}/new-fork-name").exists?
  end

  context "#can_fork_repository?" do
    test "can fork repo into org more than once" do
      organization = create(:organization, admin: @forker)

      forked_repo, result = @upstream.fork(owner: organization, forker: @forker)
      assert_equal :created, result

      orchestration = build_fork_orchestration(owner: organization)

      assert_predicate orchestration, :valid?
      refute_predicate orchestration.errors, :any?
    end

    test "cannot fork repo into user account more than once" do
      forked_repo, result = @upstream.fork(forker: @forker)
      assert_equal :created, result

      orchestration = build_fork_orchestration(forker: @forker)

      refute_predicate orchestration, :valid?
      assert_predicate orchestration.errors, :any?
      assert orchestration.errors.first&.type == :exists
    end

    test "cannot fork to personal account with enable_restrict_create_repository_in_personal_namespace", skip_enterprise: true do
      emu = create(:emu)
      emu_business = emu.enterprise_managed_business
      emu_owner = emu_business.owners.first
      emu_member = create :emu, business: emu_business
      enterprise_org = create(:organization, admins: [emu_owner], business: emu_business)
      enterprise_org_repo = create(:repository, owner: enterprise_org, organization: enterprise_org, from_example: :repository_test_simple)
      enterprise_org.add_member(emu_member)
      emu_business.enable_restrict_create_repository_in_personal_namespace(force: false, actor: emu_owner)

      orchestration = build_fork_orchestration(repo: enterprise_org_repo, forker: emu_member)

      refute_predicate orchestration, :valid?
      assert_predicate orchestration.errors, :any?
      assert_equal :policy, orchestration.errors.first&.type
    end

    test "cannot fork to a deleted user" do
      org = create(:organization)
      org.async_destroy(org.owner)

      orchestration = build_fork_orchestration(forker: org.admins.first, owner: org)

      refute_predicate orchestration, :valid?
      assert_predicate orchestration.errors, :any?
      assert_equal :deleted_owner, orchestration.errors.first&.type
    end

    test "spammy users cannot fork" do
      @forker.update!(spammy: true)
      orchestration = build_fork_orchestration(repo: @repo, forker: @forker)
      refute_predicate orchestration, :valid?
      assert_predicate orchestration.errors, :any?
      assert_equal :spammy_user, orchestration.errors.first&.type
    end unless GitHub.single_or_multi_tenant_enterprise?
  end

  def perform_fork_orchestration(repo: nil, forker: nil, owner: nil, name: nil, description: nil, one_branch: nil, jobs: [])
    orchestration = build_fork_orchestration(repo:, forker:, owner:, name:, description:, one_branch:)

    if !orchestration.valid?
      reason = orchestration.errors.first&.type
      yield(nil, orchestration, reason) if block_given?
      return orchestration
    end

    only = ([RepositoryOrchestrationJob] + jobs)
    perform_enqueued_jobs(only: only) do
      orchestration.execute
    end

    orchestration.reload

    yield(orchestration.repository, orchestration, nil) if block_given?

    orchestration
  end

  def build_fork_orchestration(repo: nil, forker: nil, owner: nil, name: nil, description: nil, one_branch: nil)
    repo = @upstream if repo.nil?
    forker = @forker if forker.nil?
    owner = forker if owner.nil?

    # This is testing the forking features itself, not creating a fork for other purposes.
    # rubocop:disable GitHub/UseCreateForkRepositoryFactory
    RepositoryOrchestration.fork(
      parent_repository: repo,
      actor: forker,
      owner:,
      name:,
      description:,
      one_branch:
    )
    # rubocop:enable GitHub/UseCreateForkRepositoryFactory
  end

  def apply_policy(policy)
    business = create(:business)
    business_org = create(:organization, business: business)
    business.add_organization(business_org)
    business.allow_private_repository_forking(force: true, actor: business_org.admin, policy:)
    business_org.allow_private_repository_forking(force: true, actor: business_org.admin, policy:)
    second_business_org = create(:organization, business: business, admin: business_org.admin)
    private_repository = create(:private_repository, owner: business_org)

    [private_repository, business_org, second_business_org]
  end
end
