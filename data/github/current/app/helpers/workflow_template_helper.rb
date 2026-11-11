# typed: true
# frozen_string_literal: true

module WorkflowTemplateHelper

  TECH_STACK_BASED_CATEGORIES = ["continuous integration", "code scanning"]
  FILTER_CATEGORIES = ["automation", "continuous integration", "deployment", "code scanning"]

  POPULAR_SECURITY_TEMPLATES = ["code-scanning/codeql"]
  GENERIC_TEMPLATE_LANGUAGES_THRESHOLD = 5 # Number of languages that a template support above which a template will be considered generic.

  # To check if category is tech_stack based or not. It returns true if any one of the given category is tech_stack based.
  def self.tech_stack_based_categories?(categories)
    categories.any? { |category| TECH_STACK_BASED_CATEGORIES.include?(category.downcase) }
  end

  # Returns given repository tech stack
  def self.repo_tech_stacks_percent_size(repository)
    repo_tech_stack = {}
    tech_project_stack_percentage = TechProjectStackAnalysis.tech_projects_with_stack_percentages(repository)
    if !tech_project_stack_percentage.nil? && !tech_project_stack_percentage[0].nil? && tech_project_stack_percentage[0].length >= 2
      repo_tech_stack = tech_project_stack_percentage[0][1] || {}
    end
    repo_tech_stack
  end

  def self.category_to_tech_stack(category)
    stack = Scout::TechStack.find_by_name(category) || Scout::TechStack.find_by_alias(category) || Linguist::Language.find_by_name(category) || Linguist::Language.find_by_alias(category)
  end

  def self.language_category?(category)
    Linguist::Language.find_by_name(category) || Linguist::Language.find_by_alias(category)
  end

  def self.filter_category?(category)
    FILTER_CATEGORIES.include?(category.downcase)
  end

  def self.has_deployment_category?(template_categories)
    template_categories && template_categories.is_a?(Array) && template_categories.any? { |t| t.casecmp?("Deployment") }
  end

  def self.has_preview_label?(template_labels)
    template_labels && template_labels.is_a?(Array) && template_labels.any? { |t| t.casecmp?("preview") }
  end

  def self.has_security_category?(template_categories)
    template_categories && template_categories.is_a?(Array) && template_categories.any? { |t| t.casecmp?("Code Scanning") || t.casecmp?("Dependency Review") }
  end

  def self.repo_popular_tech_stack(repository, popular_tech_stack)
    repo_tech_stack = repo_tech_stacks_percent_size(repository).keys
    popular_tech_stack & repo_tech_stack.map(&:name)
  end

  def self.split_templates_by_popularity(templates)
    popular_templates = Actions::TopNCloudCustomizer::POPULAR_CLOUD_TEMPLATES + WorkflowTemplateHelper::POPULAR_SECURITY_TEMPLATES
    templates.partition { |template| popular_templates.include?(template.id.downcase) }
  end

  def self.generic_template?(template)
    # A template is considered generic if it supports more than GENERIC_TEMPLATE_LANGUAGES_THRESHOLD languages. Issue: https://github.com/github/actions-cats/issues/986
    template.id == "ci/datadog-synthetics" || template.categories.map {  |category| self.language_category?(category) }.length > GENERIC_TEMPLATE_LANGUAGES_THRESHOLD
  end
end
