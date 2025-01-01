# typed: true
# frozen_string_literal: true

require "test_helper"

module SlashCommands
  class SnippetsConfigTest < GitHub::TestCase
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

        commands = SnippetsConfig.find_commands(@repo)
        assert_equal 1, commands.size

        command = commands[0]
        assert_equal "test", T.must(command).trigger
        assert_equal "Test", T.must(command).title
        assert_equal "It's a test", T.must(command).description
        assert_equal "Test value", T.must(command).value
        assert_equal SlashCommands::SUPPORTED_SURFACES.map(&:to_s), T.must(command).surfaces
      end

      test "doesn't return invalid commands" do
        create_invalid_command!

        commands = SnippetsConfig.find_commands(@repo)
        assert_equal 0, commands.size
      end

      test "handles a user owned repository" do
        user_owned_repo = create(:repository)

        assert_equal [], SnippetsConfig.find_commands(user_owned_repo)
      end
    end

    context "#source_repository" do
      test "returns an orgs .github-private repository" do
        assert_equal @source_repo, SnippetsConfig.source_repository(@repo)
      end

      test "returns nil if the repository isn't owned by an org" do
        user_owned_repo = create(:repository)
        assert_nil SnippetsConfig.source_repository(user_owned_repo)
      end
    end

    context ".initialize" do
      test "expands surfaces to support surface hierarchy" do
        snippet = SnippetsConfig.new(repository: @source_repo, trigger: "test", title: "Test", description: "It's a test", value: "test", surfaces: [SlashCommands::ISSUE_SURFACE.to_s])
        assert snippet.supported_surface?(SlashCommands::ISSUE_BODY_SURFACE.to_s)
      end
    end

    context ".supported_surface?" do
      test "returns true if no surface is configured" do
        snippet = SnippetsConfig.new(repository: @source_repo, trigger: "test", title: "Test", description: "It's a test", value: "test")
        assert snippet.supported_surface?("test")
      end

      test "returns true if surface is configured and supported on is passed in" do
        snippet = SnippetsConfig.new(repository: @source_repo, trigger: "test", title: "Test", description: "It's a test", value: "test", surfaces: ["test"])
        assert snippet.supported_surface?("test")
      end

      test "returns false if surface is configured and unsupported one is passed in" do
        snippet = SnippetsConfig.new(repository: @source_repo, trigger: "test", title: "Test", description: "It's a test", value: "test", surfaces: ["test"])
        refute snippet.supported_surface?("another-test")
      end
    end

    context ".get_value" do
      test "returns a passed in value" do
        snippet = SnippetsConfig.new(repository: @source_repo, trigger: "test", title: "Test", description: "It's a test", value: "test")
        assert_equal "test", snippet.get_value
      end

      test "loads a value_source if provided" do
        create_value_source_command!
        snippet = SnippetsConfig.new(repository: @source_repo, trigger: "test", title: "Test", description: "It's a test", value_source: "#{SnippetsConfig::CONFIG_PATH}/value_source_command.md")
        assert_equal snippet.get_value, <<~MARKDOWN
          This is *a* **test**
        MARKDOWN
      end

      test "returns empty string on an invalid value_source" do
        create_value_source_command!
        snippet = SnippetsConfig.new(repository: @source_repo, trigger: "test", title: "Test", description: "It's a test", value_source: "#{SnippetsConfig::CONFIG_PATH}/_value_source_command.md")
        assert_equal "", snippet.get_value
      end

      test "returns string value if both value and value_source are provided" do
        create_value_source_command!
        snippet = SnippetsConfig.new(repository: @source_repo, trigger: "test", title: "Test", description: "It's a test", value: "test value", value_source: "#{SnippetsConfig::CONFIG_PATH}/value_source_command.md")
        assert_equal "test value", snippet.get_value
      end
    end

    private

    def create_valid_command!
      commit = @source_repo.commits.create({ message: "Add snippet", committer: @user }) do |files|
        files.add "#{SnippetsConfig::CONFIG_PATH}/valid_command.yml", <<~YAML
          ---
          trigger: test
          title: Test
          description: It's a test
          value: Test value
          surfaces: all
        YAML
      end

      @source_repo.refs["refs/heads/master"].update(commit, @user)
    end

    def create_value_source_command!
      commit = @source_repo.commits.create({ message: "Add snippet", committer: @user }) do |files|
        files.add "#{SnippetsConfig::CONFIG_PATH}/value_source_command.yml", <<~YAML
          ---
          trigger: test
          title: Test
          description: It's a test
          value_source: #{SnippetsConfig::CONFIG_PATH}/value_source_command.md
          surfaces: all
        YAML

        files.add "#{SnippetsConfig::CONFIG_PATH}/value_source_command.md", <<~MARKDOWN
          This is *a* **test**
        MARKDOWN
      end

      @source_repo.refs["refs/heads/master"].update(commit, @user)
    end

    def create_invalid_command!
      commit = @source_repo.commits.create({ message: "Add invalid snippet", committer: @user }) do |files|
        files.add "#{SnippetsConfig::CONFIG_PATH}/invalid_command.yml", <<~YAML
          ---
          title: Test
          description: It's a test
          surfaces: all
        YAML
      end

      @source_repo.refs["refs/heads/master"].update(commit, @user)
    end
  end
end
