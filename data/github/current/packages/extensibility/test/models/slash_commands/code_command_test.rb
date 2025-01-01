# typed: true
# frozen_string_literal: true

require "test_helper"

module SlashCommands
  class CodeCommandTest < GitHub::TestCase
    include GitHub::SlashCommandTestHelpers

    fixtures do
      @user = create(:user)
      @repo = create(:repository, owner: @user)
    end

    setup do
      example_repo :language_test, @repo
    end

    test "puts repo's top languages at the top" do
      analysis = LanguageAnalysis.new(@repo)
      @repo.analyze_languages

      command = build_command(SlashCommands::CodeCommand,
        current_user: @user,
        current_repository: @repo
      )

      top_lang_names = @repo.language_percentages.map(&:first)

      assert_command_rendered(command) do |items|
        items.shift
        top_item_texts = items.first(top_lang_names.size).map(&:text)
        assert_same_elements top_item_texts, top_lang_names
      end
    end

    test "populates with popular languages when current repo is nil" do
      command = build_command(SlashCommands::CodeCommand,
        current_user: @user,
        current_repository: nil
      )

      popular_lang_names = Linguist::Language.popular.map(&:name)

      assert_command_rendered(command) do |items|
        item_texts = items.map(&:text).without("No Syntax")
        assert_same_elements item_texts, popular_lang_names
      end
    end

    test "handles repo languages that don't map to linguist" do
      command = build_command(SlashCommands::CodeCommand,
        current_user: @user,
        current_repository: @repo
      )

      # In this list of languages ASP does not map to a Linguist language and so will result in a nil value
      # when passed into Linguist.find_by_name
      language_percentages = [["C#", 71.4], ["CSS", 11.8], ["JavaScript", 10.1], ["Pascal", 4.0], ["HTML", 2.7], ["ASP", 0.0]]
      @repo.expects(:language_percentages).returns(language_percentages)

      assert_command_rendered(command) do |items|
        item_texts = items.map(&:text)
        refute_includes item_texts, "ASP"
        assert_includes item_texts, "C#"
        assert_includes item_texts, "CSS"
        assert_includes item_texts, "JavaScript"
        assert_includes item_texts, "Pascal"
        assert_includes item_texts, "HTML"
      end
    end

    test "fills with expected code block" do
      command = build_command(SlashCommands::CodeCommand,
        current_user: @user,
        current_repository: @repo,
        page_number: 2,
        data: { language: "ruby" }
      )

      codeblock = <<~CODEBLOCK
      ```ruby
      %cursor%
      ```
      CODEBLOCK

      assert_command_fill(command, codeblock)
    end

    test "languages have a valid value" do
      command = build_command(SlashCommands::CodeCommand,
        current_user: @user,
        current_repository: @repo
      )

      assert_command_rendered(command) do |items|
        refute_predicate items.map(&:value).select(&:nil?), :any?
      end
    end
  end
end
