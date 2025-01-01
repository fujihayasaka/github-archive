# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryActionsOnboardingTemplateTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)
  end

  setup do
    templates = Actions::WorkflowTemplates.new(@repo, @user)
    templates.stubs(:shared_templates).returns(
      GitHub::JSON.parse(File.read(Rails.root.join("test", "fixtures", "actions_workflow_templates.json")))
    )

    @nodejs = RepositoryActions::Onboarding::Template.new(templates.get_by_id("ci/nodejs"))
    @ruby = RepositoryActions::Onboarding::Template.new(templates.get_by_id("ci/ruby"))
    @blank = RepositoryActions::Onboarding::Template.new(templates.get_by_id("ci/blank"))
    @grunt = RepositoryActions::Onboarding::Template.new(templates.get_by_id("ci/grunt"))
  end

  context "#initialize" do
    test "handles a missing iconName by defaulting to an octicon" do
      t = RepositoryActions::Onboarding::Template.new({})
      assert_equal "octicon workflow.svg", t.icon_name
    end
  end

  context "#highlighted_template_lines" do
    test "returns correct lines from the templates yaml file" do
      assert_same_elements ["npm ci", "npm run build --if-present", "npm test"], @nodejs.highlighted_template_lines
    end

    test "works for the Ruby template" do
      assert_same_elements ["bundle install", "bundle exec rake", ""], @ruby.highlighted_template_lines
    end

    test "works for the blank template" do
      assert_same_elements ["echo Hello, world!", "echo Add other actions to build,", "echo test, and deploy your project."], @blank.highlighted_template_lines
    end
  end

  context "#source_repository" do
    test "defaults to actions/starter-workflows" do
      assert_equal "actions/starter-workflows", @blank.source_repository
    end

    test "takes a passed in sourceRepository" do
      template = RepositoryActions::Onboarding::Template.new({ "sourceRepository": "some/repo", "iconName": "something-needed-to-not-fail" }.stringify_keys)
      assert_equal "some/repo", template.source_repository
    end
  end

  context "#add_weight" do
    test "works as intended" do
      @nodejs.add_weight(5)
      @nodejs.add_weight(5)
      assert_equal 10, @nodejs.weight
    end
  end

  context "matches_paths?" do
    test "returns false if there are no patterns" do
      assert_nil @nodejs.file_patterns
      refute @nodejs.matches_paths?(["some-file.js"])
    end

    test "works as intended" do
      template = RepositoryActions::Onboarding::Template.new({ "filePatterns": ["package.json$"], "iconName": "something-needed-to-not-fail" }.stringify_keys)
      assert template.matches_paths?(["some-file.js", "package.json"])
    end

    test "handles invalid regex" do
      template = RepositoryActions::Onboarding::Template.new({ "filePatterns": ["*.json"], "iconName": "something-needed-to-not-fail" }.stringify_keys)

      # Regex error is caught and returns false
      refute template.matches_paths?(["some-file.js", "package.json"])
    end
  end

  context "matches_language?" do
    test "works as intended" do
      assert @nodejs.matches_language? "JavaScript"
      assert @nodejs.matches_language? "javaScript"
      refute @nodejs.matches_language? "Golang"
    end
  end

  context "matched_languages" do
    test "works as intended" do
      assert_equal %w[JavaScript npm], @nodejs.matched_languages(%w[JavaScript npm])
      assert_equal %w[Javascript Npm], @nodejs.matched_languages(%w[Javascript Npm])
      refute_equal %w[Node JavaScript], @nodejs.matched_languages(%w[JavaScript Node])
    end
  end

  context "matches_any_language?" do
    test "works as intended" do
      assert @nodejs.matches_any_language?(%w[JavaScript Node Golang])
      assert @nodejs.matches_any_language?(%w[javascript NODE golang])
      refute @nodejs.matches_any_language?(%w[Golang Python])
    end
  end

  context "matched_tech_stack" do
    test "if tech stack is empty" do
      assert_equal [], @ruby.matched_tech_stack([])
    end

    test "if matched tech stack is empty" do
      tech_stack = [
      RepositoryTechProjectStackContract.new("Python", 250, nil),
      RepositoryTechProjectStackContract.new("Java", 150, nil),
      RepositoryTechProjectStackContract.new("Go", 100, nil),
      ]

      assert_equal [], @ruby.matched_tech_stack(tech_stack)
    end

    test "if matched tech stack is not empty" do
      tech_stack = [
        RepositoryTechProjectStackContract.new("Python", 300, nil),
        RepositoryTechProjectStackContract.new("Ruby", 200, nil),
        RepositoryTechProjectStackContract.new("pip", 100, nil),
      ]

      expected_tech_stack = tech_stack.select { |stack| stack.name == "Ruby" }
      assert_equal expected_tech_stack, @ruby.matched_tech_stack(tech_stack)

      ## case insensitive
      tech_stack[1].name = "ruby"
      expected_tech_stack = tech_stack.select { |stack| stack.name == "ruby" }
      assert_equal expected_tech_stack, @ruby.matched_tech_stack(tech_stack)
    end
  end

  context "#matches_any_tech_stack_names?" do
    test "matches tech stack name if present" do
      assert @nodejs.matches_any_tech_stack_names?(%w[Ruby JavaScript]), "Template with aleast one matching tech stack name must return true"
      refute @nodejs.matches_any_tech_stack_names?(%w[Ruby Java]), "Template with zero non-matching tech stack should return false "
    end
  end

  context "#matched_tech_stack_names" do
    test "matches tech stack name if present" do
      assert_equal %w[JavaScript npm], @grunt.matched_tech_stack_names(%w[JavaScript npm Ruby]), "Template with aleast one matching tech stack name must matching tech stack name"
      assert_equal [], @nodejs.matched_tech_stack_names(%w[Ruby Java]), "Template with zero matching tech stack name should return empty array "
    end
  end
end
