# typed: true
# frozen_string_literal: true
require "test_helper"
# these tests were all copied from toggle_visibility_job_test.rb and modified for the orchestration job
class VisibilityRepositoryOrchestrationTest < GitHub::TestCase
  include HydroTestHelpers
  include HydroMessageJobTestHelpers
  include TurboghasHelpers

  PRIVATE = Repository::PRIVATE_VISIBILITY
  PUBLIC = Repository::PUBLIC_VISIBILITY

  setup do
    GitHub::flipper[:turboghas_enabled].disable
  end

  test "disables push rules when a repo goes public" do
    GitHub.flipper[:push_rulesets].enable

    org = create(:organization, plan: "business_plus")
    repo = create(:private_repository, owner: org)

    push_ruleset = build(:repository_ruleset, target: "push", source: repo)
    push_rule = build(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
      max_file_path_length: 255
    })

    push_ruleset.save!
    push_rule.save!
    push_rules = RepositoryRuleset.load_for(source: repo, include_parents: false, targets: ["push"])
    assert_equal 1, push_rules.size
    assert_predicate push_rules.first, :enabled?

    o = RepositoryOrchestration.set_visibility(repo, actor: repo.owner, visibility: PUBLIC)
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) { o.execute }
    repo.reload
    o.reload

    assert_predicate o, :valid?
    assert_equal :succeeded, o.state.to_sym
    assert_predicate repo, :public?
    push_rules = RepositoryRuleset.load_for(source: repo, include_parents: false, targets: ["push"])
    assert_equal 1, push_rules.size
    assert_predicate push_rules.first, :disabled?
  end

  test "perform unlocks repo after job execution" do
    repo = create(:private_repository)

    o = RepositoryOrchestration.set_visibility(repo, actor: repo.owner, visibility: PUBLIC)
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) { o.execute }
    repo.reload
    o.reload

    assert_predicate o, :valid?
    assert_equal :succeeded, o.state.to_sym
    assert_predicate repo, :public?
    refute_predicate repo, :locked?
  end

  test "bot can change visibility with :write permission to the admin scope" do
    org = create(:organization)
    org.block_members_from_changing_repo_visibility(actor: org.owner)
    repo = create(:private_repository, owner: org)

    assert_predicate repo, :private?

    installation = make_integration_installation(target: org, permissions: { "administration" => :write })

    o = RepositoryOrchestration.set_visibility(repo, actor: installation.bot, visibility: PUBLIC)
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) { o.execute }
    repo.reload
    o.reload

    assert_predicate o, :valid?
    assert_equal :succeeded, o.state.to_sym
    assert_predicate repo, :public?
  end

  test "bot can NOT change visibility with :read permission to the admin scope" do
    org = create(:organization)
    org.block_members_from_changing_repo_visibility(actor: org.owner)
    repo = create(:private_repository, owner: org)

    assert_predicate repo, :private?

    installation = make_integration_installation(target: org, permissions: { "administration" => :read })

    o = RepositoryOrchestration.set_visibility(repo, actor: installation.bot, visibility: PUBLIC)

    refute_predicate o, :valid?
    assert_equal "Visibility can't be changed by this user.", o.errors.full_messages.to_sentence
    assert_predicate repo.reload, :private?
  end

  test "failed visibility change rolls back visibility changes" do
    org = create(:organization)
    repo = create(:internal_repository)
    repo.create_repository_auth_version(version: 42)

    assert_equal "internal", repo.visibility

    # Mock a failure to save the repo, which should cause set_visibility step to rollback
    repo.stubs(:save!).raises(StandardError.new("boom"))

    o = RepositoryOrchestration.set_visibility(repo, actor: repo.owner, visibility: "private")
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
      assert_raises StandardError do
        o.execute
      end
    end

    o.reload
    assert_equal 1, o.attempts
    assert_equal "failed", o.state
    assert_equal "boom", o.error_message
    assert_equal "set_visibility", o.step_name

    assert_equal 42, repo.reload.auth_version
  end

  test "increments the repository_auth_version", skip_enterprise: true do
    repo = create(:private_repository, from_example: :simple)
    repo.create_repository_auth_version(version: 42)

    # Freeze time so the hydro event timestamps match
    Timecop.freeze do
      o = RepositoryOrchestration.set_visibility(repo, actor: repo.owner, visibility: PUBLIC)
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { o.execute }
      repo.reload

      assert_equal 43, repo.auth_version

      expected_event = {
        repository: Hydro::EntitySerializer.repository(repo),
        change: :VISIBILITY_CHANGED,
        actor: Hydro::EntitySerializer.user(repo.owner),
        auth_version: 43,
      }
      assert_hydro_published_partial(expected_event, schema: "github.search.v0.RepositoryChanged")
      assert_hydro_messages(count: 1, schema: "github.search.v0.RepositoryChanged")
    end
  end

  test "making a network public syncs org_owned_private_networks_with_forks" do
    org = create(:organization)
    org.allow_private_repository_forking(actor: org.admins.first)
    user = create(:user)
    repo = create(:private_repository, owner: org)
    fork = create(:fork_repository, forker: org.admins.first, fork_repo: repo)

    assert OrgOwnedPrivateNetworkWithForks.where(network_id: repo.network_id, owner_id: repo.owner_id).exists?

    o = RepositoryOrchestration.set_visibility(repo, actor: repo.owner, visibility: PUBLIC)
    assert_difference("::OrgOwnedPrivateNetworkWithForks.count", -1) do
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { o.execute }
    end

    refute OrgOwnedPrivateNetworkWithForks.where(network_id: repo.network_id, owner_id: repo.owner_id).exists?
  end

  context "disable GHAS config when", skip_enterprise: true do
    test "making it public" do
      org = create(:organization)
      repo = create(:private_repository, owner: org)
      repo.owner.stubs(:advanced_security_purchased?).returns(true)
      repo.enable_advanced_security!(actor: repo.owner)

      o = RepositoryOrchestration.set_visibility(repo, actor: repo.owner, visibility: PUBLIC)
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { o.execute }
      repo.reload

      assert_equal :succeeded, o.reload.state.to_sym
      assert_predicate repo, :public?
      refute_predicate repo, :advanced_security_enabled?
    end

    test "making it private and new repos shouldn't enable it for user" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      repo.owner.stubs(:advanced_security_purchased?).returns(true)
      refute org.advanced_security_enabled_on_new_repos?

      o = RepositoryOrchestration.set_visibility(repo, actor: org.admin, visibility: PRIVATE)
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { o.execute }
      repo.reload

      assert_equal :succeeded, o.reload.state.to_sym
      assert_predicate repo, :private?
      refute_predicate repo, :advanced_security_enabled?
    end

    test "making it private and new repos shouldn't enable it for org" do
      org = create(:organization)

      business = create(:business, organizations: [org])
      business.mark_advanced_security_as_purchased_for_entity(actor: org)
      org.reload

      repo = create(:repository, owner: org)
      repo.owner.stubs(:advanced_security_purchased?).returns(true)
      refute_predicate org, :advanced_security_enabled_on_new_repos?

      o = RepositoryOrchestration.set_visibility(repo, actor: org.admin, visibility: PRIVATE)
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { o.execute }
      assert_equal :succeeded, o.reload.state.to_sym

      repo.reload
      assert_predicate repo, :private?
      refute_predicate repo, :advanced_security_enabled?
    end
  end

  test "enable GHAS config when making it private and the org opt-in GHAS for new repos", skip_enterprise: true do
    org = create(:organization)
    repo = create(:repository, owner: org)
    org.enable_advanced_security_on_new_repos(actor: org)

    GitHub.flipper[:advanced_security_circuit_breaker].disable(org)
    Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)

    o = RepositoryOrchestration.set_visibility(repo, actor: org.admin, visibility: PRIVATE)
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) { o.execute }
    repo.reload

    assert_equal :succeeded, o.reload.state.to_sym
    assert_predicate repo, :advanced_security_enabled?
  end

  test "do not enable GHAS config when making it private if the org has GHAS enabled for new repos and seat allowance would be exceeded", skip_enterprise: true do
    org = create(:organization)
    repo = create(:public_repository, owner: org)

    Repository.any_instance.stubs(:enabling_advanced_security_would_exceed_seat_allowance?).returns(true)
    GitHub.flipper[:advanced_security_circuit_breaker].disable(org)
    org.enable_advanced_security_on_new_repos(actor: org.admin)

    Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)

    o = RepositoryOrchestration.set_visibility(repo, actor: org.admin, visibility: PRIVATE)
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) { o.execute }
    repo.reload
    refute_predicate repo, :advanced_security_enabled?
  end

  test "enable GHAS config when making it private if the org has GHAS enabled for new repos, the seat allowance would be exceeded, but the circuit breaker is open", skip_enterprise: true do
    org = create(:organization)
    repo = create(:public_repository, owner: org)

    Repository.any_instance.stubs(:enabling_advanced_security_would_exceed_seat_allowance?).returns(true)
    GitHub.flipper[:advanced_security_circuit_breaker].enable(org)
    org.enable_advanced_security_on_new_repos(actor: org.admin)

    Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)

    o = RepositoryOrchestration.set_visibility(repo, actor: org.admin, visibility: PRIVATE)
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) { o.execute }
    repo.reload
    assert_predicate repo, :advanced_security_enabled?
  end

  test "do not enable GHAS config when making it private if the org has GHAS enabled for new repos, but policy forbids enabling GHAS", skip_enterprise: true do
    org = create(:organization)
    repo = create(:public_repository, owner: org)

    Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)

    # Setting enables GHAS for new repos
    Organization.any_instance.stubs(:advanced_security_enabled_on_new_repos?).returns(true)
    # but policy forbids it
    Organization.any_instance.stubs(:policy_allows_advanced_security_enablement?).returns(false)

    o = RepositoryOrchestration.set_visibility(repo, actor: org.admin, visibility: PRIVATE)
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) { o.execute }
    repo.reload
    refute_predicate repo, :advanced_security_enabled?
  end

  test "enable GHAS config when making it private if the org has GHAS enabled for new repos, and policy allows enabling GHAS", skip_enterprise: true do
    org = create(:organization)
    repo = create(:public_repository, owner: org)

    Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)

    # Setting enables GHAS for new repos
    Organization.any_instance.stubs(:advanced_security_enabled_on_new_repos?).returns(true)
    # and policy allows it
    Organization.any_instance.stubs(:policy_allows_advanced_security_enablement?).returns(true)

    o = RepositoryOrchestration.set_visibility(repo, actor: org.admin, visibility: PRIVATE)
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) { o.execute }
    repo.reload
    assert_predicate repo, :advanced_security_enabled?
  end

  context "multi repository variant analysis" do
    test "when going from public to private, triggers a database cleanup job" do
      user = create(:user)
      repo = create(:public_repository, owner: user)

      assert_enqueued_jobs(1, only: CodeqlDatabaseCleanupJob) do
        o = RepositoryOrchestration.set_visibility(repo, actor: user, visibility: PRIVATE)
        perform_enqueued_jobs(only: RepositoryOrchestrationJob) { o.execute }
      end
    end
  end

  context "dependency graph, vulnerability alerts, vulnerablity updates", skip_enterprise: true do
    test "when going from public to private, keep existing security product settings" do
      user = create(:verified_user)
      org = create(:organization, admin: user)
      repo = create(:public_repository, owner: org)

      dep_graph = SecurityProduct::DependencyGraph.new(repo)
      vuln_alerts = SecurityProduct::VulnerabilityAlerts.new(repo)
      vuln_updates = SecurityProduct::VulnerabilityUpdates.new(repo)

      # dep graph enabled by default on public repos
      assert repo.public?
      assert dep_graph.enabled?

      # vuln alerts _sometimes_ enabled by default
      vuln_alerts.enable(actor: user)
      assert vuln_alerts.enabled?

      refute vuln_updates.enabled?
      vuln_updates.enable(actor: user)
      assert vuln_updates.enabled?

      # all three services are turned on.
      # now, we transfer the repo to private vis

      o = RepositoryOrchestration.set_visibility(repo, actor: user, visibility: PRIVATE)
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { o.execute }
      repo.reload

      assert vuln_updates.enabled?
      assert vuln_alerts.enabled?
      assert dep_graph.enabled?
    end

    test "when going from public to private, don't just turn everything on" do
      user = create(:verified_user)
      org = create(:organization, admin: user)
      repo = create(:public_repository, owner: org)

      dep_graph = SecurityProduct::DependencyGraph.new(repo)
      vuln_alerts = SecurityProduct::VulnerabilityAlerts.new(repo)

      # dep graph enabled by default on public repos
      assert repo.public?
      assert dep_graph.enabled?

      # let's specifically _disable_ vuln alerts
      vuln_alerts.disable(actor: user)
      refute vuln_alerts.enabled?

      o = RepositoryOrchestration.set_visibility(repo, actor: user, visibility: PRIVATE)
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { o.execute }
      repo.reload

      assert dep_graph.enabled?
      refute vuln_alerts.enabled?
    end

    test "when going from private to public, keep existing security product settings" do
      user = create(:verified_user)
      org = create(:organization, admin: user)
      repo = create(:private_repository, owner: org)

      dep_graph = SecurityProduct::DependencyGraph.new(repo)
      vuln_alerts = SecurityProduct::VulnerabilityAlerts.new(repo)
      vuln_updates = SecurityProduct::VulnerabilityUpdates.new(repo)

      refute repo.public?
      refute dep_graph.enabled?
      refute vuln_alerts.enabled?
      refute vuln_updates.enabled?

      dep_graph.enable(actor: user)
      vuln_alerts.enable(actor: user)
      vuln_updates.enable(actor: user)

      assert dep_graph.enabled?
      assert vuln_alerts.enabled?
      assert vuln_updates.enabled?

      # all three services are turned on.
      # now, we transfer the repo to public vis

      o = RepositoryOrchestration.set_visibility(repo, actor: org.admin, visibility: PUBLIC)
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { o.execute }
      repo.reload

      assert dep_graph.enabled?
      assert vuln_alerts.enabled?
      assert vuln_updates.enabled?
    end
  end

  context "events" do
    context "secret scanning" do
      test "private -> public", skip_enterprise: true do
        org = create(:organization)
        repo = create(:private_repository, :with_instrumentation, owner: org)

        Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)

        o = RepositoryOrchestration.set_visibility(repo, actor: org.admin, visibility: PUBLIC)
        perform_enqueued_hydro_jobs(only: [HydroSecretScanningRepositoryVisibilityJob], allowed_primary_query_count: 1) do
          perform_enqueued_jobs(only: RepositoryOrchestrationJob) { o.execute }
        end

        with_hydro_publisher(GitHub.sync_hydro_publisher) do
          message = {
            repository_id: repo.id,
            request_id: "",
            actor_id: org.admin.id,
            old_visibility: "PRIVATE",
            new_visibility: "PUBLIC"
          }
          assert_hydro_published(message, schema: "github.repositories.v1.VisibilityChanged")
        end
        assert_hydro_messages(count: 1, schema: "token_scanning_service.v0.BackfillRequest")
      end

      test "public -> private", skip_enterprise: true do
        org = create(:organization)
        repo = create(:public_repository, :with_instrumentation, owner: org)

        Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)

        o = RepositoryOrchestration.set_visibility(repo, actor: org.admin, visibility: PRIVATE)
        perform_enqueued_hydro_jobs(only: [HydroSecretScanningRepositoryVisibilityJob], allowed_primary_query_count: 1) do
          perform_enqueued_jobs(only: RepositoryOrchestrationJob) { o.execute }
        end

        assert_hydro_messages(count: 0, schema: "token_scanning_service.v0.BackfillRequest")
      end
    end
  end

  test "when going from public to private, remove PVR submitters from pending advisories" do
    org = create(:organization)
    repo = create(:public_repository, :with_instrumentation, owner: org)
    advisory = create(:pending_pvd_repo_advisory, :with_workspace, repository: repo)

    assert repo.readable_by?(advisory.author)
    assert advisory.writable_by?(advisory.author)
    assert advisory.workspace_repository.resources.contents.writable_by?(advisory.author)

    o = RepositoryOrchestration.set_visibility(repo, actor: org.admin, visibility: PRIVATE)
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) { o.execute }

    refute repo.readable_by?(advisory.author)
    refute advisory.writable_by?(advisory.author)
    refute advisory.workspace_repository.resources.contents.readable_by?(advisory.author)
  end

  test "works with long descriptions" do
    repo = create(:private_repository)

    # create a too-long description
    count = Repository::DESCRIPTION_CHAR_LIMIT / 10 + 1
    words = count.times.map { "\xF0\x9D\x90\x93\xF0\x9D\x90\xA1\xF0\x9D\x90\x9E \xF0\x9D\x90\xA9\xF0\x9D\x90\xAE\xF0\x9D\x90\xAB\xF0\x9D\x90\xA9\xF0\x9D\x90\xA8\xF0\x9D\x90\xAC\xF0\x9D\x90\x9E " }.join

    Repository.connection.execute(<<-SQL)
    UPDATE repositories
    SET DESCRIPTION = "#{words}"
    WHERE id = #{repo.id}
    SQL

    repo = Repository.find(repo.id)
    assert repo.description.length > Repository::DESCRIPTION_CHAR_LIMIT

    o = RepositoryOrchestration.set_visibility(repo, actor: repo.owner, visibility: PUBLIC)
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) { o.execute }
    repo.reload
    o.reload

    assert_predicate o, :valid?
    assert_equal :succeeded, o.state.to_sym
    assert_predicate repo, :public?
    refute_predicate repo, :locked?
    assert_predicate repo, :valid?
  end

  test "when making forked repo private close pull requests sent to public repositories" do
    repo = create(:public_repository, from_example: :pull_request_source)

    forker = create(:user)
    repo_fork = create(:fork_repository, forker: forker, fork_repo: repo, from_example: :pull_request_fork)

    example_repo :pull_request_fork, repo
    pull_request = create(:pull_request, user: forker, repository: repo, base_repository: repo, head_repository: repo_fork, head_ref: "topic")

    assert_predicate pull_request, :open?
    assert_predicate repo_fork, :public?

    o = RepositoryOrchestration.set_visibility(repo_fork, actor: repo_fork.owner, visibility: PRIVATE)
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) { o.execute }
    repo.reload
    o.reload

    assert_predicate o, :valid?
    assert_equal :succeeded, o.state.to_sym
    assert_predicate repo_fork, :private?
    assert_predicate repo_fork, :valid?
    assert_predicate pull_request.reload, :closed?
  end

  test "can't change visibility if the repository is currently being transferred and is locked" do
    repo = create(:public_repository)
    new_owner = create(:user)

    RepositoryOrchestration.transfer(repo, actor_id: repo.owner.id, new_owner_id: new_owner.id).execute
    assert repo.reload.locked?

    o = RepositoryOrchestration.set_visibility(repo, actor: repo.owner, visibility: PRIVATE)
    assert_equal "The repository is locked due to an ownership transfer.", o.errors.full_messages.to_sentence
  end

  # The user contribution cache is only cleared directly via KV in single tenant enterprise environments
  if GitHub.single_tenant_enterprise?
    test "retries if kv is down" do
      repo = create(:public_repository)

      GitHub::KV.any_instance.stubs(:del).raises(GitHub::KV::UnavailableError)

      o = RepositoryOrchestration.set_visibility(repo, actor: repo.owner, visibility: PRIVATE)
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        o.execute(synchronous: false)
      end

      assert_equal :failed, o.reload.state.to_sym
      assert_equal Orchestration::MAX_ATTEMPTS + 1, o.attempts
    end
  end

  context "when a conflicting namespace exists"  do
    test "can't change private visibility to public on repo when you don't own the retired namespace" do
      repo_jack = create(:user, login: "repojack123")
      private_repo = create(:private_repository, name: "shiny-lamp", owner: repo_jack)
      retired_namespace = RetiredNamespace.create(name: "shiny-lamp", owner_id: 1, owner_login: "repojack123")

      o = RepositoryOrchestration.set_visibility(private_repo, actor: private_repo.owner, visibility: PUBLIC)
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        o.execute(synchronous: false)
      end

      assert_equal "Visibility Repository namespace has been retired.", o.errors.full_messages.to_sentence
    end

    test "can change private visibility to public on repo when you do own the retired namespace" do
      repo_jack = create(:user, login: "repojack123")
      private_repo = create(:private_repository, name: "shiny-lamp", owner: repo_jack)
      retired_namespace = create(:retired_namespace, name: "shiny-lamp", owner: repo_jack)

      o = RepositoryOrchestration.set_visibility(private_repo, actor: private_repo.owner, visibility: PUBLIC)
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        o.execute(synchronous: false)
      end

      assert_equal :succeeded, o.reload.state.to_sym
    end
  end
end
