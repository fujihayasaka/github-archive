# typed: true
# frozen_string_literal: true

class Memexes::TemplatesController < Memexes::Controller
  include ApplicationController::VerifiedFetchDependency
  include MemexProject::DefaultTemplates

  preload_features [:org_feature_helper]

  before_action :login_required
  before_action :require_verified_email, only: [:create]
  before_action :require_memex_feature_enabled
  before_action :require_this_memex
  before_action :user_has_admin_access
  before_action :disable_color_modes
  before_action :require_valid_repository, only: [:create], if: :auto_add_enabled_for_default_template?
  before_action :require_valid_auto_add_entities, only: [:create], if: :auto_add_enabled_for_default_template?

  before_action :set_client_uid

  allow_verified_fetch only: [:create]

  TEMPLATES = %w[feature backlog].freeze

  # cluster dependencies analysis will be enabled for this non-get requests
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Memexes::TemplatesController#create"
  ]

  depends_on_clusters ApplicationRecord::Memex,
    ApplicationRecord::Iam,
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    # Repositories required for determining outside collaborator access to issue_types feature
    # This allows us to determine if the user has access to create a type column
    # We can remove this dependency when issue_types is globally enabled
    ApplicationRecord::Repositories,
    only: [:create]

  # Project columns backed by issue fields need to query the issues and pull requests cluster to denormalize
  # the issue field values into the project columns.
  depends_on_clusters ApplicationRecord::IssuesPullRequests, only: [:create]

  def create
    return head :unprocessable_entity if !(default_template || custom_template_project)

    copying_drafts_async = false
    if default_template
      template_to_apply = nil
      system_template = MemexProject::DefaultTemplates::SYSTEM_TEMPLATE_MAP[template_id]
      if system_template
        template_to_apply = system_template
      else
        case default_template
        when :feature
          template_to_apply = MemexProject::DefaultTemplates::FeatureTemplate
        when :backlog
          template_to_apply = MemexProject::DefaultTemplates::BacklogTemplate
        end
      end

      # Modify template to include auto-add workflow if needed
      if auto_add_enabled_repository_id.present?
        template_to_apply = add_auto_add_workflow_to_template(template_to_apply)
      end

      this_memex.apply_default_template(creator: current_user, template: template_to_apply)
    elsif custom_template_project
      # Make sure the user has access to the template project
      return head :unprocessable_entity unless custom_template_project.viewer_can_read?(current_user)
      # The template should be the source of truth for all workflows, and will include the "default" workflows
      # if they haven't been removed from the template.

      max_draft_item_copy_error = MemexProject::Copier.get_max_draft_error(
        base_project: custom_template_project,
        include_draft_issues: true,
        is_template: true,
        actor: current_user,
      )
      if max_draft_item_copy_error
        GitHub.dogstats.increment("memex.memex_project_copier.max_copy_error")
        return render(json: { errors: [max_draft_item_copy_error] }, status: :unprocessable_entity)
      end

      this_memex.workflows.delete_all

      copier = MemexProject::Copier.new(
        base_project: custom_template_project,
        target_project: this_memex,
        include_draft_issues: true,
        actor: current_user,
      )

      copier_result = copier.execute
      copying_drafts_async = copier_result.copying_drafts_async?
      @this_memex = copier_result.target_project
      this_memex.update!(created_with_memex_template: custom_template_project.memex_template)
    end

    render(json: { success: true, copyingDraftsAsync: copying_drafts_async }, status: :created)
  rescue ActionController::ParameterMissing
    head :unprocessable_entity
  rescue ActiveRecord::RecordInvalid
    render_json_error(error: "Sorry, there was a problem applying this template. Please try again later.", status: :unprocessable_entity)
  end

  private

  def add_auto_add_workflow_to_template(template)
    return template unless auto_add_enabled_repository.present?
    return template unless FeatureFlag.vexi.enabled?(:projects_attach_repository, [this_memex.owner, current_user], default: false)

    # Deep duplicate the template to avoid modifying the original
    modified_template = template.deep_dup

    # Initialize workflows array if it doesn't exist
    modified_template[:workflows] ||= []

    # Build the auto-add workflow structure
    entity_filters = []
    content_types = []
    entity_filters << "issue" if auto_add_entities.include?("issues")
    content_types << "Issue" if auto_add_entities.include?("issues")
    entity_filters << "pr" if auto_add_entities.include?("prs")
    content_types << "PullRequest" if auto_add_entities.include?("prs")

    custom_query = "is:#{entity_filters.join(',')} is:open"

    # Create the auto-add workflow in template format
    auto_add_workflow = {
      name: "Auto-add to project",
      trigger_type: "query_matched",
      enabled: true,
      content_types: content_types,
      actions_attributes: [
        {
          action_type: "get_items",
          arguments: {
            query: custom_query,
            repositoryId: auto_add_enabled_repository.id
          }
        },
        {
          action_type: "add_project_item",
          arguments: {
            repositoryId: auto_add_enabled_repository.id
          }
        }
      ]
    }

    # Add the workflow to the template
    modified_template[:workflows] << auto_add_workflow

    modified_template
  end

  memoize def create_params
    underscored_params.permit(
      :template,
      :memex_id,
      :auto_add_enabled_repository_id,
      auto_add_entities: []
    )
  end

  # template_id is a string, either
  #  1. one of our default templates, or
  #  2. the ID of a MemexProject which has a template
  def template_id # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @template_id if defined?(@template_id)

    @template_id = create_params.require(:template)
  end

  sig { returns(T.nilable(Symbol)) }
  def default_template
    return nil unless TEMPLATES.include?(template_id) || SYSTEM_TEMPLATE_MAP.key?(template_id)

    template_id.to_sym
  end

  memoize def custom_template_project
    template_project = MemexProject.where(owner_type: memex_owner.type, owner_id: memex_owner.id, number: template_id).includes(:owner).first

    return nil if template_project.nil? || template_project.deleted? || !template_project.is_template?
    return nil if this_memex.owner != template_project.owner

    template_project
  end

  memoize def auto_add_enabled_repository_id
    create_params[:auto_add_enabled_repository_id]
  end

  memoize def auto_add_enabled_repository
    return unless auto_add_enabled_repository_id_present?
    @auto_add_enabled_repository = if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
      Repositories.domain.by_id(auto_add_enabled_repository_id)
    else
      Repository.find_by(id: auto_add_enabled_repository_id)
    end
  end

  memoize def auto_add_entities
    create_params[:auto_add_entities] || []
  end

  # Method feels a bit redundant, but is referenced by the rails hooks
  def auto_add_enabled_repository_id_present?
    auto_add_enabled_repository_id.present?
  end

  def auto_add_enabled_for_default_template?
    auto_add_enabled_repository_id_present? && default_template.present?
  end

  def require_valid_repository
    head :unprocessable_entity unless auto_add_enabled_repository&.readable_by?(current_user)
  end

  def require_valid_auto_add_entities
    return head :unprocessable_entity if auto_add_entities.empty?

    valid_entities = %w(issues prs)
    invalid_entities = auto_add_entities - valid_entities

    head :unprocessable_entity if invalid_entities.any?
  end
end
