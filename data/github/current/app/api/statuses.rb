# typed: true
# frozen_string_literal: true

class Api::Statuses < Api::App
  include ReceiveSchemaWithOpenApi

  # Create a Status
  #
  # Statuses are meant to be immutable.  If a SHA has a
  # changed status, the integrator should just create a new status.
  #
  # To create a status, you must have push rights to the repo. For OAuth access,
  # you must also have the appropriate scopes.
  post "/repositories/:repository_id/statuses/:sha", operation_id: "repos/create-commit-status" do
    repo = find_repo!
    control_access :write_status, resource: repo, allow_integrations: true, allow_user_via_granular_actor: true
    authorize_content(repo, :create)

    GitHub.dogstats.time("status.time", tags: ["action:create"]) do
      # Introducing strict validation of the status.create
      # JSON schema would cause breaking changes for integrators
      # skip_validation until a rollout strategy can be determined
      # see: https://github.com/github/ecosystem-api/issues/1555
      data = receive_with_schema("status", "create", skip_validation: true)
      data = attr(data, :state, :description, :target_url, :context)

      GitHub.dogstats.increment("status.context", tags: ["action:create"]) if data["context"].present?

      data["sha"] = params[:sha]

      find_commit!(repo, params[:sha], @documentation_url)
      data[:oauth_application_id] = current_app.id if current_app

      result = Statuses.domain.create(
        repository: repo,
        sha: data[:sha],
        state: data[:state],
        user: current_user,
        oauth_application_id:
        data[:oauth_application_id],
        context: data[:context],
        target_url: data[:target_url],
        description: data[:description],
      )

      case result
      when GH::Result::Ok
        with_write do
          MergeQueues.execute_from_sha!(repo, result.value.head_sha)
        end
        GitHub.dogstats.increment("status", tags: ["action:create", "valid:true"])
        deliver :status_hash, result.value, status: 201
      when GH::Result::Error
        GitHub.dogstats.increment("status", tags: ["action:create", "valid:false"])
        deliver_error 422,
          errors: result.message,
          documentation_url: @documentation_url
      end
    end
  end

  # Get statuses for a SHA, branch, or tag name.
  get "/repositories/:repository_id/statuses/*", operation_id: "repos/list-commit-statuses-for-ref" do
    ref = params[:splat].first
    control_access :read_status,
      resource: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    sha = repo.ref_to_sha(ref)
    return deliver_error 404 if sha.blank?

    # if per page is blank set default to 30
    pagination[:per_page] ||= 30

    commit_statuses = Statuses.domain.list_for_sha(
      repository_id: repo.id,
      sha: sha,
      pagination: GH::Pagination::Offset.from_api_pagination(pagination),
    )

    GitHub::PrefillAssociations.prefill_associations(commit_statuses, [:creator, :oauth_application, :repository])

    deliver :status_hash, commit_statuses
  end

  # Get combined status for a given SHA, branch, or tag name.
  get "/repositories/:repository_id/status/*", operation_id: "repos/get-combined-status-for-ref" do
    ref = params[:splat].first
    repo = find_repo!
    control_access :read_status,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    sha = repo.ref_to_sha(ref)
    unless sha
      deliver_error!(404, message: "Ref not found", documentation_url: @documentation_url)
    end

    statuses = Statuses.domain.current_statuses_for_shas(repository_id: repo.id, shas: [sha])

    combined_status = CombinedStatus.new(repo, sha, statuses: statuses, check_runs: [])
    combined_status.paginate(pagination)

    deliver :combined_status_hash, combined_status
  end

  private

  def authorize_content(authorizable, operation = :create)
    authorization = ContentAuthorizer.authorize(current_user, :status, operation, repo: authorizable)
    deliver_content_authorization_denied!(authorization) if authorization.failed?
  end

  def with_write(&block)
    last_operations = DatabaseSelector::LastOperations.from_request_creds(
      request_credentials,
    )
    ActiveRecord::Base.connected_to(role: :writing) do
      DatabaseSelector.instance.track_writes(last_operations, &block)
    end
  end
end
