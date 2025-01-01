# typed: true
# frozen_string_literal: true

require "test_helper"

class SlashCommandsTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper
  include GitHub::PullRequestTestHelpers
  include GitHub::SlashCommandTestHelpers

  class MockCommand < SlashCommands::ApplicationSlashCommand
    trigger_on name: "mock_command", title: "mock_command", description: "mock_command"

    def self.enabled?(context)
      false
    end
  end

  fixtures do
    @user = create(:user)
    enable_feature_flag(:slash_commands)
  end

  test "classes in slash_commands.yml are all valid" do
    repo = create(:repository, from_example: :dot_github)
    context = build_command_context(current_user: @user, current_repository: repo, surface: :issue)
    SlashCommands.slash_command_classes.each do |klass|
      refute_nil klass.triggers(context)
    end
  end

  context "#find_command" do
    test "returns an enabled slash command" do
      context = build_command_context(current_user: @user, surface: :issue)

      assert_kind_of SlashCommands::DetailsCommand, SlashCommands.find_command(context, command_id: SlashCommands::DetailsCommand.id, trigger_name: "details")
    end

    test "returns nil when the slash command is not enabled" do
      SlashCommands::DetailsCommand.stubs(:enabled?).returns(false)
      context = build_command_context(current_user: @user, surface: :issue)

      assert_nil SlashCommands.find_command(context, command_id: SlashCommands::DetailsCommand.id, trigger_name: "details")
    end

    test "returns nil when the command_id isn't real" do
      context = build_command_context(current_user: @user, surface: :issue)

      assert_nil SlashCommands.find_command(context, command_id: "test", trigger_name: "details")
    end

    test "returns nil when command_id is real but trigger isn't" do
      context = build_command_context(current_user: @user, surface: :issue)

      assert_nil SlashCommands.find_command(context, command_id: SlashCommands::DetailsCommand.id, trigger_name: "test")
    end
  end

  context "#all_commands" do
    test "returns all enabled commands" do
      # stub to include mock command
      stubbed_slash_command_classes = SlashCommands.slash_command_classes + [MockCommand]
      SlashCommands.stubs(:slash_command_classes).returns(stubbed_slash_command_classes)

      # test with nil context
      context = build_command_context(current_user: @user, surface: :issue)

      SlashCommands.all_commands(context).each do |command|
        assert command.enabled?(context)
      end
    end
  end

  context "#expand_surfaces" do
    test "handles an empty array" do
      assert_equal [], SlashCommands.expand_surfaces([])
    end

    test "expands nested surfaces" do
      assert_equal [
        SlashCommands::ISSUE_SURFACE,
        SlashCommands::ISSUE_BODY_SURFACE,
        SlashCommands::ISSUE_COMMENT_SURFACE,
        SlashCommands::PULL_REQUEST_SURFACE,
        SlashCommands::PULL_REQUEST_BODY_SURFACE,
        SlashCommands::PULL_REQUEST_COMMENT_SURFACE,
      ], SlashCommands.expand_surfaces([SlashCommands::ISSUE_SURFACE, SlashCommands::PULL_REQUEST_SURFACE])
    end
  end

  context "#supported_surface" do
    test "returns false for an unsuported surface" do
      refute SlashCommands.supported_surface? :invalid_surface
    end

    context "valid surfaces" do
      SlashCommands::SUPPORTED_SURFACES.each do |surface|
        test "returns true when the surface is #{surface} symbol" do
          assert SlashCommands.supported_surface? surface
        end

        test "returns true when the surface is #{surface} string" do
          assert SlashCommands.supported_surface? surface.to_s
        end
      end
    end
  end

  context "#surface_for" do
    test "returns nil when the subject is nil" do
      assert_nil SlashCommands.surface_for(nil)
    end

    test "returns nil when the subject is an unsupported class" do
      assert_nil SlashCommands.surface_for(Object)
    end

    test "returns nil when the subject is an unsupported instance" do
      assert_nil SlashCommands.surface_for(Object.new)
    end

    context "with a supported class" do
      test "returns true" do
        assert_equal SlashCommands.surface_for(Discussion), :discussion
      end
    end

    context "with a supported instance" do
      test "returns true" do
        assert_equal SlashCommands.surface_for(Discussion.new), :discussion
      end
    end

    context "with a supported platform object class" do
      test "returns true" do
        assert_equal SlashCommands.surface_for(PlatformTypes::Discussion), :discussion
      end
    end

    context "with a supported platform object instance" do
      test "returns true" do
        assert_equal SlashCommands.surface_for(PlatformTypes::Discussion), :discussion
      end
    end

    context "when surface is a string" do
      test "valid class names" do
        assert_equal SlashCommands.surface_for("Discussion"), :discussion
        assert_equal SlashCommands.surface_for("Issue"), :issue
        assert_equal SlashCommands.surface_for("PullRequest"), :pull_request
      end

      test "invalid class names" do
        assert_nil SlashCommands.surface_for("DiscussionComment")
        assert_nil SlashCommands.surface_for("PullRequestReview")
        assert_nil SlashCommands.surface_for("PullRequestReviewComment")
      end
    end
  end

  context "validations" do
    test "each slash command has valid allowed_surfaces" do
      SlashCommands.slash_command_classes.each do |klass|
        next if klass._allowed_surfaces.empty?
        klass._allowed_surfaces.each do |allowed_surface|
          assert SlashCommands.supported_surface? allowed_surface
        end
      end
    end
  end

  context "enabled_for?" do
    test "returns false if user is nil" do
      refute SlashCommands.enabled_for?(nil, nil)
    end

    test "returns true if user is enabled and no repository is provided" do
      user = build(:user)
      user.expects(:slash_commands_enabled?).returns(true)

      assert SlashCommands.enabled_for?(user, nil)
    end

    test "repository hash value overrides user enabled value" do
      user = build(:user)
      user.expects(:slash_commands_enabled?).returns(false)

      assert SlashCommands.enabled_for?(user, { slash_commands_enabled?: true })
    end

    test "calls repository helper if model provided" do
      user = build(:user)
      user.expects(:slash_commands_enabled?).returns(false)

      repository = build(:repository)
      repository.expects(:slash_commands_enabled?).returns(true)

      assert SlashCommands.enabled_for?(user, repository)
    end
  end

  context "subject_gid" do
    test "returns nil if subject is nil" do
      assert_nil SlashCommands.subject_gid(nil)
    end

    test "returns nil if subject is not a supported class" do
      assert_nil SlashCommands.subject_gid(Class.new)
    end

    test "returns nil if subject is a new record" do
      klass = Class.new
      klass.expects(:new_record?).returns(true)

      assert_nil SlashCommands.subject_gid(klass)
    end

    test "returns nil if subject does not respond to global_relay_id" do
      klass = Class.new
      klass.expects(:new_record?).returns(false)

      assert_nil SlashCommands.subject_gid(klass)
    end

    test "returns the gid for a supported class" do
      klass = Class.new
      klass.expects(:new_record?).returns(false)
      klass.expects(:global_relay_id).returns("test_gid")

      assert_equal "test_gid", SlashCommands.subject_gid(klass)
    end
  end

  context "#surface_for_issue_adapter" do
    test "returns correct surface when a pull request is provided" do
      pull_request = make_pr_and_repos
      repository = pull_request.repository

      loader = Issue::ShowLoader.new(pull_request.issue, repository, @user, cap_filter: cap_authorizing_filter)
      adapted = Issue::Adapter::PullRequestAdapter.new(loader.context, pull_request: pull_request)

      assert_equal SlashCommands::PULL_REQUEST_SURFACE, SlashCommands.surface_for_issue_adapter(adapted)
    end

    test "returns correct surface when an issue is provided" do
      repo = create(:repository, owner: @user)
      issue = create(:issue, repository: repo, user: @user)
      loader = Issue::ShowLoader.new(issue, repo, @user, cap_filter: cap_authorizing_filter)
      adapted = Issue::Adapter::IssueAdapter.new(
        loader.context,
        timeline_loader: loader.timeline_loader
      )

      assert_equal SlashCommands::ISSUE_BODY_SURFACE, SlashCommands.surface_for_issue_adapter(adapted)
    end

    test "returns correct surface when an issue comment is provided" do
      issue = create(:issue)
      comment = create(:issue_comment, issue: issue)
      loader = Issue::ShowLoader.new(issue, issue.repository, @user, cap_filter: cap_authorizing_filter)
      adapted = Issue::Adapter::CommentAdapter.new(loader.context, comment_id: comment.id, issue_adapter: {})

      assert_equal SlashCommands::ISSUE_COMMENT_SURFACE, SlashCommands.surface_for_issue_adapter(adapted)
    end

    test "returns correct surface when a pull request comment is provided" do
      pull_request = make_pr_and_repos
      repository = pull_request.repository
      issue = pull_request.issue

      comment = create(:issue_comment, issue: issue)
      loader = Issue::ShowLoader.new(issue, issue.repository, @user, cap_filter: cap_authorizing_filter)
      adapted = Issue::Adapter::CommentAdapter.new(loader.context, comment_id: comment.id, issue_adapter: {})

      assert_equal SlashCommands::PULL_REQUEST_SURFACE, SlashCommands.surface_for_issue_adapter(adapted)
    end

    test "returns nil when an unsupported object is provided" do
      klass = Class.new
      assert_nil SlashCommands.surface_for_issue_adapter(klass.new)
    end
  end

  context "#may_contain_commands?" do
    test "matches a single line with a command" do
      assert SlashCommands.may_contain_commands?("/test")
    end

    test "matches a command at the end of a multi-line string" do
      assert SlashCommands.may_contain_commands?("test string\n/test")
    end

    test "matches a command at the beginning of a multi-line string" do
      assert SlashCommands.may_contain_commands?("/test\ntest string")
    end

    test "matches a command in the middle of a multi-line string" do
      assert SlashCommands.may_contain_commands?("test string\n/test\ntest string")
    end

    test "doesn't match single line without a command" do
      refute SlashCommands.may_contain_commands?("test string")
    end

    test "doesn't match multi-line string without a command" do
      refute SlashCommands.may_contain_commands?("test string\ntest string")
    end

    test "doesn't match if slash isn't at start of line" do
      refute SlashCommands.may_contain_commands?("test string /test")
    end
  end

  context "#extract_embedded_commands" do
    test "returns an empty array if no commands are found" do
      assert_equal [], SlashCommands.extract_embedded_commands("test string")
    end

    test "matches a single line with a command" do
      assert_equal ["test"], SlashCommands.extract_embedded_commands("/test")
    end

    test "matches multiple commands" do
      assert_equal %w[test-one test-two], SlashCommands.extract_embedded_commands("/test-one\n/test-two")
    end

    test "matches a command at the end of a multi-line string" do
      assert_equal ["test"], SlashCommands.extract_embedded_commands("this is a\n/test")
    end

    test "matches a command in the middle of a multi-line string" do
      assert_equal ["test"], SlashCommands.extract_embedded_commands("this is a\n/test\nso is this")
    end

    test "matches the same command multiple times if used multiple times" do
      assert_equal %w[test test], SlashCommands.extract_embedded_commands("this is a\n/test\nso is this\n/test")
    end
  end

  context "#snippets_repository?" do
    test "returns true for a private repo owner with the flag enabled" do
      org = build(:organization)
      repo = build(:repository, :private, owner: org)

      enable_feature_flag(:snippet_slash_commands, org)

      assert SlashCommands.snippets_repository?(repo)
    end

    test "returns true for an internal repo owner with the flag enabled" do
      org = build(:organization)
      repo = build(:repository, :org_owned_internal, owner: org)

      enable_feature_flag(:snippet_slash_commands, org)

      assert SlashCommands.snippets_repository?(repo)
    end

    test "returns false for a public repo owner with the flag enabled" do
      org = build(:organization)
      repo = build(:repository, :public, owner: org)

      enable_feature_flag(:snippet_slash_commands, org)

      refute SlashCommands.snippets_repository?(repo)
    end

    test "returns false with the flag disabled" do
      org = build(:organization)
      repo = build(:repository, :private, owner: org)

      disable_feature_flag(:snippet_slash_commands)

      refute SlashCommands.snippets_repository?(repo)
    end

    test "returns false with a non-org repo owner" do
      repo = build(:repository, :private, owner: @user)

      enable_feature_flag(:snippet_slash_commands)

      refute SlashCommands.snippets_repository?(repo)
    end
  end
end
