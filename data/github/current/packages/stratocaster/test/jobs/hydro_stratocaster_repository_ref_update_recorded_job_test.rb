# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroStratocasterRepositoryRefUpdateRecordedJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers

  fixtures do
    @user = create(:user)
    @repository = create(:repository, owner: @user)

    @commit_sha_before = "c1800491d95c42b4e96fb83f31fe8d9230c62907"
    @commit_sha_after = "63611721afd41f58f801d66e543d8288b4c5eb44"
    @ref = "refs/heads/master"

    @created = create(:push, repository: @repository, pusher: @user, ref: @ref, before: GitHub::NULL_OID, after: @commit_sha_after)
    @push = create(:push, repository: @repository, pusher: @user, ref: @ref, before: @commit_sha_before, after: @commit_sha_after)
    @deleted = create(:push, repository: @repository, pusher: @user, ref: @ref, before: @commit_sha_after, after: GitHub::NULL_OID)
  end

  test "push created" do
    assert @created.created?

    message = {
      actor_id: @user.id,
      request_context: Hydro::EntitySerializer.request_context(GitHub.context),
      repository_id: @repository.id,
      push_id: @created.id,
      before: @created.before,
      after: @created.after,
      ref: @created.ref,
      feature_flags: [],
    }

    GitHub.stratocaster.stubs(:queue).never

    perform_hydro_message_job(message, schema: "github.repositories.v1.RefUpdateRecorded", queue: "hydro_stratocaster_repository_ref_update_recorded")
  end

  test "push" do
    refute @push.created?
    refute @push.deleted?

    message = {
      actor_id: @user.id,
      request_context: Hydro::EntitySerializer.request_context(GitHub.context),
      repository_id: @repository.id,
      push_id: @push.id,
      before: @push.before,
      after: @push.after,
      ref: @push.ref,
      feature_flags: [],
    }

    GitHub.stratocaster.stubs(:queue).once.with(Stratocaster::Event::PUSH_EVENT, @push.id, @repository.id, @user.id)

    perform_hydro_message_job(message, schema: "github.repositories.v1.RefUpdateRecorded", queue: "hydro_stratocaster_repository_ref_update_recorded")
  end

  test "push deleted" do
    assert @deleted.deleted?

    message = {
      actor_id: @user.id,
      request_context: Hydro::EntitySerializer.request_context(GitHub.context),
      repository_id: @repository.id,
      push_id: @deleted.id,
      before: @deleted.before,
      after: @deleted.after,
      ref: @deleted.ref,
      feature_flags: [],
    }

    GitHub.stratocaster.stubs(:queue).never

    perform_hydro_message_job(message, schema: "github.repositories.v1.RefUpdateRecorded", queue: "hydro_stratocaster_repository_ref_update_recorded")
  end
end
