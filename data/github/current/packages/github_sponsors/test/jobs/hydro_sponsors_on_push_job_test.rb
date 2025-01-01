# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/spokesd"

class HydroSponsorsOnPushJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include PushTestHelper
  include HydroTestHelpers

  fixtures do
    @repo = create(:public_repository, from_example: :simple)

    example_repo_snapshot
  end

  setup do
    example_repo_restore

    Spokesd.enable_spokesd
  end

  test "instruments funding links file change in audit log" do
    expected_payload = {
      visibility: :public,
      repo: @repo.nwo,
      repo_id: @repo.id,
      public_repo: @repo.public?,
      fork_source: @repo.nwo,
      fork_source_id: @repo.id,
      user: @repo.owner.login,
      user_id: @repo.owner_id,
      actor: @repo.owner.login,
      actor_id: @repo.owner_id,
    }
    events = subscribe "sponsors.repo_funding_links_file_action"

    perform_push_hydro_job(
      repository: @repo,
      job_class: HydroSponsorsOnPushJob,
      changes: { path: "funding.yml", content: "irrelevant" }
    )

    refute_nil event = events.pop, "should have had an audit log event"
    assert_equal expected_payload, event.payload
  end

  test "instruments funding links file change to hydro" do
    reset_hydro

    assert_hydro_messages(count: 0, schema: "github.v1.FundingFileAction")
    perform_push_hydro_job(
      repository: @repo,
      job_class: HydroSponsorsOnPushJob,
      changes: { path: "funding.yml", content: "irrelevant" }
    )
    assert_hydro_messages(count: 1, schema: "github.v1.FundingFileAction")
  end

  test "nothing is instrumented when no funding file is changed" do
    events = subscribe "sponsors.repo_funding_links_file_action"

    perform_push_hydro_job(
      repository: @repo,
      job_class: HydroSponsorsOnPushJob,
      changes: { path: "README.md", content: "irrelevant" }
    )

    assert_nil event = events.pop, "should not have had an audit log event"
  end

  test "nothing is instrumented when push is not recordable" do
    events = subscribe "sponsors.repo_funding_links_file_action"

    Repositories::RefUpdate.any_instance.stubs(:recordable?).returns(false)
    perform_push_hydro_job(
      repository: @repo,
      job_class: HydroSponsorsOnPushJob,
      changes: { path: "funding.yml", content: "irrelevant" }
    )

    assert_nil event = events.pop, "should not have had an audit log event"
  end

  test "nothing is instrumented when push is not on default branch" do
    events = subscribe "sponsors.repo_funding_links_file_action"

    perform_push_hydro_job(
      repository: @repo,
      branch_name: "non-default-branch",
      create_branch: true,
      job_class: HydroSponsorsOnPushJob,
      changes: { path: "funding.yml", content: "irrelevant" }
    )

    assert_nil event = events.pop, "should not have had an audit log event"
  end

  test "nothing is instrumented when funding links are not enabled" do
    events = subscribe "sponsors.repo_funding_links_file_action"
    @repo.disable_repository_funding_links(actor: @repo.owner)
    refute_predicate @repo, :repository_funding_links_enabled?

    perform_push_hydro_job(
      repository: @repo,
      job_class: HydroSponsorsOnPushJob,
      changes: { path: "funding.yml", content: "irrelevant" }
    )

    assert_nil event = events.pop, "should not have had an audit log event"
  end
end
