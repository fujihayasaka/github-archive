# typed: true
# frozen_string_literal: true

require "test_helper"

class DeployInstructionsTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository, :has_merge_queue)
    @queue = @repo.default_merge_queue
    @body = <<~EOF
    Go out and deploy. Just do it.
    **YOLO deploying to 100% of production**

    ```
    .deploy github/branch to prod
    ```
    EOF
  end

  setup do
    example_repo(:deploy_instructions, @repo)
    enable_feature_flag(:merge_queue, @repo)
  end

  test "works for valid adaptive card template" do
    create(:merge_queue_entry, queue: @queue)
    instructions = DeployInstructions.new(repository: @repo)

    assert_predicate instructions, :valid?
    assert_equal "Manage deployments", instructions.title
    assert_equal @body, instructions.body
  end

  test "returns default title if title is not specified in template" do
    repo = create(:repository)
    blob = { "body" => @body }.to_yaml

    ref = repo.heads.find_or_build("master")
    ref.append_commit({ message:  "add DEPLOY_INSTRUCTIONS.yml", committer: repo.owner }, repo.owner) do |files|
      files.add(".github/DEPLOY_INSTRUCTIONS.yml", blob)
    end

    instructions = DeployInstructions.new(repository: repo)
    assert_predicate instructions, :valid?
    assert_equal "Deploy instructions", instructions.title
    assert_equal @body, instructions.body
  end
end
