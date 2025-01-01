# typed: true
# frozen_string_literal: true

class Api::RepositoryCodeqlVariantAnalyses < Api::App
  include VariantAnalysis::ActionsWorkflowHelper
  include VariantAnalysis::StorageHelper
  include VariantAnalysis::RepositoryResolutionHelper

  before do
    deliver_error! 404 if GitHub.enterprise?
  end

  get "/repositories/:repository_id/code-scanning/codeql/variant-analyses/:codeql_variant_analysis_id", operation_id: "code-scanning/get-variant-analysis" do
    @route_owner = "@github/code-scanning-secexp"

    controller_repo = ActiveRecord::Base.connected_to(role: :reading) { find_repo! }

    @accepted_scopes = controller_repo.public? ? %w(public_repo repo) : %w(repo)

    control_access :read_multi_repository_variant_analysis,
      resource: controller_repo,
      forbid: controller_repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    variant_analysis = CodeqlVariantAnalysis.find_by(
      id: params[:codeql_variant_analysis_id].to_i,
      controller_repo_id: controller_repo.id)
    deliver_error!(404, message: "Variant analysis not found") unless variant_analysis

    associated_repo_ids = [
      variant_analysis.codeql_variant_analysis_repo_tasks.pluck(:repository_id),
      variant_analysis.privacy_mismatch_repo_ids&.split(","),
      variant_analysis.no_codeql_db_repo_ids&.split(","),
      variant_analysis.over_limit_repo_ids&.split(","),
    ].compact.flatten
    associated_repositories = ActiveRecord::Base.connected_to(role: :reading) { find_accessible_repositories_with_ids(associated_repo_ids, current_user, cap_filter) }

    deliver :repository_codeql_variant_analysis_hash, {
      variant_analysis: variant_analysis,
      repositories: associated_repositories
    }
  end

  post "/repositories/:repository_id/code-scanning/codeql/variant-analyses", operation_id: "code-scanning/create-variant-analysis" do
    @route_owner = "@github/dsp-code-scanning-secexp"

    controller_repo = ActiveRecord::Base.connected_to(role: :reading) { find_repo! }

    @accepted_scopes = controller_repo.public? ? %w(public_repo repo) : %w(repo)

    control_access :write_multi_repository_variant_analysis,
      resource: controller_repo,
      forbid: controller_repo.public?,
      forbid_message: "To use CodeQL variant analysis, you must have write access to the controller repository used for running GitHub Actions.",
      allow_integrations: true,
      allow_user_via_granular_actor: true

    validate_controller_repo_exists!(controller_repo)

    data = receive_with_openapi

    action_repo_ref = data["action_repo_ref"] || "main"
    validate_action_repo_ref!(action_repo_ref)

    decoded_query_pack = decode_query_pack!(data["query_pack"])

    repositories = ActiveRecord::Base.connected_to(role: :reading) do
      resolve_repositories(
        current_user: current_user,
        cap_filter: cap_filter,
        language: data["language"],
        repository_nwos: data["repositories"],
        repository_lists: data["repository_lists"],
        repository_owners: data["repository_owners"]
      )
    end

    validate_repositories!(repositories)

    variant_analysis = CodeqlVariantAnalysis.create!(
      controller_repo_id: controller_repo.id,
      actor_id: current_user&.id,
      query_language: data["language"],
      not_found_repo_count: repositories[:invalid_repo_nwos].size,
      not_found_repo_nwos: repositories[:invalid_repo_nwos].take(100).join(",")
    )

    query_pack_path = upload_query_pack(variant_analysis, decoded_query_pack)
    variant_analysis.update!(query_pack_path: query_pack_path)

    CodeqlVariantAnalysisProcessingJob.perform_later(
      variant_analysis_id: variant_analysis.id,
      action_repo_ref: action_repo_ref,
      repository_ids: repositories[:repo_ids],
    )

    deliver :repository_codeql_variant_analysis_hash,
      { variant_analysis: variant_analysis },
      status: 201
  end

  private

  def validate_action_repo_ref!(action_repo_ref)
    check_for_valid_ref(action_repo_ref: action_repo_ref, user: current_user)
  rescue InvalidActionRepoRef => e
    deliver_error! 422, message: e.message
  end

  def decode_query_pack!(query_pack)
    process_query_pack(query_pack)
  rescue InvalidBase64QueryPackError, InvalidGzipQueryPackError => e
    deliver_error! 422, message: e.message
  end

  def validate_controller_repo_exists!(controller_repo)
    return if branch_exists(controller_repo, controller_repo.default_branch)

    error_message = "Variant analysis failed because controller repository #{controller_repo.name_with_display_owner} "\
    "does not have a branch '#{controller_repo.default_branch}'. Please create a "\
    "'#{controller_repo.default_branch}' branch in the repository and re-run the "\
    "variant analysis."

    deliver_error! 422, message: error_message, errors: [
      api_error(
        :Repository, :default_branch, :missing,
        repository: controller_repo.name_with_display_owner,
        default_branch: controller_repo.default_branch,
      )
    ]
  end

  def validate_repositories!(repositories)
    errors = []

    if repositories[:repo_ids].empty?
      errors << "Unable to trigger a variant analysis. None of the requested repositories could be found."
    end

    if repositories[:invalid_owners].any?
      errors << "The following repository owners are invalid: #{repositories[:invalid_owners].join(", ")}."
    end

    if repositories[:invalid_repo_lists].any?
      errors << "The following repository lists are invalid: #{repositories[:invalid_repo_lists].join(", ")}."
    end

    return if errors.empty?
    deliver_error! 422, message: errors.join(" ")
  end
end
