# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroAuthenticCommitsJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include DogstatsTestHelpers

  fixtures do
    @repository = create(:repository, from_example: :simple)
    @web_committer = create(:user, :verified, login: "web-flow", email: GitHub.web_committer_email)
    @web_committer.gpg_keys.create_from_armored_public_key(GitHub.gpg.signing_key)
  end

  setup do
    @message = {
      repository_id: @repository.id,
      enabled_flags: [],
    }

    Spokesd.enable_spokesd
    GitHub.stubs(:web_commit_signing_enabled?).returns(true)
  end

  context "commit_shas is populated" do
    test "verifies and saves commits" do
      list_commits_response = list_commits_response(@repository, size: 5)
      oids = list_commits_response.commits.map(&:oid).map(&:id)
      SpokesAPI::Client.any_instance.stubs(:list_commits_for_ids).returns(list_commits_response)

      GitHub.gpg.expects(:batch_verify).with do |requests|
        assert_equal requests.map { |r| r[:id] }, oids
      end.returns(oids.map { |id| [id, GpgVerify::VALID] }.to_h)

      assert_changes -> { AuthenticCommit.count }, from: 0, to: 5 do
        perform_hydro_message_job(@message.merge(commit_shas: oids), schema: "github.repositories.v1.CommitsCreated", queue: "hydro_authentic_commits")
      end

      assert_dogstats_count_value 5, "authentic_commits_job.commits.count", tags: ["signed_by_github:true", "type:gpg"]
    end

    test "paginates through commits" do
      first_page = list_commits_response(@repository, size: 5, has_next_page: true)
      second_page = list_commits_response(@repository, size: 5)
      first_page_oids = first_page.commits.map(&:oid).map(&:id)
      second_page_oids = second_page.commits.map(&:oid).map(&:id)

      SpokesAPI::Client.any_instance.stubs(:list_commits_for_ids).returns(first_page).then.returns(second_page)
      GitHub.gpg.expects(:batch_verify).twice.returns(first_page_oids.map { |id| [id, GpgVerify::VALID] }.to_h).then.returns(second_page_oids.map { |id| [id, GpgVerify::VALID] }.to_h)

      assert_changes -> { AuthenticCommit.count }, from: 0, to: 10 do
        perform_hydro_message_job(@message.merge(commit_shas: first_page_oids + second_page_oids,), schema: "github.repositories.v1.CommitsCreated", queue: "hydro_authentic_commits")
      end

      stats = assert_dogstats_count "authentic_commits_job.commits.count", tags: ["signed_by_github:true", "type:gpg"]
      assert_equal 2, stats.size # one report for each page
      assert_equal 10, stats.sum(&:value) # totaling 10 commits
    end

    test "handles unsigned commits" do
      list_commits_response = list_commits_response(@repository, size: 5, sign: false)
      oids = list_commits_response.commits.map(&:oid).map(&:id)
      SpokesAPI::Client.any_instance.stubs(:list_commits_for_ids).returns(list_commits_response)

      perform_hydro_message_job(@message.merge(commit_shas: oids), schema: "github.repositories.v1.CommitsCreated", queue: "hydro_authentic_commits")

      assert_dogstats_count_value 5, "authentic_commits_job.commits.count", tags: ["type:unsigned"]
    end
  end

  context "start_sha and end_sha are populated" do
    test "verifies and saves commits" do
      list_commits_response = list_commits_response(@repository, size: 5)
      oids = list_commits_response.commits.map(&:oid).map(&:id)
      SpokesAPI::Client.any_instance.stubs(:list_commits_for_revisions).returns(list_commits_response)

      GitHub.gpg.expects(:batch_verify).with do |requests|
        assert_equal requests.map { |r| r[:id] }, oids
      end.returns(oids.map { |id| [id, GpgVerify::VALID] }.to_h)

      assert_changes -> { AuthenticCommit.count }, from: 0, to: 5 do
        perform_hydro_message_job(@message.merge(start_sha: oids[0], end_sha: oids[4]), schema: "github.repositories.v1.CommitsCreated", queue: "hydro_authentic_commits")
      end

      assert_dogstats_count_value 5, "authentic_commits_job.commits.count", tags: ["signed_by_github:true", "type:gpg"]
    end

    test "paginates through commits" do
      first_page = list_commits_response(@repository, size: 5, has_next_page: true)
      second_page = list_commits_response(@repository, size: 5)
      first_page_oids = first_page.commits.map(&:oid).map(&:id)
      second_page_oids = second_page.commits.map(&:oid).map(&:id)

      SpokesAPI::Client.any_instance.stubs(:list_commits_for_revisions).returns(first_page).then.returns(second_page)
      GitHub.gpg.expects(:batch_verify).twice.returns(first_page_oids.map { |id| [id, GpgVerify::VALID] }.to_h).then.returns(second_page_oids.map { |id| [id, GpgVerify::VALID] }.to_h)

      assert_changes -> { AuthenticCommit.count }, from: 0, to: 10 do
        perform_hydro_message_job(@message.merge(start_sha: first_page_oids[0], end_sha: second_page_oids[4]), schema: "github.repositories.v1.CommitsCreated", queue: "hydro_authentic_commits")
      end

      stats = assert_dogstats_count "authentic_commits_job.commits.count", tags: ["signed_by_github:true", "type:gpg"]
      assert_equal 2, stats.size # one report for each page
      assert_equal 10, stats.sum(&:value) # totaling 10 commits
    end

    test "handles unsigned commits" do
      list_commits_response = list_commits_response(@repository, size: 5, sign: false)
      oids = list_commits_response.commits.map(&:oid).map(&:id)
      SpokesAPI::Client.any_instance.stubs(:list_commits_for_revisions).returns(list_commits_response)

      perform_hydro_message_job(@message.merge(start_sha: oids[0], end_sha: oids[4]), schema: "github.repositories.v1.CommitsCreated", queue: "hydro_authentic_commits")

      assert_dogstats_count_value 5, "authentic_commits_job.commits.count", tags: ["type:unsigned"]
    end
  end

  test "sets read_after_write flag for Spokes API" do
    list_commits_response = list_commits_response(@repository, size: 5, sign: false)

    GitHub::Spokes::Proto::Commits::V1::CommitsAPIClient.any_instance.expects(:list_commits).twice.with do |request|
      assert request[:request_context][:read_after_write]
    end.returns(Struct.new(:error, :data).new(nil, list_commits_response))

    perform_hydro_message_job(@message.merge(commit_shas: [SecureRandom.hex(20)]), schema: "github.repositories.v1.CommitsCreated", queue: "hydro_authentic_commits")
    perform_hydro_message_job(@message.merge(start_sha: SecureRandom.hex(20), end_sha: SecureRandom.hex(20)), schema: "github.repositories.v1.CommitsCreated", queue: "hydro_authentic_commits")
  end


  private

  def list_commits_response(repository, size:, has_next_page: nil, sign: true)
    commits = size.times.map do
      repository.default_branch_ref.append_commit({ message: "A commit", author: repository.owner }, repository.owner, { sign: sign })
    end

    GitHub::Spokes::Proto::Commits::V1::ListCommitsResponse.new(
      commits: commits.map do |commit|
        {
          oid: { id: commit.oid },
          commit_content: {
            message: commit.message,
            gpg_signature: commit.signature,
            committer: { name: commit.committer_name, email: commit.committer_email },
          }
        }
      end,

      next_cursor: has_next_page && { cursor: "cursor" },
    )
  end
end
