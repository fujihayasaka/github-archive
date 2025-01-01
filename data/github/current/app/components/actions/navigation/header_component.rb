# typed: true
# frozen_string_literal: true

class Actions::Navigation::HeaderComponent < ApplicationComponent

  include ActionsHelper

  def initialize(
    selected_workflow:,
    selected_section:,
    current_repository:,
    current_user:,
    workflow_run_filters:,
    page_title:,
    show_link_to_workflow:,
    user_has_push_access:,
    cache_item_filters:,
    allow_pinning: false
  )
    @selected_workflow = selected_workflow
    @selected_section = selected_section || :all_workflows
    @current_repository = current_repository
    @current_user = current_user
    @workflow_run_filters = workflow_run_filters
    @page_title = page_title
    @show_link_to_workflow = show_link_to_workflow
    @user_has_push_access = user_has_push_access
    @cache_item_filters = cache_item_filters
    @allow_pinning = allow_pinning
  end

  def is_workflows_section?
    @selected_section == :all_workflows
  end

  def is_cache_section?
    @selected_section == :caches
  end

  def is_runners_section?
    @selected_section == :runners
  end

  def title
    if is_workflows_section?
      return @page_title
    end
    @selected_section.to_s.humanize
  end

  def description_text
    if is_cache_section?
      return "Showing caches from all workflows."
    end

    if is_runners_section?
      return "Runners available to this repository"
    end

    if is_workflows_section?
      if @selected_workflow
        if @selected_workflow.dynamic_dependabot_workflow?
          "Showing all updates from Dependabot. Learn about "
        elsif @selected_workflow.dynamic_actions_workflow?
          "Showing Actions debug workflows."
        elsif @selected_workflow.dynamic_codespaces_workflow?
          "Showing all prebuild configuration runs for Codespaces. Learn about "
        elsif @selected_workflow.dynamic_codeql_workflow?
          "Showing all CodeQL runs. Learn more about "
        elsif @selected_workflow.dynamic_immutable_actions_migration_workflow?
          "Showing all runs for migrating semantic version releases to Immutable Actions."
        end
      elsif @workflow_run_filters[:workflow]
        "Showing runs from all workflows named #{@workflow_run_filters[:workflow]}"
      else
        "Showing runs from all workflows"
      end
    end
  end

  def description_link_url
    if is_cache_section?
      return "#{GitHub.help_url}/actions/advanced-guides/caching-dependencies-to-speed-up-workflows#managing-caches"
    end

    if is_workflows_section?
      if @selected_workflow
        if @selected_workflow.dynamic_dependabot_workflow?
          "#{GitHub.help_url}/code-security/dependabot"
        elsif @selected_workflow.dynamic_codespaces_workflow?
          "#{GitHub.help_url}/codespaces/customizing-your-codespace/prebuilding-codespaces-for-your-project"
        elsif @selected_workflow.dynamic_codeql_workflow?
          "#{GitHub.help_url}/code-security/code-scanning/automatically-scanning-your-code-for-vulnerabilities-and-errors/about-code-scanning-with-codeql"
        elsif @show_link_to_workflow
          workflow_blob_path
        end
      end
    end
  end

  def description_link_text
    if is_cache_section?
      return "Learn more about managing caches."
    end

    if is_workflows_section?
      if @selected_workflow
        if @selected_workflow.dynamic_dependabot_workflow?
          "Dependabot updates."
        elsif @selected_workflow.dynamic_codespaces_workflow?
          "prebuilding your codespaces."
        elsif @selected_workflow.dynamic_codeql_workflow?
          "code scanning."
        elsif @show_link_to_workflow
          workflow_file_name
        end
      end
    end
  end

  def description_test_selector
    if is_cache_section?
      return "cache-subtitle"
    end

    if is_workflows_section?
      if @selected_workflow
        if @selected_workflow.dynamic_dependabot_workflow?
          "dependabot-learn-more-link"
        elsif @selected_workflow.dynamic_codespaces_workflow?
          "codespaces-learn-more-link"
        elsif @selected_workflow.dynamic_codeql_workflow?
          "codeql-learn-more-link"
        elsif @show_link_to_workflow
          "workflow-file-link"
        end
      end
    end
  end

  def filter(is_mobile = false)
    if is_cache_section?
      return render partial: "actions/cache/filter_input", locals: {
        cache_item_filters: @cache_item_filters,
        current_repository: @current_repository,
        is_mobile: is_mobile
      }
    end

    if is_workflows_section?
      render partial: "actions/filter_input", locals: {
        workflow_run_filters: @workflow_run_filters,
        selected_workflow: @selected_workflow,
        current_repository: @current_repository,
        is_mobile: is_mobile
      }
    end
  end

  def workflow_file_name
    return @selected_workflow&.filename unless @selected_workflow&.required?

    @selected_workflow&.filename.gsub(Actions::Workflow::REQUIRED_WORKFLOWS_BASE_PATH, "")
  end

  def workflow_blob_path
    return blob_path(@selected_workflow.path, @current_repository.default_branch) unless @selected_workflow.required?

    source_repo = Repository.find_by(id: @selected_workflow.imposer_repository_id)
    return if source_repo.nil?

    latest_workflow_run_sha = @selected_workflow.workflow_runs.order(id: :desc).first&.workflow_file_checkout_sha
    return if latest_workflow_run_sha.nil?
    blob_path(@selected_workflow.path, latest_workflow_run_sha, source_repo)
  end

  sig { returns(T.nilable(String)) }
  memoize def set_up_runners_path
    return nil unless (owner = @current_repository.owner)

    if (business = owner.business) && business.adminable_by?(@current_user)
      settings_actions_runners_enterprise_path(business)
    elsif owner.organization? && owner.adminable_by?(@current_user)
      settings_org_actions_runners_path(owner)
    elsif @current_repository.adminable_by?(@current_user)
      repository_actions_settings_runners_path(repository: @current_repository, user_id: owner)
    end
  end

  memoize def selected_workflow_is_pinned?
    return false unless @selected_workflow.present?
    @selected_workflow.is_pinned?
  end

  memoize def selected_workflow_active?
    return false unless @selected_workflow.present?
    @selected_workflow.active?
  end

  def show_unpin_button?
    @allow_pinning && selected_workflow_active? && selected_workflow_is_pinned?
  end

  def show_pin_button?
    @allow_pinning && selected_workflow_active? && !selected_workflow_is_pinned?
  end

  def unpin_dialog_id
    return "" unless @selected_workflow.present?
    "menu-item-unpin-workflow-#{@selected_workflow.id}"
  end

  def show_ruleset_label?
    @current_repository.feature_enabled?(:actions_workflow_list_pinning)
  end
end
