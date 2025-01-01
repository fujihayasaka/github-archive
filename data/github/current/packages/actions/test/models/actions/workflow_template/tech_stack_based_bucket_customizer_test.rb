# typed: true
# frozen_string_literal: true

require "test_helper"

class TechStackBasedBucketCustomizerTest < GitHub::TestCase
  include StarterWorkflowTemplateTestHelpers

  context "#customize_templates" do
    test "templates of given tech stack are present" do
      templates = get_templates_with_id(["Python-Django-pip", "Python-Django-pip-with-C++", "Django", "Flask", "nodejs", "Docker-image", "html"])
      tech_stack = %w[Dockerfile Python npm Ruby]
      customized_templates_length, templates = Actions::WorkflowTemplate::TechStackBasedBucketCustomizer.customize_templates(templates, **{ tech_stack: tech_stack, max_num_of_templates: 6 })

      assert_equal 3, customized_templates_length
      assert_templates ["Docker-image", "Python-Django-pip", "nodejs", "Python-Django-pip-with-C++", "Django", "Flask"], templates
    end

    test "empty templates as input" do
      tech_stack = %w[Dockerfile Python npm Ruby]
      customized_templates_length, templates = Actions::WorkflowTemplate::TechStackBasedBucketCustomizer.customize_templates([], **{ tech_stack: tech_stack, max_num_of_templates: 6 })
      assert_equal 0, customized_templates_length
      assert_templates [], templates
    end

    test "no given tech stack based templates are present" do
      templates = get_templates_with_id(["Python-Django-pip", "Python-Django-pip-with-C++", "Django", "Flask", "nodejs", "Docker-image", "Greetings"])
      tech_stack = %w[Go html Erlang]
      customized_templates_length, templates = Actions::WorkflowTemplate::TechStackBasedBucketCustomizer.customize_templates(templates, **{ tech_stack: tech_stack, max_num_of_templates: 6 })
      assert_equal 0, customized_templates_length
      assert_templates ["Python-Django-pip", "Python-Django-pip-with-C++", "Django", "Flask", "nodejs", "Docker-image"], templates
    end
  end
end
