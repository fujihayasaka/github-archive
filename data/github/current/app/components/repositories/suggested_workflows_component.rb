# typed: strict
# frozen_string_literal: true

module Repositories
  class SuggestedWorkflowsComponent < ApplicationComponent
    include ApplicationComponent::Rescuable

    MAX_NUM_OF_RECOMMENDED_TEMPLATES = 3
    SUGGESTED_WORKFLOW_SECTION_NOTICE_NAME = "repo_suggested_workflows"
    ACTIONS_IMPORTER_URL = "https://github.com/github/gh-actions-importer"
    PRODUCT_NAME = "actions"

    sig { returns(Repository) }
    attr_reader :repository

    sig { returns(User) }
    attr_reader :user

    sig { returns(String) }
    attr_reader :branch_or_tag_name

    rescue_from ActiveRecord::ActiveRecordError, with: :nothing

    sig { params(repository: Repository, user: User, branch_or_tag_name: T.nilable(String)).void }
    def initialize(repository:, user:, branch_or_tag_name: nil)
      @repository = T.let(repository, Repository)
      @user = T.let(user, User)
      @branch_or_tag_name = T.let(branch_or_tag_name || repository.default_branch, String)
    end

    sig { returns(T::Boolean) }
    def render?
      return false if GitHub.enterprise?
      if (organization = repository.organization)
        return false if organization.members_count > 100
        return false if organization.invoiced?
      end
      return false if user.spammy?
      return false if user.dismissed_repository_notice?(SUGGESTED_WORKFLOW_SECTION_NOTICE_NAME, repository_id: repository.id)
      return false if repository.actions_disabled_at_any_level?
      return false unless repository.writable_by?(user)
      return false if Actions::WorkflowRun.limit_execution_time.exists?(repository: repository)
      return false if suggested_templates.size < 2

      GlobalInstrumenter.instrument(
        "analytics.event",
        category: "suggested_workflows_in_repository_sidebar",
        action: "viewed_suggested_workflows_component",
        label: "user:#{user.id};repo:#{repository.id};owner:#{repository.owner&.id};ref_loc:respository_sidebar;is_scout_recommendation:true",
      )

      true
    end

    sig do
      params(workflow_template: RepositoryActions::Onboarding::Template, rank: Integer)
        .returns(T::Hash[String, T.untyped])
    end
    def configure_workflow_analytics_attributes(workflow_template:, rank:)
      # Feature flag determines whether to include visibility tracking (minimal blast radius)
      if FeatureFlag.vexi.enabled?(:workflow_template_visibility_tracking, user, repository.owner, default: false)
        # Determine template source visibility
        if workflow_template.respond_to?(:visibility) && workflow_template.visibility.present?
          # RepositoryActions::Onboarding::Template with visibility attribute
          template_source_visibility = workflow_template.visibility
        elsif workflow_template.respond_to?(:from_owner?) && workflow_template.from_owner?
          # RepositoryActions::Onboarding::Template from owner
          template_source_visibility = "owner"
        else
          # RepositoryActions::Onboarding::Template from shared templates
          template_source_visibility = "shared"
        end

        # Feature flag ON: Include visibility tracking
        hydro_click_tracking_attributes("actions.onboarding_setup_workflow_click", {
          repository_id: repository.id,
          workflow_template: workflow_template.id,
          view_section: "repository_sidebar",
          view_rank: rank,
          templates_count: suggested_templates.size,
          template_creator: workflow_template.creator,
          new_with_filter_view: false,
          correlation_id: GitHub.context[:request_id],
          category: workflow_template.category,
          search_query: nil,
          template_source_visibility: template_source_visibility
        })
      else
        # Feature flag OFF: Original behavior (unchanged)
        hydro_click_tracking_attributes("actions.onboarding_setup_workflow_click", {
          repository_id: repository.id,
          workflow_template: workflow_template.id,
          view_section: "repository_sidebar",
          view_rank: rank,
          templates_count: suggested_templates.size,
          template_creator: workflow_template.creator,
          new_with_filter_view: false,
          correlation_id: GitHub.context[:request_id],
          category: workflow_template.category,
          search_query: nil,
        })
      end
    end

    sig { returns(RepositoryActions::Onboarding::Template) }
    def actions_importer_template
      RepositoryActions::Onboarding::Template.new({
        "name" => "Actions Importer",
        "description" => "Automatically convert CI/CD files to YAML for GitHub Actions.",
        "iconName" => "octicon file-moved",
      })
    end

    sig { returns(T::Boolean) }
    memoize def error_getting_usage?
      usage_checker.request_error? || actions_entitlements.nil?
    end

    private

    sig { returns(T::Array[RepositoryActions::Onboarding::Template]) }
    memoize def suggested_templates
      template_recommender = Actions::WorkflowTemplate::Recommender.new(repository, user)

      templates = template_recommender.get_repo_based_templates(template_source: Actions::WorkflowTemplate::Source::ALL, filter_categories: ["Continuous integration"])
      templates.delete_if { |template| template.id == "datadog-synthetics" }

      templates.max_by(MAX_NUM_OF_RECOMMENDED_TEMPLATES) { |template| rand**(1.0 / template.weight) }
    end

    sig { returns(Billing::UsageChecker) }
    memoize def usage_checker
      Billing::UsageChecker.new(
        account: repository.owner,
        product_names: [PRODUCT_NAME],
        timeout: 3,
      )
    end

    sig { returns(T.nilable(Billing::UsageChecker::EntitlementResult)) }
    memoize def actions_entitlements
      usage_checker.entitlements_for(name: PRODUCT_NAME.capitalize)
    end
  end
end
