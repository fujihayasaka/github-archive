# typed: strict
# frozen_string_literal: true

class Ghui::FilterSuggestions::IssueTypesController < GhuiController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include GitHub::ResilienceMixin

  allow_verified_fetch only: [:index]

  before_action :login_required
  before_action :parse_json_params
  before_action :validate_index_params, only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::Memex,
    ApplicationRecord::Ballast,
    only: [:index]


  sig { void }
  def index
    raw_response = with_database_error_fallback(fallback: nil) do
      case scope
      when :repository
        fetch_repository_raw_response
      when :project
        fetch_project_raw_response
      else
        fetch_viewer_raw_response
      end
    end

    if raw_response
      respond_payload({ data: raw_response["data"] })
    else
      respond_payload({ data: nil })
    end
  end

  private

  sig { returns(Symbol) }
  def scope
    if params[:owner].present? && params[:repo].present?
      :repository
    elsif params[:login].present? && params[:project_number].present?
      :project
    else
      :viewer
    end
  end

  sig { returns(T.nilable(T::Hash[String, T.untyped])) }
  def fetch_repository_raw_response
    variables = {
      owner: params[:owner],
      repo: params[:repo],
    }

    execute_server_persisted_query("FilterSuggestionsRepoIssueTypes", variables: variables)
  end

  sig { returns(T.nilable(T::Hash[String, T.untyped])) }
  def fetch_viewer_raw_response
    execute_server_persisted_query("FilterSuggestionsViewerIssueTypes", variables: {})
  end

  sig { returns(T.nilable(T::Hash[String, T.untyped])) }
  def fetch_project_raw_response
    variables = {
      login: params[:login],
      number: Integer(params[:project_number]),
    }

    execute_server_persisted_query("FilterSuggestionsProjectIssueTypes", variables: variables)
  end

  sig { void }
  def validate_index_params
    if params[:owner].present? && params[:repo].blank?
      respond_error(:bad_request, "`repo` parameter is required when `owner` is provided")
      return
    end

    if params[:repo].present? && params[:owner].blank?
      respond_error(:bad_request, "`owner` parameter is required when `repo` is provided")
      return
    end

    if params[:login].present? && params[:project_number].blank?
      respond_error(:bad_request, "`project_number` parameter is required when `login` is provided")
      return
    end

    if params[:project_number].present? && params[:login].blank?
      respond_error(:bad_request, "`login` parameter is required when `project_number` is provided")
      return
    end

    if (params[:owner].present? || params[:repo].present?) && (params[:login].present? || params[:project_number].present?)
      respond_error(:bad_request, "Cannot provide both repository (`owner`/`repo`) and project (`login`/`project_number`) scope parameters")
      return
    end

    if params[:project_number].present?
      validate_integer_param(:project_number, required: true)
    end
  end

  sig { returns(T.nilable(Repository)) }
  memoize def repository
    return nil unless params[:owner].present? && params[:repo].present?
    Repository.find_by(owner_login: params[:owner], name: params[:repo])
  end

  sig { returns(T.untyped) }
  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless repository # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    repository
  end

  sig { returns(T.untyped) }
  def target_for_conditional_access
    repository || :no_resource_for_conditional_access
  end
end
