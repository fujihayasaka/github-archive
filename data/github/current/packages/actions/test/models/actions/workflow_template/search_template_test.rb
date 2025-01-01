# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchTemplateTest < GitHub::TestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)
    @templates = Actions::WorkflowTemplates.new(@repo, @user)
    @templates_data = GitHub::JSON.parse(File.read(Rails.root.join("test", "fixtures", "actions_workflow_templates.json")))
  end

  setup do
    Actions::WorkflowTemplates.any_instance.stubs(:all).returns(@templates_data)
  end

  context "#execute" do
    test "test templates search " do
      queries_map = {
                "azure" => {
                  sanitized_prefixes: ["azure"],
                  templates: { "deployments/azure" => { weight: 1.0 } }
                },
                "amaz!!!" => {
                   sanitized_prefixes: ["amaz"],
                   templates: { "deployments/aws" => { weight: 0.67 } }
                },
                "amaz@on" => {
                  sanitized_prefixes: ["amaz"],
                  templates: { "deployments/aws" => { weight: 0.67 } }
               },
                "deploy" => {
                  sanitized_prefixes: ["deploy"],
                  templates: { "deployments/azure" => { weight: 1.0 }, "deployments/aws" => { weight: 1.0 }, "deployments/alibabacloud" => { weight: 1.0 }, "deployments/aaa" => { weight: 1.0 }, "ci/docker-image" => { weight: 1.0 } }
                },
                "node.js" => {
                  sanitized_prefixes: ["node.js"],
                  templates: { "ci/nodejs" => { weight: 1.0 }, "deployments/azure" => { weight: 1.0 } }
                },
                "node.js    deploy" => {
                  sanitized_prefixes: ["node.js", "deploy"],
                  templates: { "deployments/azure" => { weight: 2.0 } },
                },
                "build!!! npm++ grunt" => {
                  sanitized_prefixes: %w[build npm grunt],
                  templates: { "ci/grunt-with-typescript" => { weight: 3.0 }, "ci/grunt" => { weight: 3.0 } },
                },
                "c#" => {
                  sanitized_prefixes: ["c#"],
                  templates: { "ci/dotnet" => { weight: 1.0 }, "code-scanning/codeql" => { weight: 1.0 }, "code-scanning/devskim" => { weight: 1.0 } }
                }
              }
      queries_map.each do |key, compare_data|
        templates = map_json_to_template(@templates.all)
        searched_templates = Actions::WorkflowTemplate::SearchTemplate.execute(templates, key)
        assert_equal searched_templates.length, compare_data[:templates].length, "searched templates length matched doesn't match for search query #{key}"
        searched_templates.each do |template|
          assert_equal template.weight, compare_data[:templates][template.id][:weight], "For search query:#{key}, template #{template.id} weight should be equal to than #{compare_data[:templates][template.id][:weight]}"
          compare_data[:sanitized_prefixes].each do |prefix|
            refute_nil template_string(template).include?(prefix), "For search query:#{key}, template  #{template.id} doesn't have search word #{prefix}"
          end
        end
      end
    end

    test "test templates search with preview templates" do
      queries_map = {
                "node.js" => {
                  sanitized_prefixes: ["node.js"],
                  templates: { "ci/nodejs" => { weight: 1.0 }, "ci/nodejs-preview" => { weight: 1.0 }, "deployments/azure" => { weight: 1.0 } }
                },
                "preview" => {
                  sanitized_prefixes: ["preview"],
                  templates: { "ci/nodejs-preview" => { weight: 1.0 } },
                },
                "node.js    deploy" => {
                  sanitized_prefixes: ["node.js", "deploy"],
                  templates: { "deployments/azure" => { weight: 2.0 } },
                }
              }
      queries_map.each do |key, compare_data|
        templates = map_json_to_template_preview(@templates.all)
        searched_templates = Actions::WorkflowTemplate::SearchTemplate.execute(templates, key)
        assert_equal searched_templates.length, compare_data[:templates].length, "searched templates length matched doesn't match for search query #{key}"
        searched_templates.each do |template|
          assert_equal template.weight, compare_data[:templates][template.id][:weight], "For search query:#{key}, template #{template.id} weight should be equal to than #{compare_data[:templates][template.id][:weight]}"
          compare_data[:sanitized_prefixes].each do |prefix|
            refute_nil template_string(template).include?(prefix), "For search query:#{key}, template  #{template.id} doesn't have search word #{prefix}"
          end
        end
      end
    end

    test "test special characters search " do
      # Special characters are sanitized and removed with empty space, so search result will return all templates
      special_characters = ["@", "&", "$", "%", "/", "\\", "!", "+", "*"]
      templates = map_json_to_template(@templates.all)
      special_characters.each do |key|
        searched_templates = Actions::WorkflowTemplate::SearchTemplate.execute(templates, key)
        assert_equal searched_templates.length, templates.length, "Special character match should match to all the templates"
        searched_templates.each do |template|
          assert_equal template.weight, 0
        end
      end
    end
  end

  def map_json_to_template(templates)
    templates.map do |template|
      next if WorkflowTemplateHelper::has_preview_label?(template["labels"])
      ::RepositoryActions::Onboarding::Template.new(template)
    end.compact
  end

  def map_json_to_template_preview(templates)
    templates.map do |template|
      ::RepositoryActions::Onboarding::Template.new(template)
    end.compact
  end

  def template_string(template)
    categories = template.categories.join(" ") if template.categories
    labels = template.labels.join(" ") if template.labels
    template_props = [template.id, template.name, template.creator, categories, labels, template.description].compact.join(" ")
  end
end
