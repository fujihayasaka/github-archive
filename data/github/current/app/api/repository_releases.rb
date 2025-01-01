# typed: true
# frozen_string_literal: true

class Api::RepositoryReleases < Api::App
  include ReceiveSchemaWithOpenApi

  before do
    @accepted_scopes = [:repo]
  end

  def ip_allowlist_enforceable
    return :no if hmac_authenticated_internal_service_request?
    :yes
  end

  # List releases for a repository
  get "/repositories/:repository_id/releases", operation_id: "repos/list-releases" do
    control_access :list_releases,
      repo: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    can_list_drafts = can_list_draft_releases?(repo)

    results = Releases::Public.query_releases(
      repo,
      current_user,
      page: pagination[:page],
      limit: pagination[:per_page],
      allow_drafts: can_list_drafts
    )
    paginator.collection_size = results.total
    releases = results.models

    assets = ReleaseAsset.for(repo, releases).group_by { |a| a.release_id }
    prefill_releases(repo, releases, assets.values.flatten, prefill_mentions_count: true)

    options = { repo: repo, assets: assets }

    if GitHub.flipper[:api_releases_serialize_user_cache].enabled?(current_user)
      options[:object_cache] = {
        users: LruRedux::Cache.new(5)
      }
    end

    deliver :release_hash, releases, options
  rescue Search::Query::MaxOffsetError
    deliver_error! 422,
    message: "Only the first #{logged_in? ? Search::Queries::ReleaseQuery::SIGNED_IN_MAX_OFFSET : Search::Query::max_offset_default} results are available."
  end

  # Get a latest published release
  get "/repositories/:repository_id/releases/latest", operation_id: "repos/get-latest-release" do
    repo = find_repo!
    control_access :list_releases,
      repo: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    release = Releases::Public.latest_for_repository(repo, current_user)

    deliver_error! 404 if release.nil?

    prefill_releases(repo, [release], T.cast(release, Release).uploaded_assets)

    deliver :release_hash, release, repo: repo, last_modified: calc_last_modified_for_object(release)
  end

  # Get a single release by tag
  get "/repositories/:repository_id/releases/tags/*", operation_id: "repos/get-release-by-tag" do
    repo = find_repo!
    slug = params[:splat].join("/")
    release = Releases::Public.load_by_tag(repo.id, slug, include_drafts: can_list_draft_releases?(repo))

    deliver_error! 404 if release.nil?

    control_access :get_release,
      repo: repo, resource: release,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    prefill_releases(repo, [release], T.cast(release, Release).uploaded_assets)

    deliver :release_hash, release, repo: repo, last_modified: calc_last_modified_for_object(release)
  end

  # Get a single release
  get "/repositories/:repository_id/releases/:release_id", operation_id: "repos/get-release" do
    repo = find_repo!

    release = Releases::Public.load_release(int_id_param!(key: :release_id))
    record_or_404(release)

    control_access :get_release,
      repo: repo,
      resource: release,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    # hacky work-around for how we currently prefill
    prefill_releases(repo, [release], T.cast(release, Release).uploaded_assets)
    deliver :release_hash, release, last_modified: calc_last_modified_for_object(release)
  end

  # Delete a release
  delete "/repositories/:repository_id/releases/:release_id", operation_id: "repos/delete-release" do
    # Introducing strict validation of the release.delete
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("release", "delete", skip_validation: true)

    repo, release = find_repo_and_release
    control_access :delete_release,
      repo: repo,
      resource: release,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_repo_writable!(repo)

    release.destroy

    deliver_empty(status: 204)
  end

  # Generate release notes for a release with the given tag
  # The tag can be a new one or an existing one
  post "/repositories/:repository_id/releases/generate-notes", operation_id: "repos/generate-release-notes" do
    control_access :create_release,
      repo: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data = receive_with_openapi

    deliver_error! 400, message: "Missing tag_name parameter" if data["tag_name"].blank?

    begin
      name, body = Releases::Public.generate_release_notes(
        repo,
        data["tag_name"],
        target_commitish: data["target_commitish"],
        previous_tag_name: data["previous_tag_name"],
        configuration_file_path: data["configuration_file_path"]
      )
    rescue Releases::ConfigurationError => e
      deliver_error! 400, message: "Invalid release notes configuration: #{e.errors.join(", ")}"
    rescue Releases::Error => e
      deliver_error! 400, message: e.message
    end

    record_or_404(name)
    record_or_404(body)

    deliver :release_notes_content_hash, { name: name, body: body }
  end

  # Update a release
  verbs :patch, :post, "/repositories/:repository_id/releases/:release_id", operation_id: "repos/update-release" do
    _repo, release = find_repo_and_release
    control_access :edit_release,
      repo: repo = find_repo!,
      resource: release,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_repo_writable!(repo)

    # Introducing strict validation of the release.update
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    data = receive_with_schema("release", "update", skip_validation: true)
    parameters = data.symbolize_keys.slice(:tag_name, :name, :body, :draft, :prerelease, :target_commitish, :make_latest)

    parameters[:make_latest] = handle_make_latest_param(parameters, release)

    release.with_params parameters

    if release.save
      if data["discussion_category_name"] && release.can_add_discussion?(repo)
        deliver_error! 404, message: "Discussions are not enabled on this repository." unless repo.discussions_active?

        category = repo.available_discussion_categories.find_by(slug: DiscussionCategory.slug_for_name(data["discussion_category_name"]))

        discussion = release.build_discussion(
          repository: repo,
          user: current_user,
          category: category,
        )

        if !discussion.save
          deliver_error! 404, message: "Discussion could not be created. Make sure you passed a valid category name."
        end
      end

      if data["make_latest"] == "legacy"
        RepositoryLatestRelease.destroy_by(repository_id: repo.id)
      end

      prefill_releases(repo, [release], release.uploaded_assets)
      deliver :release_hash, release, repo: repo
    else
      deliver_error 422,
        errors: release.errors,
        documentation_url: @documentation_url
    end
  end

  # Create a new release
  post "/repositories/:repository_id/releases", operation_id: "repos/create-release" do
    data = receive_with_schema("release", "create-legacy")

    control_access :create_release,
      repo: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      target_commitish: data["target_commitish"]

    ensure_repo_writable!(repo)

    parameters = data.symbolize_keys.slice(:tag_name, :name, :body, :draft, :prerelease, :target_commitish, :make_latest, :generate_release_notes)

    parameters.merge!(author_id: current_user.id, repository_id: repo.id)

    parameters[:make_latest] = handle_make_latest_param(parameters)


    # clients may depend on this legacy non-standard value for `:via`. Let's
    # remove this at a later date.
    begin
      release = GitHub.context.push(from: "releases create api") do
        Releases::Public.create_release(parameters)
      end
    rescue Releases::Error => e
      deliver_error! 422, message: e.message
    end

    if release.errors.any?
      deliver_error 422,
        errors: release.errors,
        documentation_url: @documentation_url
    else
      if data["discussion_category_name"] && release.can_add_discussion?(repo)
        deliver_error! 404, message: "Discussions are not enabled on this repository." unless repo.discussions_active?

        category = repo.discussion_categories.find_by(slug: DiscussionCategory.slug_for_name(data["discussion_category_name"]))

        discussion = release.build_discussion(
          repository: repo,
          user: current_user,
          category: category,
        )

        if !discussion.save
          deliver_error! 404, message: "Discussion could not be created. Make sure you passed a valid category name."
        end
      end

      if data["make_latest"] == "legacy"
        RepositoryLatestRelease.destroy_by(repository_id: repo.id)
      end

      prefill_releases(repo, [release], release.uploaded_assets)
      deliver :release_hash, release, status: 201, repo: repo
    end
  end

  # List a release's assets
  get "/repositories/:repository_id/releases/:release_id/assets", operation_id: "repos/list-release-assets" do
    repo, release = find_repo_and_release
    control_access :get_release,
      repo: repo,
      resource: release,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    assets = release.release_assets
    assets = paginate_rel(assets)
    prefill_releases(repo, [release], assets)

    GitHub::PrefillAssociations.prefill_associations(assets, :release, available_records: [release]) if assets.present?

    deliver :release_asset_hash, assets
  end

  # Get a single release asset
  get "/repositories/:repository_id/releases/assets/:asset_id", operation_id: "repos/get-release-asset" do
    allow_media ReleaseAsset::DOWNLOAD_CONTENT_TYPE, GitHub::OCTOCAT_CONTENT_TYPE
    repo, asset = find_repo_and_release_asset
    control_access :get_release,
      repo: repo,
      resource: asset.release,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    if medias.api
      prefill_releases(repo, nil, [asset])
      deliver :release_asset_hash, asset, last_modified: calc_last_modified_for_object(asset)
    else
      deliver_error! 401, message: "Must authenticate to access this API." if !logged_in? && repo.anonymous_release_download_disabled?

      asset.download
      status 302
      response["location"] = url = asset.url(actor: current_user)

      if medias.sub_type =~ /octocat/i
        content_type GitHub::OCTOCAT_CONTENT_TYPE
        GitHub.octocat(url)
      end
    end
  end

  # edit a release asset
  patch "/repositories/:repository_id/releases/assets/:asset_id", operation_id: "repos/update-release-asset" do
    repo, asset = find_repo_and_release_asset
    control_access :edit_release,
      repo: repo,
      resource: asset.release,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_repo_writable!(repo)

    data = receive_with_schema("release-asset", "update")

    edited = T.let(nil, T.nilable(Symbol))
    %w(name label).each do |key|
      next unless value = data[key]
      asset.send("#{key}=", value)
      edited = :save
    end

    if asset.starter? && data["state"] == "uploaded"
      edited = :track_uploaded
    end

    if edited.nil? || asset.send(edited)
      prefill_releases(repo, nil, [asset])

      deliver :release_asset_hash, asset, last_modified: calc_last_modified_for_object(asset)
    else
      deliver_error 422,
        errors: asset.errors,
        documentation_url: @documentation_url
    end
  end

  # delete a single release asset
  delete "/repositories/:repository_id/releases/assets/:asset_id", operation_id: "repos/delete-release-asset" do
    # Introducing strict validation of the release-asset.delete
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("release-asset", "delete", skip_validation: true)

    repo, asset = find_repo_and_release_asset
    control_access :delete_release,
      repo: repo,
      resource: asset.release,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_repo_writable!(repo)

    asset.destroy

    deliver_empty(status: 204)
  end

  private

  alias actually_ensure_acceptable_media_types! ensure_acceptable_media_types!

  # skip this check in a before filter, do it before #control_access instead
  # Needed so that an asset's content type can be added to the list of acceptable
  # media types
  def ensure_acceptable_media_types!
  end

  def get_latest_release_tag_for_action(repo_action, repo, current_user)
    if repo_action&.latest_release_tag.nil?
      latest_release = Releases::Public.latest_for_repository(repo, current_user)
      latest_release&.tag_name
    else
      repo_action&.latest_release_tag
    end
  end

  def clean_data(method, releases, options = {})
    releases.map { |rel| Api::Serializer.serialize(method, rel, options) }.join("\n")
  end

  def control_access(*args)
    actually_ensure_acceptable_media_types!
    super
  end

  def find_repo_and_release
    repo = find_repo!
    release = repo.releases.find_by_id(int_id_param!(key: :release_id)) if repo
    deliver_error! 404 if release.nil?
    [repo, release]
  end

  def find_repo_and_release_asset
    repo = find_repo!
    asset = repo.release_assets.find_by_id(int_id_param!(key: :asset_id)) if repo
    deliver_error! 404 if asset.nil?
    [repo, asset]
  end

  def can_list_draft_releases?(repo)
    access_allowed? :list_draft_releases, repo: repo, allow_integrations: true, allow_user_via_granular_actor: true
  end

  def prefill_releases(repository, releases, assets, prefill_mentions_count: false)
    Release.prefill_releases_and_assets(repository, releases, assets, prefill_assets_downloads_counters: true)
    unless releases.nil?
      Reaction::Summary.prefill(releases)
      GitHub::PrefillAssociations.prefill_batch_method(releases, :mentions_count) if prefill_mentions_count
    end
  end

  # If explicitly passed make_latest can be one of: 'legacy', 'true' or 'false'
  # 'legacy' sets make_latest = false & reverts to legacy elasticSearch behavior
  # If not explicitly passed we set make_latest = true except for the following cases:
  # the release is a prerelease or will be once saved
  # the release will be a draft when saved
  # the release is already published and being edited
  def handle_make_latest_param(data, release = nil)
    if data[:make_latest] == "legacy" || data[:draft] || data[:prerelease]
      false
    else
      is_publishing = data.has_key?(:draft) && data[:draft] == false
      default_value = (release&.published? || release&.prerelease? || (release&.draft? && !is_publishing)) ? false : true

      ActiveModel::Type::Boolean.new.cast(data.fetch(:make_latest, default_value))
    end
  end
end
