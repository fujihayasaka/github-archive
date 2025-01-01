# typed: true
# frozen_string_literal: true

require "test_helper"

class CreateArtifactsJobTest < GitHub::TestCase
  setup do
    GitHub.stubs(:actions_enabled?).returns(true)
    GitHub.flipper[:actions_create_artifacts_job_reduce_primary_reads].disable
  end

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user = create(:user, plan: "pro")
    @repo = create(:repository, name: "hello-world", owner: @user, from_example: :rebase_pull_request)


    commit = @repo.heads.find("contrib").append_commit({ message: "blah", committer: @user }, @user) do |files|
      files.add("foo", "dsfdsfsdfsd")
    end
    @sha = commit.oid

    make_trusted_oauth_apps_owner

    @check_suite = create(
      :check_suite_for_actions_app,
      repository: @repo,
      head_sha: @sha,
      head_branch: nil
    )

    created_at = DateTime.current
    expires_at = DateTime.current + 1.day

    @artifacts = [{
      name: "Artifact 1",
      source_url: "https://dev.azure.com/Account/project/_build/artifacts_1.zip",
      size: 102400,
      created_at: created_at,
      expires_at: expires_at,
      repository_id: @repo.id,
    }]
  end

  def subject
    CreateArtifactsJob.new
  end

  test "calls service with correct arguments" do
    Checks::CreateArtifacts.expects(:call).with(has_entries(
      check_suite: responds_with(:id, @check_suite.id),
      artifacts: @artifacts,
    ))

    subject.perform(
      check_suite_id: @check_suite.id,
      artifacts: @artifacts,
    )
  end
end
