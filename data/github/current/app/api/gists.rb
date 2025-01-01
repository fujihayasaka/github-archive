# typed: true
# frozen_string_literal: true

class Api::Gists < Api::App
  include ReceiveSchemaWithOpenApi

  before do
    deliver_error!(403) unless GitHub.gist_enabled?(current_user)
  end

  # list all of a user's gists
  get "/user/:user_id/gists", operation_id: "gists/list-for-user" do
    user = find_user!
    control_access :list_gists,
      resource: Platform::PublicResource.new(resource: user),
      allow_integrations: false,
      allow_user_via_granular_actor: true

    scope = if private_profile_graphql_enabled? && user.private_profile_for?(current_user)
      Gist.none
    else
      all_or_public_gists_for_user(user)
    end
    scope = scope.select(:id)

    # For performance, we first fetch the ids, then paginate the ids,
    # and finally fetch the gists for those ids
    paginated_gists = paginate_rel(filter(scope.most_recent)).to_a
    gist_ids = T.let(paginated_gists.map(&:id), T::Array[Integer])
    gists = Gist.find(gist_ids).index_by(&:id)
    gists = gist_ids.map { |id| gists[id] }

    # Inject fetched gists into WillPaginate::Collection so that pagination
    # information is available when constructing the response
    total_gists = paginated_gists.total_entries
    paginated_gists.replace(gists)
    paginated_gists.total_entries = total_gists

    prefill_gists(paginated_gists)
    deliver :gist_hash, paginated_gists, files: true
  end

  # list all public gists
  get "/gists/public", operation_id: "gists/list-public" do
    # safe Platform::PublicResource usage
    control_access :list_gists,
      resource: Platform::PublicResource.new, # rubocop:disable GitHub/PublicResource
      allow_integrations: false,
      allow_user_via_granular_actor: true

    cap_paginated_entries! Gist::MAX_PUBLIC_GISTS_TO_PAGINATE

    gists = public_gists(skip_total_entries_count: true)
    prefill_gists(gists)

    deliver :gist_hash, gists, files: true, skip_last_page_link: true
  end

  # list the logged in user's gists
  # returns all public gists if called anonymously
  get "/gists", operation_id: "gists/list" do
    # safe Platform::PublicResource usage
    control_access :list_gists, resource: Platform::PublicResource.new, # rubocop:disable GitHub/PublicResource
      allow_integrations: false,
      allow_user_via_granular_actor: true

    gists = if logged_in?
      scope = all_or_public_gists_for_user(current_user).most_recent
      paginate_rel(filter(scope))
    else
      cap_paginated_entries! Gist::MAX_PUBLIC_GISTS_TO_PAGINATE
      public_gists
    end

    prefill_gists(gists)
    deliver :gist_hash, gists, files: true
  end

  # list the logged in user's starred gists
  get "/gists/starred", operation_id: "gists/list-starred" do

    control_access :list_user_gists,
      resource: current_user,
      allow_integrations: false,
      allow_user_via_granular_actor: true,
      challenge: true

    scope = all_or_public_gists_for_user(current_user, scope: current_user.starred_gists).active.most_recent
    gists = paginate_rel(filter(scope))

    prefill_gists(gists)
    deliver :gist_hash, gists, files: true
  end

  # get a gist
  get "/gists/:gist_id", operation_id: "gists/get" do
    control_access :get_gist,
      resource: gist = find_gist!(param_name: :gist_id),
      allow_integrations: false,
      allow_user_via_granular_actor: true

    deliver :gist_hash, gist, version: gist.default_branch, full: true, last_modified: calc_last_modified_for_object(gist)
  end

  # create a gist
  post "/gists", operation_id: "gists/create" do
    # CAP enforement requires a resource to be able to compute a
    # target_for_conditional_access, or disable_conditional_access_policies
    # must be set to true
    #
    # When anonymous gists are enabled and the current_user is nil (e.g. it's
    # an anonymous request), we have to disable CAP
    disable_cap = !logged_in? && GitHub.anonymous_gist_creation_enabled?

    control_access :create_gist,
      resource: Platform::PublicResource.new(resource: current_user),
      allow_integrations: false,
      allow_user_via_granular_actor: true,
      challenge: true,
      disable_conditional_access_policies: disable_cap # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    data = receive_with_openapi

    visibility = data.fetch("public", false)

    gist_creator = Gist::Creator.new(
      user: current_user,
      public: visibility,
      description: data["description"],
      contents: data_to_contents(data["files"]),
      creator_ip: logged_in? ? nil : remote_ip
    )
    gist_creator.gist.preserve_line_endings = true


    if gist_creator.create
      GitHub.dogstats.increment("gist.api.create", \
                                tags: ["visibility:#{gist_creator.gist.visibility}",
                                      "ownership:#{gist_creator.gist.ownership}"])

      deliver :gist_hash, gist_creator.gist, full: true, status: 201
    else
      deliver_error 422,
        errors: map_gist_errors(gist_creator.gist),
        documentation_url: "/v3/gists/#create-a-gist"
    end
  end

  # update a gist
  verbs :patch, :post, "/gists/:gist_id", operation_id: "gists/update" do
    control_access :update_gist,
                   resource: gist = find_gist!(param_name: :gist_id),
                   allow_integrations: false,
                   allow_user_via_granular_actor: true

    previous_gist_snapshot = gist.gist_snapshot
    data = receive_with_openapi

    if data.key?("description")
      gist.description = data["description"]
    end

    begin
      gist.preserve_line_endings = true
      saved = gist.update(contents: data_to_contents(data["files"], gist))
    rescue GitRPC::Failure => e
      handle_gitrpc_error e
    rescue Git::Ref::ComparisonMismatch
      deliver_error!(409, message: "Gist cannot be updated.")
    end

    if saved
      gist.instrument_hydro_update_event(actor: current_user, previous_gist_snapshot: previous_gist_snapshot)
      deliver :gist_hash, gist, full: true
    else
      deliver_error 422, errors: map_gist_errors(gist)
    end
  end

  # delete a gist
  delete "/gists/:gist_id", operation_id: "gists/delete" do
    # Introducing strict validation of the gist.delete
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_openapi(skip_validation: true)

    control_access :delete_gist,
                   resource: gist = find_gist!(param_name: :gist_id),
                   allow_integrations: false,
                   allow_user_via_granular_actor: true

    gist.remove

    GitHub.dogstats.increment("gist.api.destroy")

    deliver_empty status: 204
  end

  # fork a gist
  post "/gists/:gist_id/forks", operation_id: "gists/fork" do
    receive_with_openapi

    control_access :fork_gist,
                   resource: gist = find_gist!(param_name: :gist_id),
                   allow_integrations: false,
                   allow_user_via_granular_actor: true

    unprocessable_if_own! gist
    forked_gist = gist.fork(current_user)
    if forked_gist.valid?
      GitHub.dogstats.increment("gist.api.fork")

      deliver :gist_hash, forked_gist, version: forked_gist.default_branch, files: true, status: 201
    else
      deliver_error 422,
        errors: map_gist_errors(forked_gist),
        documentation_url: "/v3/gists/#fork-a-gist"
    end
  end

  # get gist forks
  get "/gists/:gist_id/forks", operation_id: "gists/list-forks" do
    control_access :get_gist,
      resource: gist = find_gist!(param_name: :gist_id),
      allow_integrations: false,
      allow_user_via_granular_actor: true
    forks = gist.visible_forks.not_spammy
    forks = paginate_rel(forks)

    prefill_gists(forks)

    deliver :gist_hash, forks, last_modified: calc_last_modified_for_object(gist)
  end

  # check if a Gist is starred
  get "/gists/:gist_id/star", operation_id: "gists/check-is-starred" do
    control_access :get_gist_star,
      resource: gist = find_gist!(param_name: :gist_id),
      allow_integrations: false,
      allow_user_via_granular_actor: true,
      challenge: true

    if Stars.domain.gist_starred_by_user?(gist.id, current_user.id)
      deliver_empty(status: 204, last_modified: calc_last_modified_for_object(gist))
    else
      deliver_empty(status: 404)
    end
  end

  # star a gist
  put "/gists/:gist_id/star", operation_id: "gists/star" do
    # Introducing strict validation of the gist.star
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_openapi(skip_validation: true)

    control_access :star_gist,
                   resource: gist = find_gist!(param_name: :gist_id),
                   allow_integrations: false,
                   allow_user_via_granular_actor: true

    Stars.domain.star_gist(user: current_user, gist: gist, context: "api")
    deliver_empty(status: 204)
  end

  # unstar a gist
  delete "/gists/:gist_id/star", operation_id: "gists/unstar" do
    # Introducing strict validation of the gist.unstar
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_openapi(skip_validation: true)

    control_access :unstar_gist,
                   resource: gist = find_gist!(param_name: :gist_id),
                   allow_integrations: false,
                   allow_user_via_granular_actor: true

    current_user.unstar(gist)
    deliver_empty(status: 204)
  end

  # get gist history
  get "/gists/:gist_id/commits", operation_id: "gists/list-commits" do
    control_access :get_gist,
      resource: gist = find_gist!(param_name: :gist_id),
      allow_integrations: false,
      allow_user_via_granular_actor: true

    commits = Api::Serializer.serialize(:gist_history, gist, pagination.merge(global_id_selection: global_id_selection))

    if commits.size == pagination[:per_page]
      @links.add_current({ page: current_page + 1 }, rel: "next")
    end

    if current_page > 1
      @links.add_current({ page: 1 }, rel: "first")
      @links.add_current({ page: current_page - 1 }, rel: "prev")
    end

    deliver_raw commits, last_modified: calc_last_modified_for_object(gist)
  end

  # get a gist revision
  get "/gists/:gist_id/:version", operation_id: "gists/get-revision" do
    control_access :get_gist,
      resource: gist = find_gist!(param_name: :gist_id),
      allow_integrations: false,
      allow_user_via_granular_actor: true

    commit = find_commit!(gist, params[:version], @documentation_url)
    deliver_error!(404) unless commit

    deliver :gist_hash, gist, version: commit.oid, full: true, last_modified: calc_last_modified_for_object(gist)
  end

  # Enterprise Managed Users are not allowed to create Gists
  # Only write operations will reach this stage
  def emu_ownership_satisfied(resource:, target_provider:)
    :no
  end

  private

  def rate_limit_configuration
    return super unless update_gist_route?

    Api::RateLimitConfiguration.for(
      Api::RateLimitConfiguration::GIST_UPDATE_FAMILY,
      self,
    )
  end

  def update_gist_route?
    %w[PUT PATCH].include?(request.request_method) && route_pattern == "/gists/:gist_id"
  end

  def public_gists(skip_total_entries_count: false)
    scope = filter(Gist.active.are_public.not_spammy.most_recent)

    gists = paginate_rel(scope, nil, skip_total_entries_count:)
    gists.total_entries = Gist::MAX_PUBLIC_GISTS_TO_PAGINATE if skip_total_entries_count
    gists
  end

  GIST_ERROR_MAP = {
    "can't be empty" => "can't be blank",
    "files can't be in subdirectories or include '/' in the name" => "is invalid",
  }

  def map_gist_errors(gist)
    errors = ActiveModel::Errors.new(gist)

    gist.errors.each do |error|
      if error.attribute.to_sym == :contents && (message = GIST_ERROR_MAP[error.message])
        errors.add(:files, message)
      else
        errors.add(error.attribute, error.message)
      end
    end

    errors
  end

  # Internal: Convert file params to contents form for Gists
  #
  # files - The inbound file params as required by the API
  # gist  - An optional Gist record for updates to existing Gists.
  def data_to_contents(files, gist = nil)
    return if files.blank?

    existing_contents = {}
    if gist
      # Use binary for filenames
      # https://thehub.github.com/epd/engineering/products-and-services/dotcom/encodings/#github-encoding-cheat-sheet
      gist.files.each { |file| existing_contents[file.name.b] = file }
    end

    files.map do |name, file|
      # Use binary for filenames
      # https://thehub.github.com/epd/engineering/products-and-services/dotcom/encodings/#github-encoding-cheat-sheet
      name = name.b
      filename = (file && file["filename"]) || name
      new_file = { name: filename, value: (file && file["content"]) }

      existing_file = existing_contents[name]
      new_file[:oid] = existing_file.oid if existing_file

      if existing_file && new_file[:value].blank?
        # Allow file renaming without specifying content
        if filename != name
          new_file[:value] = existing_file.data
        else
          new_file[:delete] = true
        end
      end

      new_file
    end
  end

  def filter(scope)
    # filter by updated_at
    if (since = params[:since]).present?
      message = "Invalid since parameter: '#{since}'. Must be an ISO 8601 timestamp."
      url = "/v3/gists/#parameters"
      since = parse_time!(since, message: message, documentation_url: url).getlocal
      scope = scope.since(since)
    end
    scope
  end

  def handle_gitrpc_error(e)
    # check for deletion of non-existent file
    pattern = %r{index does not contain (\w.+) at stage 0}
    if matches = e.message.match(pattern)
      deliver_error! 422,
        message: "Cannot delete non-existent file: #{matches[1]}",
        documentation_url: "/v3/gists/#edit-a-gist"
    else
      deliver_error! 500, message: "Server error"
    end
  end

  # Internal: Halts and delivers a 422 if the owner of the gist is the current user.
  #
  # Delivers a 422 or returns nil.
  def unprocessable_if_own!(gist)
    if logged_in? && (gist.user_id == current_user.id)
      deliver_error! 422,
        message: "You cannot fork your own gist.",
        errors: [api_error(:Gist, :forks, :unprocessable)],
        documentation_url: "/v3/gists/#fork-a-gist"
    end
  end

  def all_or_public_gists_for_user(user, scope: nil)
    scope ||= user.gists.active.not_spammy

    if  access_allowed?(
         :list_user_secret_gists,
         resource: user,
         target: user,
         allow_integrations: false,
         allow_user_via_granular_actor: true,
       )
      scope
    else
      scope.are_public
    end
  end

  def prefill_gists(gists)
    GitHub::PrefillAssociations.prefill_associations(gists, :user)
    GitHub::PrefillAssociations.prefill_batch_method(gists, :comment_count)
  end

  def private_profile_graphql_enabled?
    GitHub.flipper[:private_profile_graphql].enabled? ||
    GitHub.flipper[:private_profile_graphql].enabled?(current_user)
  end
end
