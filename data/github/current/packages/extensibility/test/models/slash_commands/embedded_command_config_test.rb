# typed: true
# frozen_string_literal: true

require "test_helper"

module SlashCommands
  class EmbeddedCommandConfigTest < GitHub::TestCase
    fixtures do
      @user = create(:user)
      @org = create(:organization)
      @repo = create(:repository, owner: @org)
      @source_repo = create(:private_repository, owner: @org, name: ".github-private")
    end

    setup do
      example_repo(:simple, @source_repo)
    end

    context "#find_commands" do
      test "returns valid commands" do
        create_valid_command!

        commands = EmbeddedCommandConfig.find_commands(@repo)
        assert_equal 1, commands.size

        command = commands[0]
        assert_equal "test", T.must(command).trigger
        assert_equal "Test", T.must(command).title
        assert_equal "It's a test", T.must(command).description
      end

      test "doesn't return invalid commands" do
        create_invalid_command!

        commands = EmbeddedCommandConfig.find_commands(@repo)
        assert_equal 0, commands.size
      end

      test "handles a user owned repository" do
        user_owned_repo = create(:repository)

        assert_equal [], EmbeddedCommandConfig.find_commands(user_owned_repo)
      end
    end

    context "#source_repository" do
      test "returns an orgs .github-private repository" do
        assert_equal @source_repo, EmbeddedCommandConfig.source_repository(@repo)
      end

      test "returns nil if the repository isn't owned by an org" do
        user_owned_repo = create(:repository)
        assert_nil EmbeddedCommandConfig.source_repository(user_owned_repo)
      end
    end

    private

    def create_valid_command!
      commit = @source_repo.commits.create({ message: "Add command", committer: @user }) do |files|
        files.add "#{EmbeddedCommandConfig::WEBHOOKS_CONFIG_PATH}/valid_command.yml", <<~YAML
          ---
          trigger: test
          title: Test
          description: It's a test
        YAML
      end

      @source_repo.refs["refs/heads/master"].update(commit, @user)
    end

    def create_invalid_command!
      commit = @source_repo.commits.create({ message: "Add command", committer: @user }) do |files|
        files.add "#{EmbeddedCommandConfig::WEBHOOKS_CONFIG_PATH}/invalid_command.yml", <<~YAML
          ---
          title: Test
          description: It's a test
        YAML
      end

      @source_repo.refs["refs/heads/master"].update(commit, @user)
    end
  end
end
