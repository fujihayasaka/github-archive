# typed: true
# frozen_string_literal: true

module Actions::WorkflowTemplate
  class Filterer
    include FeatureFlagHelper

    attr_reader :repository, :current_user

    def initialize(repository, current_user, include_preview_templates = false)
      @repository = repository
      @current_user = current_user
      @include_preview_templates = include_preview_templates
      @include_code_scanning_workflows = repository.show_code_scanning_workflows_in_actions?
    end

    # Return templates for the given categories and/or tech stack based on source i.e owner/shared.
    # Note: For now, filter_categories and owner are exclusive
    def by_criteria(templates_source, filter_categories, filter_tech_stack)
      templates = []

      if templates_source == Source::OWNER || templates_source == Source::ALL
        templates += filter_templates_helper(owner_templates, [], filter_tech_stack)
      end

      if templates_source == Source::SHARED || templates_source == Source::ALL
        templates += filter_templates_helper(shared_templates, filter_categories, filter_tech_stack)
      end

      templates.deep_dup
    end

    # Return template with given id
    def by_id(id)
      all_templates.detect { |template| template.id == id }.deep_dup
    end

    private

    def filter_templates_helper(templates, filter_categories, filter_tech_stack)
      return templates if filter_categories.empty? && filter_tech_stack.empty?

      templates.select do |template|
        match_categories = filter_categories.map(&:downcase) & template.categories.map(&:downcase)
        include_template = filter_categories.empty? || !match_categories.empty?
        include_template && satisfy_tech_stack_criteria?(template, filter_tech_stack, match_categories)
      end
    end

    def satisfy_tech_stack_criteria?(template, filter_tech_stack, template_filter_categories)
      return true if filter_tech_stack.empty?
      return true if !template_filter_categories.empty? && !WorkflowTemplateHelper::tech_stack_based_categories?(template_filter_categories)
      !template.matched_tech_stack(filter_tech_stack).empty?
    end

    def template_data
      @template_data ||= Actions::WorkflowTemplates.new(repository, current_user)
    end

    def all_templates
      shared_templates + owner_templates
    end

    def owner_templates
      return @owner_templates if defined?(@owner_templates)
      if @include_code_scanning_workflows
        @owner_templates = map_json_to_template(template_data.owner_templates)
      else
        @owner_templates = map_json_to_template(template_data.owner_templates).reject do |template|
          WorkflowTemplateHelper::has_security_category?(template.categories)
        end
      end
    end

    def shared_templates
      return @shared_templates if defined?(@shared_templates)
      if @include_code_scanning_workflows
        @shared_templates = map_json_to_template(template_data.shared_templates)
      else
        @shared_templates = map_json_to_template(template_data.shared_templates).reject do |template|
          WorkflowTemplateHelper::has_security_category?(template.categories)
        end
      end
    end

    def map_json_to_template(templates)
      templates.map do |template|
        next if !@include_preview_templates && WorkflowTemplateHelper::has_preview_label?(template["labels"])
        template["partner"] = WorkflowTemplateHelper::has_deployment_category?(template["categories"])
        ::RepositoryActions::Onboarding::Template.new(template)
      end.compact
    end
  end
end
