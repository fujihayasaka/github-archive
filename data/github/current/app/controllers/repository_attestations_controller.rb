# typed: true
# frozen_string_literal: true

class RepositoryAttestationsController < AbstractRepositoryController
  extend T::Helpers
  class TrustMetadataError < StandardError; end
  include ApplicationController::JsonDependency


  ASC_SORT_DIR = 1
  DESC_SORT_DIR = 2

  class ListResponse < T::Struct
    const :attestations, T::Array[T.untyped]
    const :attestation_summaries, T::Array[T.untyped]
    const :page_info, T.nilable(T::Hash[String, T.untyped])
    const :total_count, Integer
  end

  USER_FEEDBACK_URL = "https://github.com/orgs/community/discussions/129761"
  STAFF_FEEDBACK_URL = "https://github.com/github/package-security/discussions/1316"

  before_action :parse_json_params
  before_action :read_access_required

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show, :download_attestation],
    optional: true

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:download_attestation]


  sig { returns(String) }
  def self.react_bundle_name
    "repo-attestations"
  end

  def index
    path = delete_attestations_path(user_id: current_repository.owner_display_login, repository: current_repository.name)
    add_csrf_token(path, :delete)
    # Force page to be refreshed after pressing back button
    headers["Cache-Control"] = "no-cache, no-store"
    data = list_attestations

    render_react_app(
      page_data: {
        selected_link: :repo_attestations
      },
      payload: {
        attestations: data[:attestations],
        pageInfo: data[:page_info],
        repo: Repos::ReactPayload.current_repository_payload(
          current_repository,
          current_user_can_push: current_user_can_push?
        ),
        feedbackUrl: feedback_url,
        totalCount: data[:total_count],
      },
      title: "Attestations · #{current_repository.name_with_display_owner}",
      layout: "layouts/repository_with_container",
    )
  end

  def show
    # Force page to be refreshed after pressing back button
    headers["Cache-Control"] = "no-cache, no-store"
    data = find_attestation

    render_react_app(
      page_data: {
        selected_link: :repo_attestations
      },
      payload: {
        attestation: data[:attestation],
        rawLines: data[:rawLines],
        repo: Repos::ReactPayload.current_repository_payload(
          current_repository,
          current_user_can_push: current_user_can_push?
        ),
      },
      title: "Attestation · #{current_repository.name_with_display_owner}",
      layout: "layouts/repository_with_container",
    )
  end

  sig { void }
  def download_attestation # rubocop:todo GitHub/UseRestfulActions
    data = get_attestation_data_by_repository
    # NOTE: This filename is also used in the UI to display verify command: app/assets/modules/repo-attestations/pages/AttestationDetail.tsx
    filename = "#{current_repository.owner_display_login}-#{current_repository.name}-attestation-#{data.attestation.id}.sigstore.json"
    # Convert the proto interface to json and then back to a hash so we can format it
    bundle_json = JSON.pretty_generate(JSON.parse(data.attestation.bundle.to_json))
    send_data bundle_json, type: "text/json; charset=utf-8", disposition: "attachment", filename: filename
  end

  def destroy
    begin
      result = delete_attestations_by_id

      if result[:success]
        GitHub.dogstats.increment("trust_metadata.attestations.delete.success")
        render json: { message: "Attestations deleted successfully" }, status: :ok
      else
        GitHub.dogstats.increment("trust_metadata.attestations.delete.failure")
        GitHub.logger.error("Failed to delete attestations", {
          repository_id: current_repository.id,
          attestation_ids: result[:ids],
          error: result[:error]
        })
        render json: { error: result[:error] }, status: result[:status] || :internal_server_error
      end
    rescue JSON::ParserError => e
      render json: { error: "Invalid request format" }, status: :bad_request
    end
  end

  private

  def feedback_url
    return STAFF_FEEDBACK_URL if current_user&.employee?
    USER_FEEDBACK_URL
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def list_attestations
    data = {}
    resp_data = list_attestation_summaries_data_by_repository

    data[:attestations] = resp_data.attestation_summaries.map do |att|
      Attestations::ReactPayload.attestation_summary_payload(att, att.certificate_summary)
    end
    data[:page_info] = resp_data.page_info
    data[:total_count] = resp_data.total_count

    data
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def find_attestation
    data = {}

    resp_data = get_attestation_data_by_repository_summary
    data[:attestation] = Attestations::ReactPayload.attestation_summary_payload(resp_data.attestation_summary, resp_data.certificate_summary)
    # temporary disable displaying attestation preview until we truncate larger attestations
    data[:rawLines] = []

    data
  end

  def get_attestation_data_by_repository
    resp = TrustMetadata.get_attestation_by_repository(current_repository, attestation_id: params[:attestation_id].to_i)
    return resp.value if resp.call_succeeded?

    case resp.status
    when 404
      raise NotFound
    else
      message = resp.options&.fetch(:message, nil) || "Failed to get attestation by repository"
      raise TrustMetadataError.new("#{resp.status}: #{message}")
    end
  end

  def list_attestation_summaries_data_by_repository
    query_helper = TrustMetadata::AttestationsQueryHelper.new(helpers)
    @processed_params = query_helper.process_query_params(params)

    resp = TrustMetadata.list_attestation_summaries_by_repository(
      current_repository,
      before: cursor(:before),
      after: cursor(:after),
      per_page: 20,
      direction: @processed_params[:direction] || DESC_SORT_DIR,
      predicate_type: @processed_params[:predicate_type],
      created: @processed_params[:created],
      subject_name: @processed_params[:subject_name]
    )

    return resp.value if resp.call_succeeded?

    case resp.status
    when 404
      ListResponse.new(
        attestations: [],
        attestation_summaries: [],
        page_info: nil,
        total_count: 0
      )
    else
      message = resp.options&.fetch(:message, nil) || "Failed to list attestations by repository"
      raise TrustMetadataError.new("#{resp.status}: #{message}")
    end
  end

  def get_attestation_data_by_repository_summary
    resp = TrustMetadata.get_attestation_summary_by_repository(current_repository, attestation_id: params[:attestation_id].to_i)
    return resp.value if resp.call_succeeded?

    case resp.status
    when 404
      raise NotFound
    else
      message = resp.options&.fetch(:message, nil) || "Failed to get attestation by repository"
      raise TrustMetadataError.new("#{resp.status}: #{message}")
    end
  end

  def delete_attestations_by_id
    # Ensure the IDs are an array of integers
    ids = Array(params[:ids]).map(&:to_i)

    resp = TrustMetadata.delete_attestations_by_id(current_repository, ids)

    if resp.call_succeeded?
      { success: true, data: resp.value, ids: ids }
    else
      case resp.status
      when 404
        { success: false, status: :not_found, error: "Attestations not found", ids: ids }
      else
        message = resp.options&.fetch(:message, nil) || "Failed to delete attestations by ids"
        { success: false, status: resp.status, error: message, ids: ids }
      end
    end
  end

  sig { params(direction: Symbol).returns(T.nilable(Integer)) }
  def cursor(direction)
    if params[direction].blank? || !params[direction].respond_to?(:to_i)
      nil
    else
      params[direction].to_i.abs
    end
  end

  sig { void }
  def read_access_required
    render_access_denied unless current_user_can_read_repo?
  end
end
