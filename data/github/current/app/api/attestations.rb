# typed: true
# frozen_string_literal: true

class Api::Attestations < Api::App
  include Api::App::TwirpHelpers

  # 34 megabytes (34 * 1024 * 1024)
  MAX_BUNDLE_SIZE = 35651584

  post "/repositories/:repository_id/attestations", operation_id: "repos/create-attestation" do
    GitHub.tracer.in_span("Api::Attestations#repo_create_attestation", kind: :internal) do |span|
      require_authentication!
      repo = find_repo!

      control_access :write_repo_attestation,
        repo: repo,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      ensure_plan_supports_attestations!(repo)

      # Limit bundle size to prevent abuse
      if request.content_length.to_i > MAX_BUNDLE_SIZE
        deliver_error!(413, message: "Value size exceeds limit")
      end

      data = receive(Hash)
      form = TrustMetadata::CreateAttestationForm.new(repo, data)
      bundle, errors = form.validate_params

      if errors.any?
        error_message = errors.join(" ")
        span.status = OpenTelemetry::Trace::Status.error
        span.record_exception(StandardError.new(error_message))
        deliver_error!(400, message: error_message)
      end

      response = wrap_twirp_with_context do
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
    GitHub.tracer.in_span("Api::Attestations#repo_attestations_by_subject_digest", kind: :internal) do |span|
      span.add_event("fetching repo attestations by subject digest", attributes: { "gh.repo.attestation.subject_digest" => params[:subject_digest], "gh.repo.id" => params[:repository_id] })
      repo = find_repo!

      control_access :read_repo_attestation,
        repo: repo,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      subject_digest = params[:subject_digest]

      response = wrap_twirp_with_context do
        GitHub.tracer.in_span("fetch_attestations", kind: :internal) do |_|
          TrustMetadata.list_attestations_by_repository_subject_digest(repo, subject_digest, predicate_type: params[:predicate_type], **page_params)
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

  delete "/organizations/:organization_id/attestations/digest/:subject_digest", operation_id: "orgs/delete-attestations-by-subject-digest", read_from_replicas: true do
    GitHub.tracer.in_span("Api::Attestations#orgs_delete_attestations_by_subject_digest", kind: :internal) do |span|
      span.add_event("delete org attestations by subject digest", attributes: { "gh.repo.attestation.subject_digest" => params[:subject_digest], "gh.org.id" => params[:organization_id] })
      require_authentication!
      org = find_org!

      # Because this endpoint is scoped by org but authorization is scoped by repository, the control_access block
      # only checks that the user is authenticated against the org. The full authorization check is done after fetching the repository
      # associated with the attestation ID from the TMA.
      control_access :authenticated_user,
        resource: Platform::PublicResource.new(resource: org),
        challenge: true,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      subject_digest = params[:subject_digest]
      delete_attestations_by_subjects!(org, [subject_digest])

      deliver_empty
    end
  end

  delete "/organizations/:organization_id/attestations/:attestation_id", operation_id: "orgs/delete-attestations-by-id", read_from_replicas: true do
    GitHub.tracer.in_span("Api::Attestations#orgs_delete_attestations_by_id", kind: :internal) do |span|
      span.add_event("delete org attestation by id", attributes: { "gh.repo.attestation.id" => params[:attestation_id], "gh.org.id" => params[:organization_id] })
      require_authentication!
      org = find_org!

      # Because this endpoint is scoped by org but authorization is scoped by repository, the control_access block
      # only checks that the user is authenticated against the org. The full authorization check is done after fetching the repository
      # associated with the attestation ID from the TMA.
      control_access :authenticated_user,
        resource: Platform::PublicResource.new(resource: org),
        challenge: true,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      attestation_id = params[:attestation_id].to_i
      delete_attestations_by_ids!(org, [attestation_id])

      deliver_empty
    end
  end

  post "/organizations/:organization_id/attestations/delete-request", operation_id: "orgs/delete-attestations-bulk", read_from_replicas: true do
    GitHub.tracer.in_span("Api::Attestations#orgs_delete_attestations_bulk", kind: :internal) do |span|
      span.add_event("delete org attestations in bulk", attributes: { "gh.org.id" => params[:organization_id] })
      require_authentication!
      org = find_org!

      # Because this endpoint is scoped by org but authorization is scoped by repository, the control_access block
      # only checks that the user is authenticated against the org. The full authorization check is done after fetching the repository
      # associated with the attestation ID from the TMA.
      control_access :authenticated_user,
        resource: Platform::PublicResource.new(resource: org),
        challenge: true,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      # Parse data from the POST request body
      data = receive(Hash)
      # Check that the data is in the expected format
      subjects = data["subject_digests"]
      ids = data["attestation_ids"]

      # Check that only one of the two fields is present
      if (subjects.nil? && ids.nil?) || (subjects.present? && ids.present?)
        deliver_error!(400, message: "The request body must be a JSON object with either a 'subject_digests' key or an 'attestation_ids' key, but not both.")
      end

      # If the 'subjects' field is present, check that it is an array and that it is not empty
      if subjects.present?
        delete_attestations_by_subjects!(org, subjects)
      else
        delete_attestations_by_ids!(org, ids)
      end

      deliver_empty
    end
  end

  get "/organizations/:organization_id/attestations/:subject_digest", operation_id: "orgs/list-attestations" do
    GitHub.tracer.in_span("Api::Attestations#orgs_attestations_by_subject_digest", kind: :internal) do |span|
      span.add_event("fetching org attestations by subject digest", attributes: { "gh.repo.attestation.subject_digest" => params[:subject_digest], "gh.org.id" => params[:organization_id] })
      require_authentication!
      org = find_org!

      control_access :authenticated_user,
        resource: Platform::PublicResource.new(resource: org),
        challenge: true,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      subject_digest = params[:subject_digest]

      response = wrap_twirp_with_context do
        GitHub.tracer.in_span("fetch_attestations", kind: :internal) do |_|
          TrustMetadata.list_attestations_by_owner_subject_digest(org, subject_digest, predicate_type: params[:predicate_type], **page_params)
        end
      end

      span.add_attributes({ "gh.repo.attestations_size" => response.attestations.size })
      set_cursor_based_pagination_headers(response.page_info, page_params[:per_page])

      authorized_attestations = authorize_attestations_by_repo(response.attestations)

      deliver_raw serialize_attestations(authorized_attestations), status: 200
    end
  end

  post "/organizations/:organization_id/attestations/bulk-list", operation_id: "orgs/list-attestations-bulk" do
    GitHub.tracer.in_span("Api::Attestations#orgs/list-attestations-bulk", kind: :internal) do |span|
      span.add_event("fetching org attestations by bulk subject digests", attributes: { "gh.org.id" => params[:organization_id] })
      require_authentication!
      org = find_org!

      control_access :authenticated_user,
        resource: Platform::PublicResource.new(resource: org),
        challenge: true,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      # Parse data from the POST request body
      data = receive(Hash)
      # Check that the data is in the expected format
      subject_digests = data["subject_digests"]
      if subject_digests.nil? || !subject_digests.is_a?(Array) || subject_digests.empty?
        deliver_error!(400, message: "The request body must be a JSON object with a 'subject_digests' key, and the value of 'subject_digests' must be a non-empty array.")
      end

      if subject_digests.size > 1024
        deliver_error!(400, message: "The 'subject_digests' key must not have more than 1024 entries.")
      end

      # check for the optional predicate type filter
      predicate_type = data["predicate_type"]

      response = wrap_twirp_with_context do
        GitHub.tracer.in_span("list_attestations_by_owner_subject_digest_bulk_digests", kind: :internal) do |_|
          TrustMetadata.list_attestations_by_owner_subject_digest_bulk_digests(org, subject_digests, predicate_type: predicate_type, **page_params)
        end
      end

      span.add_attributes({ "gh.repo.attestations_by_subject_digest_size" => response.attestations_by_subject_digest.size })
      set_cursor_based_pagination_headers(response.page_info, page_params[:per_page])

      authed_attestations = response.attestations_by_subject_digest.reduce({}) do |hash, collection|
        authorized_attestations = authorize_attestations_by_repo(collection.attestations)
        if authorized_attestations.any?
          hash[collection.subject_digest] = authorized_attestations.map { |a| { bundle: a.bundle, repository_id: a.repository_id, bundle_url: a.signed_access_signature_url } }
        end

        hash
      end

      resp = {
        attestations_subject_digests: authed_attestations
      }

      deliver_raw resp, status: 200
    end
  end

  ###############
  # USERS
  ###############

  delete "/user/:user_id/attestations/digest/:subject_digest", operation_id: "users/delete-attestations-by-subject-digest" do
    GitHub.tracer.in_span("Api::Attestations#users_delete_attestations_by_subject_digest", kind: :internal) do |span|
      span.add_event("delete user attestations by subject digest", attributes: { "gh.repo.attestation.subject_digest" => params[:subject_digest], "gh.user.id" => params[:user_id] })
      require_authentication!
      user = find_user!

      # Because this endpoint is scoped by user but authorization is scoped by repository, the control_access block
      # only checks that the user is authenticated. The full authorization check is done after fetching the repository
      # associated with the attestation ID from the TMA.
      control_access :authenticated_user,
        resource: Platform::PublicResource.new(resource: user),
        challenge: true,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      subject_digest = params[:subject_digest]
      delete_attestations_by_subjects!(user, [subject_digest])

      deliver_empty
    end
  end

  delete "/user/:user_id/attestations/:attestation_id", operation_id: "users/delete-attestations-by-id" do
    GitHub.tracer.in_span("Api::Attestations#users_delete_attestations_by_id", kind: :internal) do |span|
      span.add_event("delete user attestation by id", attributes: { "gh.repo.attestation.id" => params[:attestation_id], "gh.user.id" => params[:user_id] })
      require_authentication!
      user = find_user!

      # Because this endpoint is scoped by user but authorization is scoped by repository, the control_access block
      # only checks that the user is authenticated. The full authorization check is done after fetching the repository
      # associated with the attestation ID from the TMA.
      control_access :authenticated_user,
        resource: Platform::PublicResource.new(resource: user),
        challenge: true,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      attestation_id = params[:attestation_id].to_i
      delete_attestations_by_ids!(user, [attestation_id])

      deliver_empty
    end
  end

  get "/user/:user_id/attestations/:subject_digest", operation_id: "users/list-attestations" do
    GitHub.tracer.in_span("Api::Attestations#users_attestations_by_subject_digest", kind: :internal) do |span|
      span.add_event("fetching user attestations by subject digest", attributes: { "gh.repo.attestation.subject_digest" => params[:subject_digest], "gh.user.id" => params[:user_id] })
      require_authentication!
      user = find_user!

      control_access :authenticated_user,
        resource: Platform::PublicResource.new(resource: user),
        challenge: true,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      subject_digest = params[:subject_digest]

      response = wrap_twirp_with_context do
        GitHub.tracer.in_span("fetch_attestations", kind: :internal) do |_|
          TrustMetadata.list_attestations_by_owner_subject_digest(user, subject_digest, predicate_type: params[:predicate_type], **page_params)
        end
      end

      span.add_attributes({ "gh.repo.attestations_size" => response.attestations.size })
      set_cursor_based_pagination_headers(response.page_info, page_params[:per_page])

      authorized_attestations = authorize_attestations_by_repo(response.attestations)

      deliver_raw serialize_attestations(authorized_attestations), status: 200
    end
  end

  post "/user/:user_id/attestations/delete-request", operation_id: "users/delete-attestations-bulk" do
    GitHub.tracer.in_span("Api::Attestations#users_delete_attestations_bulk", kind: :internal) do |span|
      span.add_event("delete user attestations by bulk subject digests", attributes: { "gh.user.id" => params[:user_id] })
      require_authentication!
      user = find_user!

      control_access :authenticated_user,
        resource: Platform::PublicResource.new(resource: user),
        challenge: true,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      # Parse data from the POST request body
      data = receive(Hash)
      # Check that the data is in the expected format
      subjects = data["subject_digests"]
      ids = data["attestation_ids"]

      # Check that only one of the two fields is present
      if (subjects.nil? && ids.nil?) || (subjects.present? && ids.present?)
        deliver_error!(400, message: "The request body must be a JSON object with either a 'subject_digests' key or an 'attestation_ids' key, but not both.")
      end

      # If the 'subjects' field is present, check that it is an array and that it is not empty
      if subjects.present?
        delete_attestations_by_subjects!(user, subjects)
      else
        delete_attestations_by_ids!(user, ids)
      end

      deliver_empty
    end
  end

  # adding the 'read_from_replicas: true' configuration to satisfy a CI check but this endpoint only reads. It uses
  # the POST verb to allow bulk fetching of attestations by subject digest.
  post "/user/:user_id/attestations/bulk-list", operation_id: "users/list-attestations-bulk", read_from_replicas: true do
    GitHub.tracer.in_span("Api::Attestations#users/list-attestations-bulk", kind: :internal) do |span|
      span.add_event("fetching user attestations by bulk subject digests", attributes: { "gh.user.id" => params[:user_id] })
      require_authentication!
      user = find_user!

      control_access :authenticated_user,
        resource: Platform::PublicResource.new(resource: user),
        challenge: true,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      # Parse data from the POST request body
      data = receive(Hash)
      # Check that the data is in the expected format
      subject_digests = data["subject_digests"]
      if subject_digests.nil? || !subject_digests.is_a?(Array) || subject_digests.empty?
        deliver_error!(400, message: "The request body must be a JSON object with a 'subject_digests' key, and the value of 'subject_digests' must be a non-empty array.")
      end

      if subject_digests.size > 1024
        deliver_error!(400, message: "The 'subject_digests' key must not have more than 1024 entries.")
      end

      # check for the optional predicate type filter
      predicate_type = data["predicate_type"]

      response = wrap_twirp_with_context do
        GitHub.tracer.in_span("list_attestations_by_owner_subject_digest_bulk_digests", kind: :internal) do |_|
          TrustMetadata.list_attestations_by_owner_subject_digest_bulk_digests(user, subject_digests, predicate_type: predicate_type, **page_params)
        end
      end

      span.add_attributes({ "gh.repo.attestations_by_subject_digest_size" => response.attestations_by_subject_digest.size })
      set_cursor_based_pagination_headers(response.page_info, page_params[:per_page])

      authed_attestations = response.attestations_by_subject_digest.reduce({}) do |hash, collection|
        authorized_attestations = authorize_attestations_by_repo(collection.attestations)
        if authorized_attestations.any?
          hash[collection.subject_digest] = authorized_attestations.map { |a| { bundle: a.bundle, repository_id: a.repository_id, bundle_url: a.signed_access_signature_url } }
        end

        hash
      end

      resp = {
        attestations_subject_digests: authed_attestations
      }

      deliver_raw resp, status: 200
    end
  end

  sig { params(owner: T.any(Organization, User), subjects: T::Array[String]).returns(T.untyped) }
  def delete_attestations_by_subjects!(owner, subjects)
    subjects = subjects.uniq
    if subjects.empty?
      deliver_error!(400, message: "The value of 'subject_digests' must be a non-empty array.")
    end

    # Fetch attestation identifier information by subject digest
    # the response will include the repository ID and owner ID associated with the attestations
    # that match the subject digests. The repository ID is used to check if the user has
    # write access to the repository, and the owner ID is used to delete the attestations.
    # If the user does not have write access to any of the repositories, an error is returned.
    response = wrap_twirp_with_context do
      GitHub.tracer.in_span("get_repository_ids_by_subject_digest", kind: :internal) do |_|
        TrustMetadata.get_repository_ids_by_subject_digest(owner.id, subjects)
      end
    end

    # Filter the repositories to only those that the owner has write access to
    # and group the subject digests by owner ID.
    # This is necessary because the TMA API requires the owner ID to delete attestations.
    digests_by_repo = response.repos.reduce({}) do |hash, entry|
      repo = if FeatureFlag.vexi.enabled?(:repos_by_id_api, default: false)
        ::Repositories.domain.by_id(entry.repository_id)
      else
        Repository.find_by(id: entry.repository_id)
      end
      if access_allowed?(:write_repo_attestation, resource: repo, repo: repo, allow_integrations: true, allow_user_via_granular_actor: true)
        hash[entry.repository_id] ||= []
        hash[entry.repository_id] << entry.subject_digest
      end

      hash
    end

    if digests_by_repo.empty?
      deliver_error!(404, message: "No attestations found")
    end

    # delete attestations by subject digest if the current user has access to the repository
    digests_by_repo.each do |repo_id, digests|
      wrap_twirp_with_context do
        GitHub.tracer.in_span("delete_attestations_by_subject_digest", kind: :internal) do |_|
          TrustMetadata.delete_attestations_by_owner_subject_digest(owner.id, repo_id, digests)
        end
      end
    end
  end

  sig { params(owner: T.any(Organization, User), ids: T::Array[Integer]).returns(T.untyped) }
  def delete_attestations_by_ids!(owner, ids)
    ids = ids.uniq
    if ids.empty?
      deliver_error!(400, message: "The request body must be a JSON object with a 'attestation_ids' key, and the value of 'attestation_ids' must be a non-empty array.")
    end

    # Fetch attestation identifier information by attestation ID
    # the response will include the repository ID and owner ID associated with the attestation IDs.
    # The repository ID is used to check if the owner has write access to the repository
    # and the owner ID is used to delete the attestations.
    # If the current user does not have write access to any of the repositories, an error is returned.
    response = wrap_twirp_with_context do
      GitHub.tracer.in_span("get_repository_ids_by_attestation_id", kind: :internal) do |_|
        TrustMetadata.get_repository_ids_by_attestation_id(owner.id, ids)
      end
    end

    repository_ids = response.repos.map(&:repository_id).compact
    repositories = Repository.where(id: repository_ids).index_by(&:id)

    # Filter the repositories to only those that the owner has write access to
    # and group the attestation IDs by owner ID.
    # This is necessary because the TMA API requires the owner ID to delete attestations.
    filtered_attestations = []
    response.repos.each do |entry|
      repo = repositories[entry.repository_id]
      if access_allowed?(:write_repo_attestation, resource: repo, repo: repo, allow_integrations: true, allow_user_via_granular_actor: true)
        filtered_attestations << entry.id
      end
    end

    if filtered_attestations.empty?
      deliver_error!(404, message: "No attestations found")
    end

    # If it's valid, delete attestations by list of IDs
    wrap_twirp_with_context do
      GitHub.tracer.in_span("delete_attestations_by_id", kind: :internal) do |_|
        TrustMetadata.delete_attestations_by_owner_and_id(owner.id, filtered_attestations)
      end
    end
  end

  # Because public repositories are, well, public, you may read resources
  # associated with that repository even if your API token has not been
  # explicitly granted permission to access that resource.
  #
  # When we tried testing the orgs/list-attestations-bulk endpoint for a public
  # repository, we found that the authorized_user_via_unauthorized_integration
  # check was failing.
  #
  # The reason is that the UserViaGranularActorAuthorizer will refuse to
  # hydrate a bot user for an unauthorized integration/granular actor
  # if it determines that the request is trying to write something to the API,
  # which it does by checking the requests' HTTP verb.
  #
  # Since the orgs/list-attestations-bulk endpoint is a read request that
  # unfortunately must use a POST verb, this tripped us up. To resolve this,
  # we override the `read_request?` method to return true if the route is
  # hitting the bulk-list endpoint.
  def self.read_request?(env)
    T.bind(self, T.untyped) # necessary to call super without Sorbet complaining
    if Api::App.route_pattern(env) == "/organizations/:organization_id/attestations/bulk-list" || Api::App.route_pattern(env) == "/user/:user_id/attestations/bulk-list"
      true
    else
      super
    end
  end

  private

  sig { params(repo: T.untyped).void }
  def ensure_plan_supports_attestations!(repo)
    if !repo.plan_supports?(:attestations)
      if FeatureFlag.vexi.enabled?(:attestations_skip_billing, repo.owner, default: false)
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

  # This method wraps twirp calls with error handling and context, sent as
  # HTTP headers to the TMA, we use for analytics for API calls made from
  # within GitHub Actions
  def wrap_twirp_with_context
    # capture context from GitHub Actions:
    # SiteScopedIntegrationInstallations are not always going to be from Actions,
    # but if we filter for the Actions bot actor_id, this lets us track which repos
    # Actions requests are coming from
    case current_integration_installation
    when SiteScopedIntegrationInstallation
      GitHub.context.push(site_scoped_integration_installation_target_id: current_integration_installation.target_id)
      GitHub.context.push(site_scoped_integration_installation_repo_id: current_integration_installation.repository_ids.first)
    end

    handle_twirp_errors do
      yield
    end
  end

  def serialize_attestations(attestations)
    return nil if !attestations

    attestations_bundles = attestations.map do |attestation|
      {
        bundle: attestation.bundle,
        repository_id: attestation.repository_id,
        bundle_url: attestation.signed_access_signature_url
      }
    end

    {
      attestations: attestations_bundles,
    }
  end
end
