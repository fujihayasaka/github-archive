# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class RepositorySummarizerJobTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include JobTestHelper

  fixtures do
    @org = create :organization
    @user = create :user
    @repo = create(:repository, from_example: :simple, owner: @org)
  end

  setup do
    GitHub.flipper[:copilot_chat_magic_kbs].enable
  end

  test "simulates generating a repo description using file names" do
    ref = @repo.default_branch_ref
    ref.append_commit({ message: "blah", committer: @user }, @user) do |files|
      files.add("README.md", "change")
    end

    GitHub::Spokes::Client::Spokesd.any_instance.stubs(:get_all_filepaths_from_repo)
    .returns(["README.md"])
    Copilot::User::CopilotApi
      .any_instance
      .stubs(:create_chat_completion)
      .returns({ "choices" => [{ "message" => { "content" => "This file is a README.md" } }] })
    Copilot::User::CopilotApi
      .any_instance
      .stubs(:create_embedding)
      .returns({ "data" => [{ "embedding" => [5.695693, 0.0077387304, 0.025226949] }] })
    Copilot::User::CopilotApi
      .any_instance
      .expects(:update_knowledge_base_repo_description)
      .with("abc", @repo.id, "This file is a README.md", [5.695693, 0.0077387304, 0.025226949]).once

    RepositorySummarizerJob.perform_now(@repo, @org, "abc")
  end

  test "simulates generating a repo description using file content" do
    GitHub.flipper[:copilot_chat_magic_kbs_file_content_summarizer].enable

    ref = @repo.default_branch_ref
    ref.append_commit({ message: "blah", committer: @user }, @user) do |files|
      files.add("README.md", "change")
    end

    GitHub::Spokes::Client::Spokesd.any_instance.stubs(:get_all_filepaths_from_repo)
    .returns(["README.md"])
    Copilot::User::CopilotApi
      .any_instance
      .stubs(:create_chat_completion)
      .returns({ "choices" => [{ "message" => { "content" => "This file is a README.md" } }] })
    Copilot::User::CopilotApi
      .any_instance
      .stubs(:create_embedding)
      .returns({ "data" => [{ "embedding" => [5.695693, 0.0077387304, 0.025226949] }] })
    Copilot::User::CopilotApi
      .any_instance
      .expects(:update_knowledge_base_repo_description)
      .with("abc", @repo.id, "This file is a README.md", [5.695693, 0.0077387304, 0.025226949]).once

    RepositorySummarizerJob.perform_now(@repo, @org, "abc")
  end
end
