# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryContentsTest < Api::TestCase
  include AuditLog::IntegrationTestHelpers

  fixtures do
    @repo = create(:repository, from_example: :pull_request_source)
    @xcode_repo = make_xcode_repository
  end

  context "#xcode_project?" do
    test "xcode directory returns true" do
      assert @xcode_repo.xcode_project?
    end

    test "no xcode directory returns false" do
      refute @repo.xcode_project?
    end
  end

  context "repo downloads" do
    test "instruments download_zip event for private repo" do
      user = create(:user)
      private_repo = create(:private_repository, owner: user, from_example: :readme_markdown)

      auth_as user

      events = assert_performed_audit_entries(count: 1, only: "repo.download_zip") do
        api :get, "repos/#{private_repo.name_with_owner}/zipball",
          skip_openapi_request_validation: true
      end

      expected_payload = {
        repo: private_repo.name_with_owner,
      }

      assert_subset_hash expected_payload, events.first
    end
  end

  private

  def make_xcode_repository
    repo = create(:repository, from_example: :pull_request_source)
    base_ref = repo.heads.find("master")
    base_ref.append_commit(
      { message: "new file", committer: repo.owner },
      repo.owner) { |files| files.add(".xcodeproj/anything.txt", "line 1") }
    repo
  end
end
