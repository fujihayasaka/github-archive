# typed: true
# frozen_string_literal: true

class Api::Attestations < Api::App
  include Api::App::TwirpHelpers

  post "/repositories/:repository_id/attestations", operation_id: "repos/create-attestation" do
    GitHub.tracer.in_span("Api::Attestations#repo_create_attestation", kind: :internal) do |span|
      require_authentication!
      repo = find_repo!

      control_access :write_repo_attestation,
        repo: repo,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      ensure_feature_flag_enabled! repo.owner
      ensure_plan_supports_attestations!(repo)

      data = receive(Hash)
      form = TrustMetadata::CreateAttestationForm.new(repo, data)
      bundle, errors = form.validate_params

      if errors.any?
        error_message = errors.join(" ")
        span.status = OpenTelemetry::Trace::Status.error
        span.record_exception(StandardError.new(error_message))
        deliver_error!(400, message: error_message)
      end

      response = handle_twirp_errors do
        GitHub.tracer.in_span("create_attestation", kind: :internal) do |_|
          TrustMetadata.create_attestation_by_owner_repository(repo, bundle)
        end
      end

      attestation_id = response.try(:attestation_id)
      span.add_attributes({ "gh.repo.attestation.id" => attestation_id })

      # TODO: Return entire attestation
      deliver_raw({ id: attestation_id }, status: 201)
    end
  end

  get "/repositories/:repository_id/attestations/:subject_digest", operation_id: "repos/list-attestations" do
    GitHub.tracer.in_span("Api::Attestations#repo_attesations_by_subject_digest", kind: :internal) do |span|
      span.add_event("fetching repo attestations by subject digest", attributes: { "gh.repo.attestation.subject_digest" => params[:subject_digest], "gh.repo.id" => params[:repository_id] })
      repo = find_repo!

      control_access :read_repo_attestation,
        repo: repo,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      ensure_feature_flag_enabled! repo.owner

      subject_digest = params[:subject_digest]

      response = handle_twirp_errors do
        GitHub.tracer.in_span("fetch_attestations", kind: :internal) do |_|
          TrustMetadata.list_attestations_by_repository_subject_digest(repo, subject_digest, **page_params)
        end
      end

      span.add_attributes({ "gh.repo.attestations_size" => response.attestations.size })
      set_cursor_based_pagination_headers(response.page_info, page_params[:per_page])

      deliver_raw serialize_attestations(response.attestations), status: 200
    end
  end

  ###############
  # ORGS
  ###############

  get "/organizations/:organization_id/attestations/:subject_digest", operation_id: "orgs/list-attestations" do
    GitHub.tracer.in_span("Api::Attestations#orgs_attesations_by_subject_digest", kind: :internal) do |span|
      span.add_event("fetching org attestations by subject digest", attributes: { "gh.repo.attestation.subject_digest" => params[:subject_digest], "gh.org.id" => params[:organization_id] })
      require_authentication!
      org = find_org!
      ensure_feature_flag_enabled! org

      control_access :authenticated_user,
        resource: Platform::PublicResource.new(resource: org),
        challenge: true,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      subject_digest = params[:subject_digest]

      response = handle_twirp_errors do
        GitHub.tracer.in_span("fetch_attestations", kind: :internal) do |_|
          TrustMetadata.list_attestations_by_owner_subject_digest(org, subject_digest, **page_params)
        end
      end

      span.add_attributes({ "gh.repo.attestations_size" => response.attestations.size })
      set_cursor_based_pagination_headers(response.page_info, page_params[:per_page])

      authorized_attestations = authorize_attestations_by_repo(response.attestations)

      deliver_raw serialize_attestations(authorized_attestations), status: 200
    end
  end

  ###############
  # USERS
  ###############

  get "/user/:user_id/attestations/:subject_digest", operation_id: "users/list-attestations" do
    GitHub.tracer.in_span("Api::Attestations#users_attesations_by_subject_digest", kind: :internal) do |span|
      span.add_event("fetching user attestations by subject digest", attributes: { "gh.repo.attestation.subject_digest" => params[:subject_digest], "gh.user.id" => params[:user_id] })
      require_authentication!
      user = find_user!
      ensure_feature_flag_enabled! user

      control_access :authenticated_user,
        resource: Platform::PublicResource.new(resource: user),
        challenge: true,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      subject_digest = params[:subject_digest]

      response = handle_twirp_errors do
        GitHub.tracer.in_span("fetch_attestations", kind: :internal) do |_|
          TrustMetadata.list_attestations_by_owner_subject_digest(user, subject_digest, **page_params)
        end
      end

      span.add_attributes({ "gh.repo.attestations_size" => response.attestations.size })
      set_cursor_based_pagination_headers(response.page_info, page_params[:per_page])

      authorized_attestations = authorize_attestations_by_repo(response.attestations)

      deliver_raw serialize_attestations(authorized_attestations), status: 200
    end
  end

  private

  sig { params(repo: T.untyped).void }
  def ensure_plan_supports_attestations!(repo)
    if !repo.plan_supports?(:attestations)
      if GitHub.flipper[:attestations_skip_billing].enabled?(repo.owner)
        return
      end

      if repo.owner.is_a?(Organization)
        error_message = "Feature not available for the #{repo.owner.login_for_api} organization. To enable this feature, please upgrade the billing plan, or make this repository public."
      else
        error_message = "Feature not available for user-owned private repositories. To enable this feature, please make this repository public."
      end

      deliver_error! 422, message: error_message
    end
  end

  sig { params(attestations: T.untyped).returns(T::Array[T.untyped]) }
  def authorize_attestations_by_repo(attestations)
    repo_ids = attestations.map(&:repository_id).uniq
    repos_set = Repositories::Public.load_repositories(repo_ids).index_by(&:id)

    attestations.filter do |att|
      if repo = repos_set[att.repository_id]
        access_allowed?(:read_repo_attestation, resource: repo, repo: repo, allow_integrations: true, allow_user_via_granular_actor: true)
      end
    end
  end

  sig { params(actor: T.untyped).void }
  def ensure_feature_flag_enabled!(actor)
    if !GitHub.flipper[:attestations_api].enabled?(actor)
      deliver_error! 404
    end
  end

  sig { returns(T::Hash[Symbol, Integer]) }
  def page_params
    { before: param_to_i(params[:before]), after: param_to_i(params[:after]), per_page: param_to_i(params[:per_page]) }
  end

  sig { params(value: T.untyped).returns(T.nilable(Integer)) }
  def param_to_i(value)
    if value.blank? || !value.respond_to?(:to_i)
      nil
    else
      value.to_i.abs
    end
  end

  sig { params(page_info: Proto::TrustMetadataApi::V0::PageInfo, per_page: T.nilable(Integer)).void }
  def set_cursor_based_pagination_headers(page_info, per_page)
    if page_info["hasNextPage"]
      @links.add_current({ after:  page_info["endCursor"], before: nil, per_page: per_page == DEFAULT_PER_PAGE ? nil : per_page }, rel: "next")
    end
    if page_info["hasPreviousPage"]
      @links.add_current({ before: page_info["startCursor"], after: nil, per_page: per_page == DEFAULT_PER_PAGE ? nil : per_page }, rel: "prev")
    end
  end

  def serialize_attestations(attestations)
    return nil if !attestations

    attestations_bundles = attestations.map do |attestation|
      {
        bundle: attestation.bundle,
        repository_id: attestation.repository_id,
      }
    end

    {
      attestations: attestations_bundles,
    }
  end
end
