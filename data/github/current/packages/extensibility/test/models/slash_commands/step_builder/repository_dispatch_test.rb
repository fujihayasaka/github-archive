# typed: true
# frozen_string_literal: true

require "test_helper"

module SlashCommands
  class StepBuilder::RepositoryDispatchTest < GitHub::TestCase
    include GitHub::SlashCommandTestHelpers

    fixtures do
      @owner = create(:user)
      @repo = create(:private_repository, :org_owned, from_example: :simple)
      @repo.add_member(@owner, action: :admin)
    end

    test "dispatches event for current repository" do
      command = build_command(UserDefinedCommand, current_repository: @repo, current_user: @owner)
      step_builder = StepBuilder::RepositoryDispatch.new({
        "type" => "repository_dispatch",
        "eventType" => "myEvent"
      })

      command.current_repository.expects(:dispatch_event).with(
        @owner.id,
        "myEvent",
        command.template_data,
      )

      step_builder.render(command)

      assert_equal command.flash.notice, "Triggering a `myEvent` repository dispatch event"
    end

    test "dispatches event for another repository" do
      another_repo = create(:private_repository, owner: @owner)
      command = build_command(UserDefinedCommand, current_repository: @repo, current_user: @owner)
      step_builder = StepBuilder::RepositoryDispatch.new({
        "type" => "repository_dispatch",
        "eventType" => "myEvent",
        "repository" => another_repo.nwo
      })

      command.current_repository.expects(:dispatch_event).never
      Repository.any_instance.expects(:dispatch_event).with(
        @owner.id,
        "myEvent",
        command.template_data,
      )

      step_builder.render(command)

      assert_equal command.flash.notice, "Triggering a `myEvent` repository dispatch event"
    end

    test "sets error when specified repository isn't readable" do
      another_repo = create(:private_repository)
      command = build_command(UserDefinedCommand, current_repository: @repo, current_user: @owner)
      step_builder = StepBuilder::RepositoryDispatch.new({
        "type" => "repository_dispatch",
        "eventType" => "myEvent",
        "repository" => another_repo.nwo
      })

      Repository.any_instance.expects(:dispatch_event).never

      step_builder.render(command)

      assert_equal command.flash.error, "Repository not found."
    end

    test "sets error when eventType not set" do
      command = build_command(UserDefinedCommand, current_repository: @repo, current_user: @owner)
      step_builder = StepBuilder::RepositoryDispatch.new({ "type" => "repository_dispatch" })

      command.current_repository.expects(:dispatch_event).never

      step_builder.render(command)

      assert_equal command.flash.error, "`eventType` property not set for step `type: repository_dispatch`"
    end

    test "sets error when user can't write to repository" do
      command = build_command(UserDefinedCommand, current_repository: @repo, current_user: @owner)
      step_builder = StepBuilder::RepositoryDispatch.new({
        "type" => "repository_dispatch",
        "eventType" => "myEvent"
      })
      @repo.remove_member(@owner)
      @repo.add_member(@owner, action: :read)

      command.current_repository.expects(:dispatch_event).never

      step_builder.render(command)

      assert_equal command.flash.error, "You must have push access to the repository to run this command."
    end
  end
end
