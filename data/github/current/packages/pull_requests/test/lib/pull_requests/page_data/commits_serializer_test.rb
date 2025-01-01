# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests::PageData
  class CommitsSerializerTest < GitHub::TestCase
    include Commits::ReactPayloadDataDependency

    # Required for Commits::ReactPayloadDataDependency#build_grouped_commits_payload
    def view_context
      TestController.new.view_context
    end

    test "serializes as expected" do
      repository = create(:repository, from_example: :pull_request_history)

      pull = create(:pull_request,
        base_ref: repository.default_branch,
        base_repository: repository,
        base_user: repository.owner,
        head_ref_name: "topic",
        head_repository: repository,
        head_user: repository.owner,
        repository: repository,
        user: repository.owner,
      )

      alive_channel = "pull-requests-commits-channel"
      deferred_commits_data_url = "#{pull.url(include_host: false)}/deferred_commits_data"

      commit_groups = build_grouped_commits_payload(pull.changed_commits, pull.user, order: :asc, pull_request: pull)
      assert_equal pull.changed_commits.size, commit_groups.size

      expected_serialized_metadata = PullRequests::PageData::CommitsSerializer::MetadataData.new(
        aliveChannel: alive_channel,
        deferredCommitsDataUrl: deferred_commits_data_url,
      )

      expected_serialized_repository_data = PullRequests::PageData::CommitsSerializer::RepositoryData.new(
        defaultBranch: repository.default_branch,
        name: repository.name,
        ownerLogin: repository.owner_display_login,
      )

      expected_data = {
        "commitGroups" => commit_groups,
        "metadata" => expected_serialized_metadata,
        "repository" => expected_serialized_repository_data,
        "timeOutMessage" => "",
        "truncated" => false,
      }.as_json

      actual_data = PullRequests::PageData::CommitsSerializer.new(
        alive_channel:,
        commit_groups:,
        deferred_commits_data_url:,
        repository:,
        time_out_message: "",
        truncated: false,
      ).to_hash

      assert_equal expected_data.keys.sort, actual_data.keys.sort
      assert_equal expected_data["commitGroups"].length, actual_data["commitGroups"].length
      assert_equal expected_data["commitGroups"][0]["title"], actual_data["commitGroups"][0]["title"]
      assert_equal expected_data["commitGroups"][0]["commits"].length, actual_data["commitGroups"][0]["commits"].length
      assert_equal expected_data["commitGroups"][0]["commits"][0].keys.sort, actual_data["commitGroups"][0]["commits"][0].keys.sort
      assert_equal expected_data["commitGroups"][0]["commits"][0]["authoredDate"], actual_data["commitGroups"][0]["commits"][0]["authoredDate"]

      assert_equal expected_data["commitGroups"][0]["commits"][0]["authors"][0]["avatarUrl"], actual_data["commitGroups"][0]["commits"][0]["authors"][0]["avatarUrl"]
      assert_equal expected_data["commitGroups"][0]["commits"][0]["authors"][0]["displayName"], actual_data["commitGroups"][0]["commits"][0]["authors"][0]["displayName"]
      assert_nil expected_data["commitGroups"][0]["commits"][0]["authors"][0]["login"]
      assert_nil actual_data["commitGroups"][0]["commits"][0]["authors"][0]["login"]
      assert_nil expected_data["commitGroups"][0]["commits"][0]["authors"][0]["path"]
      assert_nil actual_data["commitGroups"][0]["commits"][0]["authors"][0]["path"]

      assert_equal expected_data["commitGroups"][0]["commits"][0]["bodyMessageHtml"], actual_data["commitGroups"][0]["commits"][0]["bodyMessageHtml"]
      assert_equal expected_data["commitGroups"][0]["commits"][0]["committedDate"], actual_data["commitGroups"][0]["commits"][0]["committedDate"]

      assert_equal expected_data["commitGroups"][0]["commits"][0]["committer"]["avatarUrl"], actual_data["commitGroups"][0]["commits"][0]["committer"]["avatarUrl"]
      assert_equal expected_data["commitGroups"][0]["commits"][0]["committer"]["displayName"], actual_data["commitGroups"][0]["commits"][0]["committer"]["displayName"]
      assert_nil expected_data["commitGroups"][0]["commits"][0]["committer"]["login"]
      assert_nil actual_data["commitGroups"][0]["commits"][0]["committer"]["login"]
      assert_nil expected_data["commitGroups"][0]["commits"][0]["committer"]["path"]
      assert_nil actual_data["commitGroups"][0]["commits"][0]["committer"]["path"]

      assert_equal expected_data["commitGroups"][0]["commits"][0]["committerAttribution"], actual_data["commitGroups"][0]["commits"][0]["committerAttribution"]
      assert_equal expected_data["commitGroups"][0]["commits"][0]["oid"], actual_data["commitGroups"][0]["commits"][0]["oid"]
      assert_equal expected_data["commitGroups"][0]["commits"][0]["shortMessage"], actual_data["commitGroups"][0]["commits"][0]["shortMessage"]
      assert_equal expected_data["commitGroups"][0]["commits"][0]["shortMessageMarkdownLink"], actual_data["commitGroups"][0]["commits"][0]["shortMessageMarkdownLink"]
      assert_equal expected_data["commitGroups"][0]["commits"][0]["url"], actual_data["commitGroups"][0]["commits"][0]["url"]

      assert_same_hash(expected_data["metadata"], actual_data["metadata"])
      assert_same_hash(expected_data["repository"], actual_data["repository"])
      assert_equal expected_data["timeOutMessage"], actual_data["timeOutMessage"]
      assert_equal expected_data["truncated"], actual_data["truncated"]
    end
  end
end
