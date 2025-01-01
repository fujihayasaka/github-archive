# typed: true
# frozen_string_literal: true

require "test_helper"

class LanguageBasedDistributionCustomizerTest < GitHub::TestCase
  include StarterWorkflowTemplateTestHelpers

  context "#customize_templates" do
    test "templates are distributed based on given languages percentage" do
      templates = get_templates_with_id(["Java", "Java-with-Clojure", "Java-with-Ant", "Python-Django-pip", "Python-Django-pip-with-C++", "Ruby", "Ruby-gem", "nodejs", "Docker-image", "html"])
      languages_percentage = {
        RepositoryTechProjectStackContract.new("Java", 250, nil) => 0.50,
        RepositoryTechProjectStackContract.new("Python", 150, nil) => 0.30,
        RepositoryTechProjectStackContract.new("Ruby", 100, nil) => 0.20
        }
      customized_templates_length, templates = Actions::WorkflowTemplate::LanguageBasedDistributionCustomizer.customize_templates(templates, **{ languages_percentage: languages_percentage, max_num_of_templates: 4 })

      assert_equal 4, customized_templates_length
      assert_templates %w[Java Java-with-Clojure Python-Django-pip Ruby], templates
    end

    test "not all slots are customized" do
      templates = get_templates_with_id(%w[Java Java-with-Clojure Python-Django-pip Ruby nodejs Docker-image html])
      languages_percentage = {
        RepositoryTechProjectStackContract.new("Java", 250, nil) => 0.50,
        RepositoryTechProjectStackContract.new("Python", 150, nil) => 0.30,
        RepositoryTechProjectStackContract.new("Ruby", 100, nil) => 0.20
        }
      customized_templates_length, templates = Actions::WorkflowTemplate::LanguageBasedDistributionCustomizer.customize_templates(templates, **{ languages_percentage: languages_percentage, max_num_of_templates: 6 })

      assert_equal 4, customized_templates_length
      assert_templates %w[Java Java-with-Clojure Python-Django-pip Ruby nodejs Docker-image], templates
    end

    test "empty templates are passed as input " do
      languages_percentage = {
        RepositoryTechProjectStackContract.new("Java", 250, nil) => 0.70,
        RepositoryTechProjectStackContract.new("Python", 150, nil) => 0.30,
        }
      customized_templates_length, templates = Actions::WorkflowTemplate::LanguageBasedDistributionCustomizer.customize_templates([], **{ languages_percentage: languages_percentage, max_num_of_templates: 4 })

      assert_equal 0, customized_templates_length
      assert_templates [], templates
    end

    test "empty language percentage" do
      templates = get_templates_with_id(%w[Java Java-with-Clojure Python-Django-pip Ruby nodejs Docker-image html])
      customized_templates_length, templates = Actions::WorkflowTemplate::LanguageBasedDistributionCustomizer.customize_templates(templates, **{ languages_percentage: {}, max_num_of_templates: 4 })

      assert_equal 0, customized_templates_length
      assert_templates %w[Java Java-with-Clojure Python-Django-pip Ruby], templates
    end
  end
end
