# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestUserReviewedFilesDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @new_user = create(:user)
    repo = create(:repository, owner: @user, from_example: :pull_request_source)
    head_ref = repo.heads.create("views", repo.heads.find("master").target, @user)
    head_ref.append_commit({ message: "a change", committer: @user }, @user) do |files|
      files.add("README.txt", "one\ntwo\nthree\n")
      files.add("file001", "hi")
      files.add("file002", "bye")
      files.add("file003", "dismissed")
    end
    @pull = create(:pull_request, repository: repo, base_repository: repo, base_user: @user,
                  base_ref: "master", head_repository: repo, head_user: @user, head_ref: "views",
                  user: @user)
  end

  context "#async_viewer_viewed_files" do
    test "returns all reviewed files for a user for a pull request" do
      file1 = @user.reviewed_files.create(filepath: "file001", pull_request_id: @pull.id, head_sha: @pull.head_sha)
      file2 = @user.reviewed_files.create(filepath: "file002", pull_request_id: @pull.id, head_sha: @pull.head_sha)
      file3 = @user.reviewed_files.create(filepath: "file002", pull_request_id: @pull.id, head_sha: @pull.head_sha, dismissed: true)

      assert_same_elements [file1, file2], @pull.async_viewer_viewed_files(@user).sync
    end

    test "returns an empty array if the user has reviewed no files" do
      file1 = @user.reviewed_files.create(filepath: "file001", pull_request_id: @pull.id, head_sha: @pull.head_sha)
      file2 = @user.reviewed_files.create(filepath: "file002", pull_request_id: @pull.id, head_sha: @pull.head_sha)
      file3 = @new_user.reviewed_files.create(filepath: "file002", pull_request_id: @pull.id, head_sha: @pull.head_sha, dismissed: true)

      assert_same_elements [], @pull.async_viewer_viewed_files(@new_user).sync
    end
  end
end
