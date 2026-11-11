# typed: true
# frozen_string_literal: true

module Actions::WorkflowTemplate
  class Recommender
    include FeatureFlagHelper
    attr_reader :repository, :current_user

    def initialize(repository, current_user, include_preview_templates = false)
      @repository = repository
      @current_user = current_user
      @include_preview_templates = include_preview_templates
    end

    # Returns the templates for the given filter_categories with tech_stacks based on source i.e. owner/shared/all
    # It also assign weight and order them
    def get_repo_based_templates(template_source:, filter_categories: [])
      start = GitHub::Dogstats.monotonic_time
      templates = filter_templates(template_source, filter_categories, true)
      order_templates(template_source, templates, filter_categories)
    ensure
      time_elapsed = GitHub::Dogstats.duration(start)
      GitHub.dogstats.distribution("starter_workflow.recommender.get_repo_based_templates.dist", time_elapsed)
    end

    # Returns the templates for the given filter_categories/search_query based on source i.e. owner/shared/all.
    # It also assign weight and order them
    def get_templates(template_source:, filter_categories: [], search_query: "")
      start = GitHub::Dogstats.monotonic_time
      templates = filter_templates(template_source, filter_categories, false)
      templates = search_templates(templates, search_query)
      templates = order_templates(template_source, templates, filter_categories)

      # If the source is owner, we don't want to order the non-relevant templates as that shuffles the order
      return templates if template_source == Actions::WorkflowTemplate::Source::OWNER

      relevant_templates, non_relevant_templates = templates.partition { |template| template.weight > 0 }
      relevant_templates + order_non_relevant_templates(non_relevant_templates, relevant_templates)
    ensure
      time_elapsed = GitHub::Dogstats.duration(start)
      GitHub.dogstats.distribution("starter_workflow.recommender.get_templates.dist", time_elapsed)
    end

    # Return the template with given id
    def template_by_id(id)
      workflow_templates_filter.by_id(id)
    end

    private

    def filter_templates(templates_source, filter_categories, filter_for_repo)
      start = GitHub::Dogstats.monotonic_time
      repo_tech_stack_keys = (tech_stacks_percent_size.keys if filter_for_repo) || []
      return [] if filter_for_repo && repo_tech_stack_keys.empty? && WorkflowTemplateHelper::tech_stack_based_categories?(filter_categories)

      filter_tech_stack = filter_for_repo ? repo_tech_stack_keys : []
      workflow_templates_filter.by_criteria(templates_source, filter_categories, filter_tech_stack)
    ensure
      time_elapsed = GitHub::Dogstats.duration(start)
      GitHub.dogstats.distribution("starter_workflow.recommender.filter_templates.dist", time_elapsed)
    end

    def compute_weight(templates, categories)
      weight_computers = get_unique_weight_computers(categories)
      templates.each do |template|
        template.add_weight(weight_computers.reduce(0) { |weight, weight_computer| weight + weight_computer.compute(template) })
      end
    end

    def get_unique_weight_computers(categories)
      weight_computers = []
      weight_computers.push(TechStackWeightComputer.new(tech_stacks_percent_size)) # Applicable for all categories

      weight_computers
    end

    def order_templates(template_source, templates, categories)
      start = GitHub::Dogstats.monotonic_time
      compute_weight(templates, categories)
      tech_stack_keys = tech_stacks_percent_size.keys
      comparators = []
      comparators.push(SecurityTemplateComparator.new) # Move GitHub recommended security templates to top irrespective of weight
      comparators.push(WeightComparator.new)
      comparators.push(SourceComparator.new) if SourceComparator::applicable?(template_source)
      comparators.push(CategoryComparator.new)
      comparators.push(UnmatchStackCountComparator.new(tech_stack_keys)) if UnmatchStackCountComparator::applicable?(categories)
      comparators.push(CloudComparator.new) if CloudComparator::applicable?(categories)
      templates.sort { |a, b| templates_sorter(a, b, comparators) }
    ensure
      time_elapsed = GitHub::Dogstats.duration(start)
      GitHub.dogstats.distribution("starter_workflow.recommender.order_templates.dist", time_elapsed)
    end

    def templates_sorter(template_a, template_b, comparators)
      weight_diff = 0
      comparators.each do |comparator|
        weight_diff = T.cast(comparator.compare(template_a, template_b), Integer)
        break if weight_diff != 0
      end
      weight_diff
    end

    def search_templates(templates, search_query)
      start = GitHub::Dogstats.monotonic_time
      Actions::WorkflowTemplate::SearchTemplate.execute(templates, search_query)
    ensure
      time_elapsed = GitHub::Dogstats.duration(start)
      GitHub.dogstats.distribution("starter_workflow.recommender.search_templates.dist", time_elapsed)
    end

    def workflow_templates_filter
      @workflow_templates_filter ||= Filterer.new(repository, current_user, @include_preview_templates)
    end

    def tech_stacks_percent_size
      @tech_stack ||= WorkflowTemplateHelper::repo_tech_stacks_percent_size(repository)
    end

    def order_non_relevant_templates(non_relevant_templates, relevant_templates)
      popular_templates, residual_templates = WorkflowTemplateHelper::split_templates_by_popularity(non_relevant_templates)
      popular_cloud_templates, popular_non_cloud_templates = popular_templates.partition { |t| t.category == "Deployment" }
      popular_cloud_templates = order_popular_cloud_templates(popular_cloud_templates, relevant_templates)
      popular_cloud_templates + popular_non_cloud_templates + residual_templates.shuffle
    end

    def order_popular_cloud_templates(popular_templates, relevant_templates)
      represented_clouds = get_clouds_for_templates(relevant_templates)
      represented_cloud_templates, non_represented_cloud_templates = popular_templates.partition { |template| represented_clouds.include?(template.creator) }
      non_represented_cloud_templates + represented_cloud_templates
    end

    def get_clouds_for_templates(templates)
      templates.select { |template| WorkflowTemplateHelper::has_deployment_category?(template.categories) }.collect(&:creator).to_set
    end
  end
end
