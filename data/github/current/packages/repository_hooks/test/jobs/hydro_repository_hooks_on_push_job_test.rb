# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class HydroRepositoryHooksOnPushJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers

  fixtures do
    @user = create(:user)
    @repository = create(:repository, owner: @user)

    @org = create(:organization, plan: GitHub::Plan.business_plus)
  end

  setup do
    Spokesd.enable_spokesd

    example_repo :post_receive_job_test, @repository

    @commit_sha_before = "c1800491d95c42b4e96fb83f31fe8d9230c62907"
    @commit_sha_after = "63611721afd41f58f801d66e543d8288b4c5eb44"

    @ref = "refs/heads/master"
    @updates = [Git::Ref::Update.new(repository: @repository, refname: @ref, before_oid: @commit_sha_before, after_oid: @commit_sha_after)]

    @time = Time.now
    @message = {
      repository_id: @repository.id,
      request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
      ref_updates: @updates.map { |u| { ref: u.refname, before: u.before_oid, after: u.after_oid } },
      pushed_at: @time,
      pusher: @user.login,
      run_hydro_job: true,
      enabled_flags: Repositories::HydroPushJobFlags::FLAGS.select { |f| GitHub.flipper[f].enabled? },
    }
  end

  test "queues created hook event" do
    Timecop.freeze do
      Hook::Event::CreateEvent.expects(:queue).with(
        repository_id: @repository.id,
        ref: @ref,
        pusher_id: @user.id,
        triggered_at: Time.now,
      )
      message = @message.merge({
        ref_updates: [{ ref: @ref, before: GitHub::NULL_OID, after: @commit_sha_after }],
        })
      perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_repository_hooks_on_push")
    end
  end

  test "queues deleted hook event" do
    Timecop.freeze do
      Hook::Event::DeleteEvent.expects(:queue).with(
        repository_id: @repository.id,
        ref: @ref,
        pusher_id: @user.id,
        triggered_at: Time.now,
      )
      message = @message.merge({
        ref_updates: [{ ref: @ref, before: @commit_sha_before, after: GitHub::NULL_OID }],
      })
      perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_repository_hooks_on_push")
    end
  end

  test "skips create and delete events for refs that aren't branches or tags" do
    Hook::Event::CreateEvent.expects(:queue).never
    message = @message.merge({ ref_updates: [{ ref: "refs/foo/bar", before: GitHub::NULL_OID, after: @commit_sha_after }] })
    perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_repositories_on_push")

    Hook::Event::DeleteEvent.expects(:queue).never
    message = @message.merge({ ref_updates: [{ ref: "refs/foo/bar", before: @commit_sha_before, after: GitHub::NULL_OID }] })
    perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_repositories_on_push")
  end
end
