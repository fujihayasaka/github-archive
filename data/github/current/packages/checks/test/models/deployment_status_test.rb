# typed: true
# frozen_string_literal: true

require "test_helper"

class DeploymentStatusTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, login: "mojombo2", plan: "medium")
    @defunkt  = create(:user, login: "defunkt", plan: "medium")

    @grit     = create(:repository, name: "grit", owner: @owner)
    @sha1     = "abcde" * 8

    reset_repo_root
    example_repo :mojombo_grit, @grit # rubocop:disable GitHub/UseFromExampleInRepositoryFactory

    default = @grit.heads.find(@grit.default_branch)
    topic   = @grit.heads.create("topic", default.target_oid, @grit.owner)

    topic.append_commit({ message: "blah", committer: @grit.owner }, @grit.owner) do |files|
      files.add("blah.txt", "blahblahblah")
    end

    @pull = PullRequest.create_for(@grit,
      user: @grit.owner,
      base: "#{@grit.owner}:master",
      head: "#{@grit.owner}:topic",
      title: "blah",
      body: "blah",
    )

    @deployment = create(:deployment, repository: @grit, sha: @pull.head_sha)
  end

  setup do
    reset_repo_root
    example_repo :mojombo_grit, @grit
  end

  context "success scope" do
    test "returns deployment statuses with state=success" do
      success_status = create(:deployment_status, :success, deployment: @deployment)
      assert_predicate success_status, :succeeded?
      failure_status = create(:deployment_status, :failure, deployment: @deployment)
      refute_predicate failure_status, :succeeded?

      result = DeploymentStatus.success

      assert_includes result, success_status
      refute_includes result, failure_status
    end
  end

  test "fixture" do
    deployment_status = create :deployment_status
  end

  test "defaults to unknown state" do
    assert_equal "unknown", DeploymentStatus.new.state
  end

  test "notifies websockets for pull requests when deployment succeeds", feature_disabled: :pr_channel_event_payload_builder do
    freeze_time do
      expects_pull_request_notification(pull: @pull).once
      expects_pull_request_deployed_notification(pull: @pull).once

      create(:deployment_status, :success, deployment: @deployment)
    end
  end

  test "notifies websockets for pull requests when deployment succeeds with event_updates", feature_enabled: :pr_channel_event_payload_builder do
    freeze_time do
      event_updates = GitHub.flipper[:skip_full_sidebar_updates].enabled? ? { timeline_updated: true } : { sidebar_updated: true, timeline_updated: true }
      expects_pull_request_notification(pull: @pull, extra_payload: { event_updates: event_updates }).once
      expects_pull_request_deployed_notification(pull: @pull).once
      create(:deployment_status, :success, deployment: @deployment)
    end
  end

  test "does not notify deployment_success channel when deployment fails", feature_disabled: :pr_channel_event_payload_builder do
    freeze_time do
      expects_pull_request_notification(pull: @pull).once
      expects_pull_request_deployed_notification(pull: @pull).never

      create(:deployment_status, :failure, deployment: @deployment)
    end
  end

  test "creating multiple deployment statuses for the same sha" do
    params = {
      state: "pending",
      creator: @owner,
      deployment: @deployment,
      log_url: "https://heaven.githubapp.com/apps/github/logs/420",
    }
    DeploymentStatus.create! params
    DeploymentStatus.create! params.merge(state: "failure")
  end

  test "cannot create more than the limit of statuses per id" do
    DeploymentStatus.stubs(:max_per_deployment).returns(5)
    deployment = @deployment
    5.times do |_i|
      status = create :deployment_status, deployment: deployment, creator: @owner
    end
    status = build :deployment_status, deployment: deployment, creator: @owner
    refute status.valid?, "This status should be invalid"
    assert_equal "This deployment has reached the maximum number of statuses.", status.errors[:base].first
  end

  context "environment" do
    test "defaults environment to deployment environment" do
      status = create(:deployment_status, deployment: @deployment)

      assert status.environment
      assert_equal status.environment, @deployment.environment
    end

    test "if previous status does not have an environment, use deployment environment" do
      first_status = create(:deployment_status, deployment: @deployment)
      first_status.update_column(:environment, nil)

      second_status = create(:deployment_status, deployment: @deployment)

      refute first_status.environment
      assert second_status.environment

      assert_equal second_status.environment, @deployment.environment
    end

    test "uses previous status environment if available" do
      first_status = create(:deployment_status,
                       deployment: @deployment,
                       environment: "foo")

      second_status = create(:deployment_status, deployment: @deployment)

      assert_equal second_status.environment, first_status.environment
    end

    test "uses correct previous status environment if there are more than one" do
      first_status = create(:deployment_status,
                      deployment: @deployment,
                      environment: "first env")

      second_status = create(:deployment_status,
                        deployment: @deployment,
                        environment: "second env")

      third_status = create(:deployment_status, deployment: @deployment)

      assert_equal third_status.environment, second_status.environment
      refute_equal third_status.environment, first_status.environment
    end
  end

  context "state validation" do
    test "can be saved with valid state" do
      status = DeploymentStatus.new(state: "pending", creator: @owner, deployment: @deployment)

      assert status.save
    end

    test "cannot be saved with invalid state" do
      status = DeploymentStatus.new(state: "not-a-state", creator: @owner, deployment: @deployment)

      refute status.save
      assert status.errors[:state]
    end
  end

  context "instrumentation" do
    test "triggers deployment_status.create after create" do
      events = subscribe "deployment_status.create"
      deployment_status = create :deployment_status, state: "pending"
      expected_payload = {
        deployment_status_id: deployment_status.id,
      }

      assert event = events.pop, "expected deployment_status.create event"
    end

    test "triggers deployment_status.update after update" do
      events = subscribe "deployment_status.update"
      deployment_status = create :deployment_status, state: "pending"
      deployment_status.update state: "success"
      expected_payload = {
        deployment_status_id: deployment_status.id,
        deployment_status_state: deployment_status.state,
        public_repo: deployment_status.repository.public?,
      }

      assert event = events.pop, "expected deployment_status.update event"
      assert_equal expected_payload, event.payload
    end
  end

  context "issue events" do
    test "does not create issue event when a first status is created and the environment is not updated" do
      assert_no_difference "@pull.issue.events.count" do
        status = DeploymentStatus.create(state: "pending", creator: @owner, deployment: @deployment)
      end
    end

    test "does not create issue event when the new env is the same as the previous status environment" do
      status = DeploymentStatus.create(state: "pending", creator: @owner, deployment: @deployment, environment: "OLD ENVIRONMENT")

      assert_no_difference "@pull.issue.events.count" do
        status = DeploymentStatus.create(state: "pending", creator: @owner, deployment: @deployment, environment: "OLD ENVIRONMENT")
      end
    end

    test "creates issue event when first status updates the environment" do
      assert_difference "@pull.issue.events.count", 1 do
        status = DeploymentStatus.create(state: "pending", creator: @owner, deployment: @deployment, environment: "IM NEW")

        event = @pull.issue.events.last

        assert_equal "deployment_environment_changed", event.event
        assert_equal status.id, event.deployment_status_id
        assert_equal "IM NEW", event.deployment_status.environment
      end
    end

    test "creates issue event when the environment is updated a second time" do
      status = DeploymentStatus.create(state: "pending", creator: @owner, deployment: @deployment, environment: "IM NEW")

      assert_difference "@pull.issue.events.count", 1 do
        status = DeploymentStatus.create(state: "pending", creator: @owner, deployment: @deployment, environment: "IM EVEN NEWER")

        event = @pull.issue.events.last

        assert_equal "deployment_environment_changed", event.event
        assert_equal status.id, event.deployment_status_id
        assert_equal "IM EVEN NEWER", event.deployment_status.environment
      end
    end
  end

  context "#update_deployments_latest_status_and_environment" do
    test "updates the parent deployment's latest deployment status id" do
      assert_nil @deployment.latest_deployment_status_id

      status = create(:deployment_status, deployment: @deployment)
      assert_equal @deployment.latest_deployment_status_id, status.id
    end

    test "updates the parent deployment's latest status state" do
      assert_nil @deployment.latest_status_state

      status = create(:deployment_status, deployment: @deployment)
      assert_equal @deployment.latest_status_state, status.state
    end

    test "updates latest deployment status then notifies sockets of successful deployment", feature_disabled: :pr_channel_event_payload_builder do
      @deployment.update_attribute(:latest_status_state, "failure")
      refute_predicate @deployment.reload, :succeeded?

      freeze_time do
        expects_pull_request_notification(pull: @pull).once
        expects_pull_request_deployed_notification(pull: @pull).once

        create(:deployment_status, :success, deployment: @deployment)

        assert_predicate @deployment.reload, :succeeded?
      end
    end

    test "updates latest deployment status then notifies sockets of successful deployment with event_updates and timeline_updated", feature_enabled: :pr_channel_event_payload_builder do
      @deployment.update_attribute(:latest_status_state, "failure")
      refute_predicate @deployment.reload, :succeeded?

      freeze_time do
        event_updates = GitHub.flipper[:skip_full_sidebar_updates].enabled? ? { timeline_updated: true } : { sidebar_updated: true, timeline_updated: true }
        expects_pull_request_notification(pull: @pull, extra_payload: { event_updates: event_updates }).once
        expects_pull_request_deployed_notification(pull: @pull).once

        create(:deployment_status, :success, deployment: @deployment)

        assert_predicate @deployment.reload, :succeeded?
      end
    end
  end

  context "#create_environment" do
    test "creates an environment" do
      deployment = create :deployment, environment: nil
      deployment_status = create :deployment_status, state: "pending", deployment: deployment, environment: "staging"

      assert_equal 2, deployment.repository.environments.size
      assert_equal "staging", deployment.repository.environments.last.name
    end

    test "does not create an environment if it is not defined" do
      deployment = create :deployment, environment: "staging"
      deployment_status = create :deployment_status, state: "pending", deployment: deployment, environment: nil

      assert_equal 1, deployment.repository.environments.size
      assert_equal "staging", deployment.repository.environments.first.name
    end

    test "creating a deployment status does not re-create a deleted environment if inactive" do
      deleted_env = create(:environment, repository: @grit)
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob, BatchInactivateDeploymentsJob]) do
        deleted_env.destroy
      end

      deployment = create :deployment, environment: nil, repository: @grit
      deployment_status = create :deployment_status, state: "inactive", deployment: deployment, environment: deleted_env.name

      # Find by name since the re-created environment wouldn't necessarily have the same ID.
      assert Environment.find_by(name: deleted_env.name).nil?
    end

    test "creating a deployment status re-creates a deleted environment if status is not inactive" do
      deleted_env = create(:environment, repository: @grit)
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob, BatchInactivateDeploymentsJob]) do
        deleted_env.destroy
      end

      deployment = create :deployment, environment: nil, repository: @grit
      deployment_status = create :deployment_status, state: "pending", deployment: deployment, environment: deleted_env.name

      # Find by name since the re-created environment wouldn't necessarily have the same ID.
      assert Environment.find_by(name: deleted_env.name).present?
    end
  end

  test "sets `repository_id` from the pull" do
    deployment_status = create(:deployment_status, deployment: @deployment)

    refute_nil deployment_status.repository_id
    assert_equal deployment_status.repository_id, deployment_status.deployment.repository_id
  end

  context "#call_auto_merge_job_enqueuer" do
    test "creation of a successful deployment status triggers a call to enqueue_auto_merge_job_if_enabled" do
      assert @deployment.pull_requests.size > 0
      @deployment.pull_requests.each do |pull_request|
        pull_request.expects(:enqueue_auto_merge_job_if_enabled).once
      end

      deployment_status = create :deployment_status, state: "success", deployment: @deployment
    end
  end

  context "environment_url" do
    test "sets environment_url appropriately when provided" do
      url = "https://example.com/foo"
      deployment_status = create :deployment_status, deployment: @deployment, environment_url: url
      assert_equal deployment_status.environment_url, url
    end

    test "strips whitespace from environment_url" do
      url = "     https://example.com/foo    "
      stripped_url = url.strip
      deployment_status = create :deployment_status, deployment: @deployment, environment_url: url
      assert_equal deployment_status.environment_url, stripped_url
    end

    test "sets nil environment_url when nil or whitespace provided" do
      whitespace_url = "          "
      empty_url = ""
      nil_url = nil

      deployment_status_whitespace_url = create :deployment_status, deployment: @deployment, environment_url: whitespace_url
      deployment_status_empty_url = create :deployment_status, deployment: @deployment, environment_url: empty_url
      nil_deployment_status_nil_url = create :deployment_status, deployment: @deployment, environment_url: nil_url

      assert_nil deployment_status_whitespace_url.environment_url
      assert_nil deployment_status_empty_url.environment_url
      assert_nil nil_deployment_status_nil_url.environment_url
    end
  end

  def expects_pull_request_notification(pull:, extra_payload: {})
    GitHub::WebSocket.expects(:notify_pull_request_channel).with(
      pull,
      GitHub::WebSocket::Channels.pull_request(pull),
      {
        timestamp: Time.now.to_i,
        wait: pull.default_live_updates_wait,
        reason: "pull request ##{pull.id} updated",
        gid: pull.global_relay_id,
      }.merge(extra_payload)
    )
  end

  def expects_pull_request_deployed_notification(pull:)
    GitHub::WebSocket.expects(:notify_pull_request_channel).with(
      pull,
      GitHub::WebSocket::Channels.pull_request_deployed(pull),
      {
        timestamp: Time.now.to_i,
        wait: pull.default_live_updates_wait,
        reason: "pull request ##{pull.id} deployment succeeded",
      }
    )
  end
end
