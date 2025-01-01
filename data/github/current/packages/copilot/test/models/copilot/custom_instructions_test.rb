# typed: strict
# frozen_string_literal: true

require "test_helper"

class Copilot::CustomInstructionsTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  test "factory works" do
    activity = create(:custom_instructions)
    assert activity.persisted?
  end

  test "for user" do
    user = create(:user)
    Copilot::CustomInstructions.create(owner: user, prompt: "User instructions")
    assert_equal T.must(Copilot::CustomInstructions.for_user(user)).prompt, "User instructions"
  end

  test "for repository" do
    Copilot::CustomInstructions.create(owner: create(:organization), prompt: "Org instructions")
    repo = create(:repository, owner: create(:organization), name: "test-repo")
    ref = repo.heads.find_or_build("master")
    ref.append_commit({ message: "a change", committer: repo.owner }, repo.owner) do |files|
      files.add(Copilot::CustomInstructions::REPO_CUSTOM_INSTRUCTIONS_PATH, "Repo instructions")
    end

    assert_equal Copilot::CustomInstructions.for_repository(repo, repo.default_oid), "Repo instructions"
  end

  test "for organization" do
    org = create(:organization)
    Copilot::CustomInstructions.create(owner_id: org.id, owner_type: :Organization,  prompt: "Org instructions")
    assert_equal T.must(Copilot::CustomInstructions.for_organization(org)).prompt, "Org instructions"
  end
end if GitHub.copilot_enabled?
