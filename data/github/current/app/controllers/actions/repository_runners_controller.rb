# typed: strict
# frozen_string_literal: true

class Actions::RepositoryRunnersController < AbstractRepositoryController
  include ActionsControllerMethods
  include Actions::RepositoryRunnersControllerHelper
  include Actions::RunnersHelper
  include ApplicationController::JsonDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Configurations,
    ApplicationRecord::Memex,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    only: [:github_hosted_runners, :shared_runners, :repository_scale_sets, :repository_self_hosted]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :github_hosted_runners, :shared_runners, :repository_self_hosted, :repository_scale_sets],
    optional: true

  before_action :ensure_user_can_view_page

  before_action :actions_enabled_for_repo?, only: [:index]

  before_action :ensure_request_format_json, only: [:github_hosted_runners, :shared_runners, :repository_scale_sets, :repository_self_hosted]
  before_action :parse_json_params, only: [:github_hosted_runners, :shared_runners, :repository_scale_sets, :repository_self_hosted]

  preload_features [:actions_workflow_list_pinning], only: [:index]

  sig { void }
  def index
    locals = if params[:tab] == "self-hosted"
      {
        selected_tab: "self-hosted",
        set_up_runners_path: set_up_runners_path,
      }
    else
      {
        selected_tab: "github-hosted",
        set_up_runners_path: set_up_runners_path,
      }
    end

    render "actions/runners/index", locals: sidebar_params.merge(locals) # rubocop:disable GitHub/RailsControllerRenderLiteral
  end

  sig { void }
  def github_hosted_runners # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.json do
        render json: {
          largerRunners: fetch_larger_runners,
          showLargerRunnerBanner: show_larger_runner_banner?,
          hasHostedRunnerGroup: has_hosted_runner_group?,
        }
      end
    end
  end

  sig { void }
  def shared_runners # rubocop:todo GitHub/UseRestfulActions
    runners = fetch_shared_runners

    respond_to do |format|
      format.json do
        render json: {
          runners: runners,
          total: runners.length,
        }
      end
    end
  end

  sig { void }
  def repository_scale_sets # rubocop:todo GitHub/UseRestfulActions
    runners = fetch_repository_scale_sets

    respond_to do |format|
      format.json do
        render json: {
          runners: runners,
          total: runners.length,
        }
      end
    end
  end

  sig { void }
  def repository_self_hosted # rubocop:todo GitHub/UseRestfulActions
    runners = paginated_repository_self_hosted_runners

    respond_to do |format|
      format.json do
        render json: {
          runners: runners,
          total: runners.length,
        }
      end
    end
  end

  private

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def sidebar_params
    {
      workflows: workflows,
      required_workflows: workflows(fetch_required_workflows: true),
      workflow_pages_count: workflow_pages_count,
      required_workflow_pages_count: workflow_pages_count(fetch_required_workflows: true),
      show_only_required_workflows: show_only_required_workflows?,
      show_runners_view: true,
      show_attestations_view: show_attestations_view?,
      show_actions_usage_metrics: show_actions_usage_metrics?,
      allow_pinning: allow_pinning?
    }
  end

  sig { void }
  def ensure_request_format_json
    render_404 unless request&.format&.json?
  end

  sig { void }
  def ensure_user_can_view_page
    render_404 unless show_runners_view?
  end
end
