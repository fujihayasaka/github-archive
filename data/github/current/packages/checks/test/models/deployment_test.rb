# typed: false
# frozen_string_literal: true

require "test_helper"

class DeploymentTest < GitHub::TestCase
  include ResiliencyHelpers
  include BackgroundDeletesTestHelpers

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @mojombo  = create(:user, login: "mojombo2", plan: "medium")
    @defunkt  = create(:user, login: "defunkt",  plan: "medium")

    @grit     = create(:repository, name: "grit", owner: @mojombo)
    @sha1     = "86264f45ff4bcd3da195f5c83f7e414ed4a71628"

    reset_repo_root
    example_repo :mojombo_grit, @grit # rubocop:disable GitHub/UseFromExampleInRepositoryFactory

    @metadata = { message: "blah", committer: @grit.owner }
  end

  setup do
    reset_repo_root
    example_repo :mojombo_grit, @grit
  end

  context "#succeeded?" do
    test "returns true when the last recorded status is 'success'" do
      deployment = create(:deployment)
      create(:deployment_status, :success, deployment: deployment)
      assert_predicate deployment.reload, :succeeded?
    end

    test "returns false when the last recorded status is not 'success'" do
      deployment = create(:deployment)
      create(:deployment_status, :failure, deployment: deployment)
      refute_predicate deployment.reload, :succeeded?
    end
  end

  test "fixture" do
    deployment = create :deployment
  end

  test "task length" do
    deployment = create(:deployment, task: "a" * 128)
    assert deployment.valid?
    deployment.task = "a" * 129
    refute deployment.valid?
    assert deployment.errors[:task].present?
  end

  test "description length" do
    deployment = create(:deployment, description: "a" * 500)
    assert_predicate deployment, :valid?

    deployment.description = "aa" * MYSQL_TEXT_FIELD_LIMIT
    refute_predicate deployment, :valid?
    assert_predicate deployment.errors[:description], :present?
  end

  test "description should be UTF-8" do
    description = "🐛 This is a description"
    deployment = create(:deployment, description: description)
    assert_predicate deployment, :valid?

    assert_equal Encoding::UTF_8, deployment.description.encoding
    assert_equal description, deployment.description
  end

  test "payload length" do
    deployment = create :deployment

    payload = { message: "#{'a' * MYSQL_TEXT_FIELD_LIMIT}" }.to_json
    deployment.payload = payload

    refute_predicate deployment, :valid?
    assert_predicate deployment.errors[:payload], :present?
  end

  test "payload should be UTF-8" do
    payload = { message: "Have a glass of \xF0\x9F\x8D\xB7" }.to_json
    deployment = create(:deployment, payload: payload)

    assert_predicate deployment, :valid?

    assert_equal Encoding::UTF_8, deployment.payload.encoding
    assert_equal payload, deployment.payload
  end

  test "latest environment should be set" do
    deployment = create(:deployment, description: "A description", environment: "development")

    assert_equal "development", deployment.latest_environment
  end

  context "behind_default_branch?" do
    test "when the ref is behind the default branch" do
      default = @grit.heads.find(@grit.default_branch)
      behind  = @grit.heads.create("behind", default.target_oid, @grit.owner)

      behind.append_commit(@metadata, @grit.owner) do |files|
        files.add("READMEa.md", "TODO")
      end

      default.append_commit(@metadata, @grit.owner) do |files|
        files.add("READMEb.md", "TODO")
      end

      deployment = create :deployment, repository: @grit, sha: behind.target_oid
      assert deployment.behind_default_branch?
    end

    test "when the ref is the same as the default branch" do
      default  = @grit.heads.find(@grit.default_branch)
      default2 = @grit.heads.create("same", default.target_oid, @grit.owner)

      deployment = create :deployment, repository: @grit, sha: default2.target_oid, ref: "same"
      assert !deployment.behind_default_branch?
    end

    test "when the ref is ahead of the default branch" do
      default = @grit.heads.find(@grit.default_branch)
      ahead   = @grit.heads.create("ahead", default.target_oid, @grit.owner)

      ahead.append_commit(@metadata, @grit.owner) do |files|
        files.add("READMEa.md", "TODO")
      end

      deployment = create :deployment, repository: @grit, sha: ahead.target_oid, ref: "ahead"
      assert !deployment.behind_default_branch?
    end
  end

  context "merge_for" do
    test "when the ref is behind the default branch" do
      default = @grit.heads.find(@grit.default_branch)
      behind  = @grit.heads.create("behind", default.target_oid, @grit.owner)

      behind.append_commit(@metadata, @grit.owner) do |files|
        files.add("READMEa.md", "TODO")
      end

      default.append_commit(@metadata, @grit.owner) do |files|
        files.add("READMEb.md", "TODO")
      end

      deployment = create :deployment, repository: @grit, sha: behind.target_oid, ref: "behind"
      assert deployment.merge_for(@grit.owner)
    end

    test "when the ref is the same as the default branch" do
      default  = @grit.heads.find(@grit.default_branch)
      default2 = @grit.heads.create("same", default.target_oid, @grit.owner)

      deployment = create :deployment, repository: @grit, sha: default2.target_oid, ref: "same"
      assert !deployment.merge_for(@grit.owner)
    end

    test "when the ref is ahead of the default branch" do
      default = @grit.heads.find(@grit.default_branch)
      ahead   = @grit.heads.create("ahead", default.target_oid, @grit.owner)

      ahead.append_commit(@metadata, @grit.owner) do |files|
        files.add("READMEa.md", "TODO")
      end

      deployment = create :deployment, repository: @grit, sha: ahead.target_oid, ref: "ahead"
      assert !deployment.merge_for(@grit.owner)
    end
  end

  context "merge queue" do
    context "#current_production_deployments_for_merge_queue" do
      test "finds all production deployments for the locked merge queue entry" do
        entry = create(:merge_queue_entry, :locked, head_sha: "a" * 40)
        deployment = create(:deployment, repository: entry.queue.repository, sha: entry.head_sha, production_environment: true)
        deployments = Deployment.current_production_deployments_for_merge_queue(entry.queue)

        assert_equal 1, deployments.count
        assert_equal deployments.first, deployment
      end

      test "only finds deployments for the locked merge queue entry" do
        entry = create(:merge_queue_entry, head_sha: "a" * 40)
        create(:deployment, repository: entry.queue.repository, sha: entry.head_sha, production_environment: true)
        deployments = Deployment.current_production_deployments_for_merge_queue(entry.queue)

        assert_empty deployments
      end

      test "only finds deployments for the production environment" do
        entry = create(:merge_queue_entry, :locked, head_sha: "a" * 40)
        create(:deployment, repository: entry.queue.repository, sha: entry.head_sha, production_environment: false)

        deployments = Deployment.current_production_deployments_for_merge_queue(entry.queue)
        assert_empty deployments
      end
    end

    context "#current_deployments_for_merge_queue" do
      test "finds all production deployments for the locked merge queue entry" do
        entry = create(:merge_queue_entry, :locked, head_sha: "a" * 40)
        deployment = create(:deployment, repository: entry.queue.repository, sha: entry.head_sha, production_environment: true)
        deployments = Deployment.current_deployments_for_merge_queue(entry.queue)

        assert_equal 1, deployments.count
        assert_equal deployments.first, deployment
      end

      test "only finds deployments for the locked merge queue entry" do
        entry = create(:merge_queue_entry, head_sha: "a" * 40)
        create(:deployment, repository: entry.queue.repository, sha: entry.head_sha, production_environment: true)
        deployments = Deployment.current_deployments_for_merge_queue(entry.queue)

        assert_empty deployments
      end

      test "finds deployments for non-production environment" do
        entry = create(:merge_queue_entry, :locked, head_sha: "a" * 40)
        deployment = create(:deployment, repository: entry.queue.repository, sha: entry.head_sha, production_environment: false)

        deployments = Deployment.current_deployments_for_merge_queue(entry.queue)

        assert_equal 1, deployments.count
        assert_equal deployments.first, deployment
      end
    end
  end

  test "sorts deployments in reverse order on repositories" do
    deployment1 = create :deployment, repository: @grit
    deployment2 = create :deployment, repository: @grit

    assert_equal deployment2.id, @grit.deployments.first.id
  end

  test "rejects deployments with invalid shas" do
    invalid_shas = ["abcd", "z" * 40, "xxx  " * 8]
    invalid_shas.each do |sha|
      deployment = build :deployment, sha: sha
      assert !deployment.valid?
      assert_equal "must be a valid hex object ID", deployment.errors[:sha].first
    end
  end

  test "test refs containing emoji" do
    deployment = build :deployment, sha: "a" * 40, ref: "start🐹tail"
    assert deployment.valid?
    deployment.save
    deployment.reload
    assert_equal "start🐹tail", deployment.ref.force_encoding("UTF-8")
  end

  test "active?" do
    deployment = create :deployment, repository: @grit
    refute_predicate deployment, :active?

    DeploymentStatus::STATES.each do |state|
      deployment = Deployment.find(deployment.id) # Resets ivars that are cached
      deployment.statuses.create!(log_url: "https://a.com", state: state, creator: @grit.owner)

      if state == "success"
        assert_predicate deployment, :active?, "expected deployment with latest status with state #{state} to be active"
      else
        refute_predicate deployment, :active?, "expected deployment with latest status with state #{state} to be in-active"
      end
    end
  end

  test "denormalized latest_* fields are filled" do
    deployment = create :deployment, repository: @grit
    assert_equal "production", deployment.latest_environment

    deployment.statuses.create(log_url: "https://a.com", state: "pending", creator: @defunkt, environment: "development")
    assert_equal "pending", Deployment.find(deployment.id).latest_status_state
    assert_equal "development", Deployment.find(deployment.id).latest_environment

    deployment.statuses.create(log_url: "https://c.com", state: "success", creator: @defunkt, environment: "staging")
    assert_equal "success", Deployment.find(deployment.id).latest_status_state
    assert_equal "staging", Deployment.find(deployment.id).latest_environment

    assert_equal "success", Deployment.find(deployment.id).latest_state
    assert_equal "staging", Deployment.find(deployment.id).latest_environment
  end

  context "active scope" do
    test "includes deployments whose latest status is success" do
      deployment_wo_status = create(:deployment)
      assert_empty deployment_wo_status.statuses

      deployment_w_one_failure = create(:deployment)
      create(:deployment_status, :failure, deployment: deployment_w_one_failure)

      deployment_w_one_success = create(:deployment)
      create(:deployment_status, :success, deployment: deployment_w_one_success)

      mixed_deployment_w_latest_failure = create(:deployment)
      create(:deployment_status, :success, deployment: mixed_deployment_w_latest_failure)
      create(:deployment_status, :failure, deployment: mixed_deployment_w_latest_failure)

      mixed_deployment_w_latest_success = create(:deployment)
      create(:deployment_status, :failure, deployment: mixed_deployment_w_latest_success)
      create(:deployment_status, :success, deployment: mixed_deployment_w_latest_success)

      active_deployments = Deployment.active
      assert active_deployments.all?(&:active?), "expected every deployment returned by .active scope to be #active?"

      active_deployment_ids = active_deployments.map(&:id)
      assert_includes active_deployment_ids, deployment_w_one_success.id,
        "should have included deployment with a single success"
      assert_includes active_deployment_ids, mixed_deployment_w_latest_success.id,
        "should have included deployment whose latest status was a success"
      refute_includes active_deployment_ids, deployment_wo_status.id,
        "should not have included deployment that has no statuses"
      refute_includes active_deployment_ids, deployment_w_one_failure.id,
        "should not have included deployment whose only status was not a success"
      refute_includes active_deployment_ids, mixed_deployment_w_latest_failure.id,
        "should not have included deployment whose latest status was not a success"
    end
  end

  context "issue deployment events" do
    test "are created for each matching pull request on create" do
      default = @grit.heads.find(@grit.default_branch)
      topic   = @grit.heads.create("topic", default.target_oid, @grit.owner)

      topic.append_commit(@metadata, @grit.owner) do |files|
        files.add("blah.txt", "blahblahblah")
      end

      pull = PullRequest.create_for(@grit,
        user: @grit.owner,
        base: "#{@grit.owner}:master",
        head: "#{@grit.owner}:topic",
        title: "blah",
        body: "blah",
      )

      assert_difference "pull.issue.events.count", 1 do
        deployment = create :deployment, repository: @grit, sha: topic.target_oid
        event = pull.events.last
        assert_equal "deployed", event.event
        assert_equal pull.head_sha, event.deployment.sha
      end

      assert_no_difference "pull.issue.events.count", 1 do
        deployment = create :deployment, repository: @grit, sha: default.target_oid
      end
    end

    test "are NOT created when the deployment is updated" do
      default = @grit.heads.find(@grit.default_branch)
      topic   = @grit.heads.create("topic", default.target_oid, @grit.owner)

      topic.append_commit(@metadata, @grit.owner) do |files|
        files.add("blah.txt", "blahblahblah")
      end

      pull = PullRequest.create_for(@grit,
        user: @grit.owner,
        base: "#{@grit.owner}:master",
        head: "#{@grit.owner}:topic",
        title: "blah",
        body: "blah",
      )

      deployment = create :deployment, repository: @grit, sha: topic.target_oid

      assert_no_difference "pull.issue.events.count" do
        deployment.update description: "updated desc"
      end
    end

    test "are destroyed when the deployment is destroyed" do
      enable_feature_flag(:destroy_deployment_issue_events)

      default = @grit.heads.find(@grit.default_branch)
      topic   = @grit.heads.create("topic", default.target_oid, @grit.owner)

      topic.append_commit(@metadata, @grit.owner) do |files|
        files.add("blah.txt", "blahblahblah")
      end

      pull = PullRequest.create_for(@grit,
        user: @grit.owner,
        base: "#{@grit.owner}:master",
        head: "#{@grit.owner}:topic",
        title: "blah",
        body: "blah",
      )

      first_deployment = create :deployment, repository: @grit, sha: topic.target_oid
      deployment = create :deployment, repository: @grit, sha: topic.target_oid
      event = pull.events.last

      assert_equal "deployed", event.event
      assert_equal pull.head_sha, event.deployment.sha

      deployment.destroy!
      assert_raises(ActiveRecord::RecordNotFound) do
        event.reload
      end

      # make sure the first deployment event is not destroyed
      first_deployment_event = pull.reload.events.deployments.first
      assert_equal first_deployment_event.deployment, first_deployment
    end
  end

  context "deployments for a pull request" do
    test "finds deployments created after the pull request" do
      default = @grit.heads.find(@grit.default_branch)
      topic   = @grit.heads.create("topic", default.target_oid, @grit.owner)

      topic.append_commit(@metadata, @grit.owner) do |files|
        files.add("blah.txt", "blahblahblah")
      end

      pull = PullRequest.create_for(@grit,
        user: @grit.owner,
        base: "#{@grit.owner}:master",
        head: "#{@grit.owner}:topic",
        title: "blah",
        body: "blah",
      )

      deployment = create :deployment, repository: @grit, sha: topic.target_oid

      deploys = Deployment.for_pull_request(pull).to_a
      assert_equal 1, deploys.count
      assert_equal deployment.id, deploys[0].id
    end

    test "finds deployments created before the pull request" do
      default = @grit.heads.find(@grit.default_branch)
      topic   = @grit.heads.create("topic", default.target_oid, @grit.owner)

      topic.append_commit(@metadata, @grit.owner) do |files|
        files.add("blah.txt", "blahblahblah")
      end

      deployment = create :deployment, repository: @grit, sha: topic.target_oid

      pull = PullRequest.create_for(@grit,
        user: @grit.owner,
        base: "#{@grit.owner}:master",
        head: "#{@grit.owner}:topic",
        title: "blah",
        body: "blah",
      )

      deploys = Deployment.for_pull_request(pull).to_a
      assert_equal 1, deploys.count
      assert_equal deployment.id, deploys[0].id
    end
  end

  context "instrumentation" do
    test "deployment.create event is triggered on create" do
      events = subscribe "deployment.create"
      deployment = create :deployment, repository: @grit
      expected_payload = {
        deployment_id: deployment.id,
        repository: @grit.name_with_owner,
        repository_id: @grit.id,
        public_repo: @grit.public?,
        creator: deployment.creator.login,
        creator_id: deployment.creator_id,
      }

      assert event = events.pop, "expected deployment.create event to be triggered"
      assert_equal expected_payload, event.payload
    end
  end

  context "deployments without statuses" do
    test "is abandoned if no services responded in 30 minutes" do
      deployment = create :deployment, repository: @grit
      deployment.update(created_at: 1.hour.ago)
      assert deployment.abandoned?
    end

    test "is pending if no services responded recently" do
      deployment = create :deployment, repository: @grit
      refute deployment.abandoned?
      assert_equal "pending", deployment.latest_state
    end
  end

  context "#set_previous_environment_deployments_inactive!" do
    test "creates inactive deployment statuses" do
      old_deployment = create :deployment, repository: @grit
      old_deployment.statuses.create(state: "pending", creator_id: @grit.owner)
      old_deployment.statuses.create(state: "success", creator_id: @grit.owner)
      old_deployment.statuses.create(state: "success", creator_id: @grit.owner)
      old_deployment.statuses.create(state: "failure", creator_id: @grit.owner)
      old_deployment.statuses.create(state: "inactive", creator_id: @grit.owner)
      old_deployment.statuses.create(state: "error", creator_id: @grit.owner)
      old_deployment.statuses.create(state: "success", creator_id: @grit.owner)

      deployment = create :deployment, repository: @grit
      deployment.statuses.create(state: "pending", creator_id: @grit.owner)
      deployment.statuses.create(state: "success", creator_id: @grit.owner)
      deployment.statuses.create(state: "success", creator_id: @grit.owner)
      deployment.statuses.create(state: "failure", creator_id: @grit.owner)
      deployment.statuses.create(state: "inactive", creator_id: @grit.owner)
      deployment.statuses.create(state: "error", creator_id: @grit.owner)
      deployment.statuses.create(state: "success", creator_id: @grit.owner)

      assert_equal 14, DeploymentStatus.count
      deployment.set_previous_environment_deployments_inactive!
      assert_equal 15, DeploymentStatus.count

      assert_equal "inactive", old_deployment.reload.latest_state
      refute_predicate old_deployment, :active?
      assert old_deployment.statuses.last.environment
      assert_equal old_deployment.environment, old_deployment.statuses.last.environment
      assert_equal "success", deployment.reload.latest_state
    end

    test "doesn't create unnecessary inactive deployment statuses" do
      old_deployment = create :deployment, repository: @grit
      old_deployment.statuses.create(state: "success", creator_id: @grit.owner)
      old_deployment.statuses.create(state: "inactive", creator_id: @grit.owner)
      old_deployment.save!

      deployment = create :deployment, repository: @grit
      deployment.statuses.create(state: "success", creator_id: @grit.owner)
      deployment.save!

      assert_equal 3, DeploymentStatus.count
      deployment.set_previous_environment_deployments_inactive!
      assert_equal 3, DeploymentStatus.count
    end

    test "will fall back to deployment environment if deployment status env is null" do
      old_deployment = create :deployment, repository: @grit, environment: "foo"
      status = old_deployment.statuses.create(state: "success", creator_id: @grit.owner)
      old_deployment.save!

      status.update_column(:environment, nil)

      deployment = create :deployment, repository: @grit
      deployment.statuses.create(state: "success", creator_id: @grit.owner, environment: "foo")
      deployment.save!

      assert_equal 2, DeploymentStatus.count
      deployment.set_previous_environment_deployments_inactive!
      assert_equal 3, DeploymentStatus.count

      assert_equal "inactive", old_deployment.reload.latest_state
    end

    test "when setting inactive status, will use environment of previous status if available" do
      old_deployment = create :deployment, repository: @grit, environment: "foo"
      old_deployment.statuses.create(state: "success", creator_id: @grit.owner, environment: "ENV")
      old_deployment.save!

      deployment = create :deployment, repository: @grit, environment: "bar"
      deployment.statuses.create(state: "success", creator_id: @grit.owner, environment: "ENV")
      deployment.save!

      assert_equal 2, DeploymentStatus.count
      deployment.set_previous_environment_deployments_inactive!
      assert_equal 3, DeploymentStatus.count

      old_deployment.reload
      assert_equal old_deployment.latest_state, "inactive"
      assert_equal old_deployment.latest_status.environment, "ENV"
    end

    test "does not set inactive status when deploying to an old environment of an old deployment" do
      old_deployment = create :deployment, repository: @grit, environment: "OLD_ENV"
      old_deployment.statuses.create(state: "success", creator_id: @grit.owner, environment: "OLD_ENV")
      old_deployment.statuses.create(state: "success", creator_id: @grit.owner, environment: "NEW_ENV")
      old_deployment.save!

      deployment = create :deployment, repository: @grit
      deployment.statuses.create(state: "success", creator_id: @grit.owner, environment: "OLD_ENV")
      deployment.save!

      assert_equal 3, DeploymentStatus.count
      deployment.set_previous_environment_deployments_inactive!
      assert_equal 3, DeploymentStatus.count

      assert_equal old_deployment.reload.latest_state, "success"
    end

    test "does not set inactive status by default on production environments" do
      old_deployment = create :deployment, repository: @grit, environment: "production", production_environment: true
      old_deployment.statuses.create(state: "success", creator_id: @grit.owner)
      old_deployment.save!

      deployment = create :deployment, repository: @grit, environment: "production", production_environment: true
      deployment.statuses.create(state: "success", creator_id: @grit.owner)
      deployment.save!

      assert_equal 2, DeploymentStatus.count
      deployment.set_previous_environment_deployments_inactive!
      assert_equal 2, DeploymentStatus.count

      assert_equal old_deployment.reload.latest_state, "success"
    end

    test "sets inactive status on production environments if :include_production kwarg is passed" do
      old_deployment = create :deployment, repository: @grit, environment: "production"
      old_deployment.statuses.create(state: "success", creator_id: @grit.owner)
      old_deployment.save!

      deployment = create :deployment, repository: @grit, environment: "production"
      deployment.statuses.create(state: "success", creator_id: @grit.owner)
      deployment.save!

      assert_equal 2, DeploymentStatus.count
      deployment.set_previous_environment_deployments_inactive!(include_production: true)
      assert_equal 3, DeploymentStatus.count

      assert_equal old_deployment.reload.latest_state, "inactive"
    end

    test "doesn't set inactive status on environments with different URL if :environment_url kwarg is passed" do
      old_deployment = create :deployment, repository: @grit, environment: "production"
      old_deployment.statuses.create(state: "success", creator_id: @grit.owner, environment_url: "https://github.com")
      old_deployment.save!

      current_url = "https://github.app.com"
      deployment = create :deployment, repository: @grit, environment: "production"
      deployment.statuses.create(state: "success", creator_id: @grit.owner, environment_url: current_url)
      deployment.save!

      assert_equal 2, DeploymentStatus.count
      deployment.set_previous_environment_deployments_inactive!(include_production: true, environment_url: current_url)
      assert_equal 2, DeploymentStatus.count

      assert_equal old_deployment.reload.latest_state, "success"
    end

    test "sets inactive status on environments with different URL if :environment_url kwarg is not passed" do
      old_deployment = create :deployment, repository: @grit, environment: "production"
      old_deployment.statuses.create(state: "success", creator_id: @grit.owner, environment_url: "https://github.com")
      old_deployment.save!

      current_url = "https://github.app.com"
      deployment = create :deployment, repository: @grit, environment: "production"
      deployment.statuses.create(state: "success", creator_id: @grit.owner, environment_url: current_url)
      deployment.save!

      assert_equal 2, DeploymentStatus.count
      deployment.set_previous_environment_deployments_inactive!(include_production: true)
      assert_equal 3, DeploymentStatus.count

      assert_equal old_deployment.reload.latest_state, "inactive"
    end

    test "sets inactive status on environments with same URL if :environment_url kwarg is passed" do
      old_deployment = create :deployment, repository: @grit, environment: "production"
      old_deployment.statuses.create(state: "success", creator_id: @grit.owner, environment_url: "https://github.com")
      old_deployment.save!

      url = "https://github.app.com"
      old_deployment2 = create :deployment, repository: @grit, environment: "production"
      old_deployment2.statuses.create(state: "success", creator_id: @grit.owner, environment_url: url)
      old_deployment2.save!

      deployment = create :deployment, repository: @grit, environment: "production"
      deployment.statuses.create(state: "success", creator_id: @grit.owner, environment_url: url)
      deployment.save!
      assert_equal 3, DeploymentStatus.count
      deployment.set_previous_environment_deployments_inactive!(include_production: true, environment_url: url)
      assert_equal 4, DeploymentStatus.count

      assert_equal old_deployment2.reload.latest_state, "inactive"
      assert_equal old_deployment.reload.latest_state, "success"
      assert_equal deployment.reload.latest_state, "success"
    end

    test "maintains log_url of previous status when deployment is auto-inactivated with log persistence feature flag enabled" do
      old_deployment = create :deployment, repository: @grit
      old_deployment.statuses.create(state: "success", creator_id: @grit.owner, log_url: "https://a.com")

      deployment = create :deployment, repository: @grit
      deployment.statuses.create(state: "success", creator_id: @grit.owner)

      assert_equal "https://a.com", old_deployment.reload.latest_status.log_url

      assert_equal 2, DeploymentStatus.count
      deployment.set_previous_environment_deployments_inactive!
      assert_equal 3, DeploymentStatus.count

      assert_equal "inactive", old_deployment.reload.latest_state
      assert_equal "https://a.com", old_deployment.latest_status.log_url
    end
  end

  context "#state" do
    test "is destroyed in a transient inactive environment" do
      deployment = create :deployment
      create :deployment_status, deployment: deployment, creator: deployment.creator, state: "inactive"
      deployment.update_attribute(:transient_environment, true)
      assert_equal "destroyed", deployment.state
      refute_predicate deployment, :active?
    end

    test "is inactive in a non-transient inactive environment" do
      deployment = create :deployment
      create :deployment_status, deployment: deployment, creator: deployment.creator, state: "inactive"
      assert_equal "inactive", deployment.state
      refute_predicate deployment, :active?
    end

    test "with a success status" do
      deployment = create :deployment
      create :deployment_status, deployment: deployment, creator: deployment.creator
      assert_equal "active", deployment.state
      assert_predicate deployment, :active?
    end

    test "with no status" do
      deployment = create :deployment
      assert_equal "pending", deployment.state
      refute_predicate deployment, :active?

      deployment.update_attribute(:created_at, 40.minutes.ago)
      assert_equal "abandoned", deployment.state
      refute_predicate deployment, :active?
    end
  end

  context "#latest_status" do
    test "returns the lastest deployment status when one exists" do
      deployment    = create :deployment, repository: @grit
      first_status  = deployment.statuses.create(log_url: "https://a.com", state: "pending", creator: @defunkt)
      latest_status = deployment.statuses.create(log_url: "https://c.com", state: "success", creator: @defunkt)

      assert_equal deployment.reload.latest_status, latest_status
    end

    test "returns nil when there is no associated deployment status" do
      deployment = create :deployment, repository: @grit
      assert_nil deployment.latest_status
    end
  end

  context "#terminal_status" do
    test "returns the terminal status when one exists" do
      deployment = create :deployment, repository: @grit
      first_status  = deployment.statuses.create(log_url: "https://a.com", state: "pending", creator: @defunkt)
      latest_status = deployment.statuses.create(log_url: "https://c.com", state: "failure", creator: @defunkt)

      assert_equal deployment.reload.terminal_status, latest_status
    end

    test "returns nil when there is no associated deployment status" do
      deployment = create :deployment, repository: @grit
      assert_nil deployment.terminal_status
    end

    test "returns nil when it's not a terminal state" do
      deployment = create :deployment, repository: @grit
      first_status  = deployment.statuses.create(log_url: "https://a.com", state: "pending", creator: @defunkt)
      latest_status = deployment.statuses.create(log_url: "https://c.com", state: "waiting", creator: @defunkt)

      assert_nil deployment.reload.terminal_status
    end
  end

  context "#create_environment" do
    test "creates an environment" do
      deployment = create :deployment, environment: "staging"

      assert_equal 1, deployment.repository.environments.size
      assert_equal "staging", deployment.repository.environments.first.name
      assert_equal deployment.environment_id, deployment.repository.environments.first.id
      assert_equal deployment.latest_environment_id, deployment.repository.environments.first.id
    end

    test "environment ids consistent for same environment" do
      deployment = create :deployment, environment: "newenv"

      assert_equal 1, deployment.repository.environments.size
      assert_equal "newenv", deployment.repository.environments.last.name
      assert_equal deployment.environment_id, deployment.repository.environments.last.id
      assert_equal deployment.latest_environment_id, deployment.repository.environments.last.id

      deployment2 = create :deployment, environment: "newenv"

      assert_equal "newenv", deployment2.repository.environments.last.name
      assert_equal deployment2.environment_id, deployment2.repository.environments.last.id
      assert_equal deployment2.latest_environment_id, deployment2.repository.environments.last.id
    end

    test "creates an environment with 'production' as the default name" do
      deployment    = create :deployment, environment: nil

      assert_equal 1, deployment.repository.environments.size
      assert_equal "production", deployment.repository.environments.first.name
    end

    test "produces an error with an invalid environment name" do
      deployment = Deployment.new(environment: "🥑Toast")

      assert_equal false, deployment.valid?

      deployment = Deployment.new(environment: "morethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255chars")
      assert_equal false, deployment.valid?

      deployment = Deployment.new(latest_environment: "🥑Toast")

      assert_equal false, deployment.valid?

      deployment = Deployment.new(latest_environment: "morethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255chars")
      assert_equal false, deployment.valid?

      assert_raises ActiveRecord::RecordInvalid do
        deployment = create :deployment, environment: "🥑Toast", repository: @grit
      end
    end
  end

  test "still saves even if mysql5 cluster is down" do
    org = create(:organization)
    repo = create(:repository, owner: org)
    user = create(:user)

    commit = repo.heads.read("master").append_commit({ message: "some change", committer: user }, org) do |files|
      files.add("file.txt", "some file content")
    end

    clusters = ApplicationRecord.clusters - [ApplicationRecord::Mysql5]
    allow_connections_to(*clusters) do
      create(:deployment, repository: repo, creator: user, sha: commit.sha)
    end
  end

  test "is deleted with repository" do
    deployment = create :deployment, repository: @grit
    other_deployment = create :deployment

    assert_destroyed_in_background_with_parent do |config|
      config.parent_record = @grit
      config.expect_destroyed = [deployment]
      config.expect_not_destroyed = [other_deployment]
    end
  end
end
