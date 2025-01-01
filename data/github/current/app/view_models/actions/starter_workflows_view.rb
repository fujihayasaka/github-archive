# typed: true
# frozen_string_literal: true

module Actions
  class StarterWorkflowsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include FeatureFlagHelper
    include UrlHelpers
    attr_reader :language_category_filter, :filter_options, :repository, :selected_category

    # Change these IDs to adjust what is shown in the popular section
    POPULAR_TECH_STACK = ["Dockerfile"]
    NAVIGATION_CATEGORIES = {
      "deployment" => "Deployment",
      "security" => "Security",
      "continuous-integration" => "Continuous integration",
      "automation" => "Automation",
      "pages" => "Pages",
    }
    MAX_NUM_OF_TEMPLATES = 4
    MAX_NUM_OF_TEMPLATES_NEW = 3
    MAX_NUM_OF_RECOMMENDED_TEMPLATES = 6
    MAX_NUM_OF_RECOMMENDED_TEMPLATES_NEW = 4
    MAX_NUM_OF_TEMPLATES_DEPLOYMENT = 8
    MAX_NUM_OF_TEMPLATES_DEPLOYMENT_NEW = 6

    VIEW_SECTION = {
      "automation" => "automation_templates",
      "continuous-integration" => "ci_templates",
      "deployment" => "partner_templates",
      "security" => "security_templates",
      "pages" => "pages_templates",
      "none" => "none"
    }.freeze

    VIEW_CATEGORY_TO_TEMPLATE_CATEGORY_MAP = {
      "Automation" => ["Automation"],
      "Continuous integration" => ["Continuous integration"],
      "Deployment" => ["Deployment"],
      "Security" => ["Code Scanning", "Dependency Review"],
      "Pages" => ["Pages"],
    }

    def starter_workflow_repo_exists?
      if GitHub.enterprise?
        GitHub.actions_starter_workflows_nwo.present? && Repository.nwo(GitHub.actions_starter_workflows_nwo).present?
      else
        true
      end
    end

    def enterprise_admin_action_help_url
      "#{GitHub.enterprise_admin_help_url}/github-actions/advanced-configuration-and-troubleshooting/troubleshooting-github-actions-for-your-enterprise#bundled-actions"
    end

    def primary_language
      repository.primary_language&.name
    end

    def show_automation_section?
      automation_templates.any?
    end

    def show_pages_section?
      pages_templates.any?
    end

    def show_filter?
      language_category_filter.present?
    end

    def number_of_templates
      {
        "deployment" => partner_templates.count,
        "continuous-integration" => ci_templates.count,
        "security" => security_templates.count,
        "automation" => automation_templates.count,
        "pages" => pages_templates.count,
        "owner" => owner_templates.count,
        "none" => all_workflow_templates.count,
      }.to_h
    end

    def suggested_templates
      return @suggested_templates if @suggested_templates

      @suggested_templates = suggest_templates_using_tech_stacks_analysis
      instrument_actions_template_stack("suggested_templates", templates_stack_analysis(@suggested_templates))
      @suggested_templates
    end

    def show_suggested_templates?
      suggested_templates.any?
    end

    def filtered_templates_new(filter_options)
      template_source = Actions::WorkflowTemplate::Source::NONE
      filter_categories = []
      if filter_options.category_slug.casecmp?("owner")
        template_source = Actions::WorkflowTemplate::Source::OWNER
      elsif filter_options.category_slug.casecmp?("none")
        template_source = Actions::WorkflowTemplate::Source::ALL
      else
        valid_category_name = get_category_name_from_slug(filter_options.category_slug)
        filter_categories = VIEW_CATEGORY_TO_TEMPLATE_CATEGORY_MAP[valid_category_name] unless  valid_category_name.empty?
        template_source = Actions::WorkflowTemplate::Source::SHARED unless filter_categories.empty?
      end
      template_recommender.get_templates(template_source: template_source, filter_categories: filter_categories, search_query: filter_options.search_query)
    end

    def all_workflow_templates
      return @all_workflow_templates if @all_workflow_templates

      @all_workflow_templates = template_recommender.get_templates(template_source: Actions::WorkflowTemplate::Source::ALL)
    end

    def automation_templates
      return @automation_templates if @automation_templates

      @automation_templates = template_recommender.get_templates(template_source: Actions::WorkflowTemplate::Source::SHARED, filter_categories: ["Automation"])
    end

    def pages_templates
      return @pages_templates if defined?(@pages_templates)

      # Get Pages templates
      @pages_templates = template_recommender.get_templates(template_source: Actions::WorkflowTemplate::Source::SHARED, filter_categories: ["Pages"])

      # If any, refine the list with the customizers
      if !@pages_templates.empty?
        @pages_templates = apply_customizers(@pages_templates, MAX_NUM_OF_RECOMMENDED_TEMPLATES)
      else
        @pages_templates = []
      end
    end

    def partner_templates
      return @partner_templates if @partner_templates

      @partner_templates = template_recommender.get_templates(template_source: Actions::WorkflowTemplate::Source::SHARED, filter_categories: ["Deployment"])

      repo_based_templates, non_relevant_templates = @partner_templates.partition { |template| template.weight > 0 }

      customized_templates = TopNCloudCustomizer.customize_templates(repo_based_templates, non_relevant_templates, **{ repository: repository, max_num_of_templates: MAX_NUM_OF_TEMPLATES_DEPLOYMENT })
      @partner_templates = customized_templates.to_set.merge(repo_based_templates).merge(non_relevant_templates).to_a
      instrument_actions_template_stack("partner_templates", templates_stack_analysis(@partner_templates).first(MAX_NUM_OF_TEMPLATES_DEPLOYMENT))
      @partner_templates
    end

    def show_partner_templates?
      partner_templates.any?
    end

    def owner_templates
      return @owner_templates if defined?(@owner_templates)

      @owner_templates = template_recommender.get_templates(template_source: Actions::WorkflowTemplate::Source::OWNER)
    end

    def show_owner_templates?
      owner_templates.any?
    end

    def show_owner_suggested_templates?
      owner_suggested_templates.any?
    end

    def owner_suggested_templates
      return @owner_suggested_template if defined?(@owner_suggested_template)

      templates = owner_templates - suggested_templates
      @owner_suggested_template = apply_customizers(templates, MAX_NUM_OF_TEMPLATES)
    end

    def show_ci_suggested_templates?
      ci_suggested_templates.present?
    end

    def ci_suggested_templates
      return @ci_suggested_templates if defined?(@ci_suggested_templates)

      templates = ci_templates - suggested_templates
      @ci_suggested_templates = apply_customizers(templates, MAX_NUM_OF_TEMPLATES)
    end

    def ci_templates
      return @ci_templates if @ci_templates

      @ci_templates = template_recommender.get_templates(template_source: Actions::WorkflowTemplate::Source::SHARED, filter_categories: ["Continuous integration"])
    end

    def show_ci_templates?
      ci_templates.any?
    end

    def prefilled_filter_path(overrides = {})
      params = filter_options.as_params(overrides)
      params = params.merge({ "repository": repository, "user_id": repository.owner })
      actions_onboarding_filter_path(params)
    end

    def security_templates
      return @security_templates if @security_templates
      @security_templates = template_recommender.get_templates(template_source: Actions::WorkflowTemplate::Source::SHARED, filter_categories: get_template_categories("Security"))
    end

    def show_security_templates?
      security_templates.any?
    end

    def about_code_scanning_docs_url
      DocsUrlConfig.url_for("code-security/about-code-scanning")
    end

    def get_category_name_from_slug(slug)
      NAVIGATION_CATEGORIES[slug.downcase] || ""
    end

    def get_template_categories(category)
      VIEW_CATEGORY_TO_TEMPLATE_CATEGORY_MAP[category] || []
    end

    def get_view_section(category_slug)
      VIEW_SECTION[category_slug.downcase] || ""
    end

    def show_navigation_category?(slug)
      return show_security_templates? if slug.casecmp?("security")
      return !GitHub.enterprise? if slug.casecmp?("deployment")
      true
    end

    def show_navigation_category
      {
        "deployment" => !GitHub.enterprise?,
        "security" => show_security_templates?,
        "continuous-integration" => true,
        "automation" => true,
        "pages" => true,
      }.to_h
    end

    def code_scanning_enabled?
      repository.code_scanning_enabled?
    end

    private

    def include_preview_templates?
      filter_options&.include_preview_templates || false
    end

    def template_data
      @template_data ||= Actions::WorkflowTemplates.new(repository, current_user)
    end

    def template_recommender
      @template_recommender ||= Actions::WorkflowTemplate::Recommender.new(repository, current_user, include_preview_templates?)
    end

    def suggest_templates_using_tech_stacks_analysis
      suggested_templates = template_recommender.get_repo_based_templates(template_source: Actions::WorkflowTemplate::Source::ALL, filter_categories: ["Continuous integration"])
      suggested_templates.delete_if { |template| WorkflowTemplateHelper.generic_template?(template) }
      if suggested_templates.empty?
        suggested_templates = [get_blank_template].compact
      else
        suggested_templates = apply_customizers(suggested_templates, MAX_NUM_OF_RECOMMENDED_TEMPLATES)
      end

      suggested_templates
    end

    def get_blank_template
      template_recommender.template_by_id("ci/blank")
    end

    def instrument_actions_template_stack(category, templates)
      return if templates.empty?
      payload = {
        repository_id: repository.id,
        category: category,
        templates: templates,
        commit_sha: repository.default_oid,
      }
      GlobalInstrumenter.instrument("repository_actions.recommended_templates", payload)
    end

    def templates_stack_analysis(templates)
      return {} if templates.empty?
      templates_analysis = []
      tech_stack = WorkflowTemplateHelper.repo_tech_stacks_percent_size(repository).keys
      templates.each_with_index do |template, index|
        matched_tech_stack = template.matched_tech_stack(tech_stack).map(&:name)
        templates_analysis << {
          template_id: template.id,
          matched_tech_stack: matched_tech_stack,
          unmatched_tech_stack: template.tech_stack - matched_tech_stack,
          undetected_tech_stack: template.undetected_tech_stack,
          rank: index + 1
        }
      end
      templates_analysis
    end

    def apply_customizers(templates, max_num_of_templates)
      repo_tech_stack = WorkflowTemplateHelper::repo_tech_stacks_percent_size(repository)
      languages_percentage = repo_tech_stack.select { |stack, _|  stack.is_language? }
      repo_popular_tech_stack = WorkflowTemplateHelper::repo_popular_tech_stack(repository, POPULAR_TECH_STACK)
      top_n_tech_stack = repo_popular_tech_stack.union(languages_percentage.keys.map(&:name))
      customized_templates_length, tech_stack_based_templates = WorkflowTemplate::TechStackBasedBucketCustomizer.customize_templates(templates, **{ tech_stack: top_n_tech_stack, max_num_of_templates: max_num_of_templates })
      return tech_stack_based_templates.first(max_num_of_templates) if customized_templates_length >= max_num_of_templates

      tech_stack_based_templates = tech_stack_based_templates[0...customized_templates_length]
      templates -= tech_stack_based_templates
      _, lang_distribution_templates = WorkflowTemplate::LanguageBasedDistributionCustomizer.customize_templates(templates, **{ languages_percentage: languages_percentage, max_num_of_templates: max_num_of_templates - customized_templates_length })

      (tech_stack_based_templates + lang_distribution_templates).first(max_num_of_templates)
    end
  end
end
