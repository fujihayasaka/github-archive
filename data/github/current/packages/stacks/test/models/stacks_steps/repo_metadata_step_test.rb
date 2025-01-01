# typed: true
# frozen_string_literal: true

require "test_helper"

class RepoMetadataStepTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)
    @params = { "topics" => %w[rails sql] }
    @auth_obj = ("ContentAuthorizer::RepoAuthorizer").constantize
    @step_obj = ("StacksSteps::RepoMetadataStep").constantize
  end

  setup do
    ContentAuthorizer.stubs(:authorize).returns(@auth_obj)
    @repo.stubs(:can_update_protected_branches?).returns(true)
  end

  context "#validate_inputs" do
    test "raises error when user not authorized" do
      @auth_obj.stubs(:failed?).returns(true)
      @auth_obj.stubs(:error_messages).returns("User unauthorized")

      error = assert_raises(Errors::ContentAuthorizerError) do
        @step_obj.validate_inputs(@params, repo: @repo, actor: @user)
      end
      assert_match "User unauthorized", error.message
    end

    test "raises error when topic length exceeds max size" do
      @params = { "topics" => ["VeryLongTopic"] }
      @auth_obj.stubs(:failed?).returns(false)
      Topic.stubs(:valid_name?).returns(false)

      error = assert_raises(Errors::InvalidInputError) do
        @step_obj.validate_inputs(@params, repo: @repo, actor: @user)
      end
      assert_match "Step validation failed: Invalid value of topics. Value must start with a lowercase letter or number, consist of 50 characters or less and can include hyphens.", error.message
    end
  end

  context "#run:" do
    test "update topics in repository" do
      @repo.expects(:update_topics).returns(true)

      StacksSteps::RepoMetadataStep.new(instance_id: 123, inputs: @params).run(repo: @repo, actor: @user)
    end

    test "raises error when update topics in repository fails" do
      @repo.stubs(:update_topics).returns(false)

      assert_raises(Errors::RepoMetadataUpdateError) do
        StacksSteps::RepoMetadataStep.new(instance_id: 123, inputs: @params).run(repo: @repo, actor: @user)
      end
    end

    test "update repository description" do
      @params = { "description" => "Small repo description" }

      @repo.expects(:save).returns(true)

      StacksSteps::RepoMetadataStep.new(instance_id: 123, inputs: @params).run(repo: @repo, actor: @user)
    end

    test "raises error when update repository description fails" do
      @params = { "description" => "Small repo description" }

      @repo.stubs(:save).returns(false)

      assert_raises(Errors::RepoMetadataUpdateError) do
        StacksSteps::RepoMetadataStep.new(instance_id: 123, inputs: @params).run(repo: @repo, actor: @user)
      end
    end
  end
end
