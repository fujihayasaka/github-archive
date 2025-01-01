# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::AttachPullRequestJobTest < GitHub::TestCase
  fixtures do
    @user = create(:user, plan: GitHub::Plan.pro)
    @repo = create(:repository, owner: @user, from_example: :simple)
  end

  def create_pull_for_codespace(codespace)
    ref = @repo.heads.find_or_build("master")
    head_ref = @repo.heads.create(codespace.ref, ref.target, @user)
    head_ref.append_commit({ message: "some changes", committer: @user }, @user) do |files|
      files.add("file001", "foo")
    end
    pull_request = create(:pull_request, repository: @repo, base_repository: @repo, head_repository: @repo,  user: @user, base_ref: "master", head_ref: codespace.ref)
  end

  test "it updates the codespace to point to the provided PR when things match", skip_enterprise: true do
    codespace = create(:codespace, repository: @repo, owner: @user)

    pull_request = create_pull_for_codespace(codespace)

    Codespaces::AttachPullRequestJob.perform_now(pull_request: pull_request)
    assert_equal pull_request, codespace.reload.pull_request
  end

  test "it does not update the codespace PR if the codespace owner is not the PR author", skip_enterprise: true do

    other_user = create(:user)
    codespace = create(:codespace, owner: other_user, repository: @repo)

    pull_request = create_pull_for_codespace(codespace)

    Codespaces::AttachPullRequestJob.perform_now(pull_request: pull_request)
    refute codespace.reload.pull_request
  end

  test "it adds :codespace as the PR's pull_request_source", skip_enterprise: true do
    codespace = create(:codespace, repository: @repo, owner: @user)

    pull_request = create_pull_for_codespace(codespace)

    Codespaces::AttachPullRequestJob.perform_now(pull_request: pull_request)
    assert pull_request.pull_request_sources.where(source: :codespace).exists?
  end
end
