# typed: true
# frozen_string_literal: true
class ReleasesController < AbstractRepositoryController
  map_to_service :release # rubocop:todo GitHub/MapToService
  map_to_service :repos, only: [:create_tag] # rubocop:todo GitHub/MapToService

  before_action :writable_repository_required,
    except: [:index, :latest, :download_latest, :tag_history, :show, :download, :check_tag, :preview, :expanded_card, :expanded_assets]
  before_action :pushers_only, except: [:index, :tag_history, :show, :download, :latest, :download_latest, :expanded_card, :expanded_assets]
  skip_before_action :cap_pagination, only: [:index], unless: :robot?

  layout "repository"
  javascript_bundle :repositories
  stylesheet_bundle :releases

  before_action :sudo_filter, only: [:create, :update], if: :action_publishing_to_marketplace?

  before_action :restrict_anonymous_download, only: [:download], if: :anonymous_download_disabled?

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Memex,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Ballast,
    ApplicationRecord::Memex,
    only: [:tag_history]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Memex,
    only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Spokes,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Memex,
    only: [:edit]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Collab,
    ApplicationRecord::NotificationsEntries,
    only: [:expanded_card]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    only: [:generate_notes]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:download]

  depends_on_clusters ApplicationRecord::IssuesPullRequests, only: [:download], optional: true

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Collab,
    only: [:check_tag]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:download_latest]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    only: [:latest]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show, :new, :edit, :index, :tag_history],
    optional: true

  depends_on_clusters ApplicationRecord::Mysql1,
  ApplicationRecord::Mysql5,
  ApplicationRecord::Authnd,
  ApplicationRecord::IamAbilities,
  ApplicationRecord::Repositories,
  ApplicationRecord::Spokes,
  ApplicationRecord::Collab,
  only: [:expanded_assets]

  def index
    respond_to do |wants|
      wants.html do
        results = Releases::Public.query_releases(
          current_repository,
          current_user,
          filter_phrase: params[:q],
          page: current_page,
          allow_drafts: current_user_can_push?
        )
        prefill_releases(results.models)
        results.models.each { |r| truncate_release_description(r, Releases::Public::LIST_VIEW_BODY_CHAR_LIMIT) }
        render "releases/index_refresh", locals: { results: results }
      end
      wants.atom do
        @releases = Releases::Public.tags_as_releases(current_repository, after: params[:after])
        prefill_index_releases_atom(@releases)

        render "releases/index", layout: false
      end
    end
  end

  # Do not break this endpoint with accept json headers. Electron apps depend on this endpoint returning JSON
  # for their auto-update code to work.
  # See this incident for links to issues, code, and more context: https://github.com/github/availability/issues/2143
  def latest # rubocop:todo GitHub/UseRestfulActions
    if rel = Releases::Public.latest_for_repository(current_repository, current_user)
      redirect_to action: "show", name: rel.tag_name
    else
      redirect_to action: "index"
    end
  end

  def download_latest # rubocop:todo GitHub/UseRestfulActions
    if rel = Releases::Public.latest_for_repository(current_repository, current_user)
      redirect_to action: "download", name: rel.tag_name, path: params[:path]
    else
      render_404
    end
  end

  param_encoding :tag_history, :q, "ASCII-8BIT"

  def tag_history # rubocop:todo GitHub/UseRestfulActions
    @releases = Releases::Public.tags_as_releases(current_repository, after: params[:after])
    GitHub::PrefillAssociations.prefill_associations(@releases, :discussion)
    @deletable_tags = Releases::Public.protected_tags_deletable_by?(current_user, @releases).to_set

    respond_to do |wants|
      wants.html do
        if @releases.empty?
          render "releases/empty", locals: { tags: true }
        else
          render "releases/tag_history"
        end
      end
      wants.html_fragment do
        # The <auto-complete> element only shows the first 9 results.
        query = params[:q].to_s
        tags = current_repository.tags.substring_filter(substring: query, limit: 9)
        render "releases/tag_history_autocomplete", formats: :html, layout: false, locals: { tags: tags }
      end
      wants.atom do
        render "releases/tag_history", layout: false
      end
    end
  end

  param_encoding :show, :name, "ASCII-8BIT"

  def show
    # Routes format must be set to false to avoid inferring request format from the file extension.
    # At the same time default file format must be set to `:html` to ensure that rails pages work as expected.
    # According to the docs default format cannot be overridden, therefore we need to set it explicitly based on the
    # Accept header.
    request.format = :json if request.headers["Accept"] == "application/json"

    include_drafts = current_user_can_push?
    @release = find_release_by_slug(params[:name], include_drafts)

    return if performed?

    unless @release.new_record?
      prefill_releases [@release]
      async_mark_thread_as_read @release
    end

    truncate_release_description(@release)

    respond_to do |wants|
      wants.html do
        if @release
          instrument_view_event
          if !@release.new_record?
            render "releases/show_refresh", locals: { release: @release }
          else
            render "releases/show"
          end
        else
          render_404
        end
      end
      # Do not break this endpoint with accept json headers. Electron apps depend on this endpoint returning JSON
      # for their auto-update code to work.
      # See this incident for links to issues, code, and more context: https://github.com/github/availability/issues/2143
      wants.json do
        if @release.nil?
          render status: 404, json: { message: "Not found" }
        else
          instrument_view_event
          render status: 200, json: release_json
        end
      end
    end
  end

  def expanded_card # rubocop:todo GitHub/UseRestfulActions
    include_drafts = current_user_can_push?
    @release = find_release_by_slug(params[:name], include_drafts)
    return unless @release

    return if performed?

    unless @release.new_record?
      prefill_releases [@release]
      async_mark_thread_as_read @release
    end

    truncate_release_description(@release)

    instrument_view_event
    latest_release = Releases::Public.latest_for_repository(current_repository, current_user)
    is_latest = @release == latest_release
    render Releases::CardComponent.new(
      @release,
      current_repository,
      is_latest: is_latest,
      is_link: true,
      show_minimal: false,
      show_author_line: false,
      open_assets: is_latest,
      writable: current_user_can_push?,
      classes: "col-md-9"
    ), layout: false
  end

  # renders the full view of the release assets list
  def expanded_assets # rubocop:todo GitHub/UseRestfulActions
    include_drafts = current_user_can_push?
    @release = find_release_by_slug(params[:name], include_drafts)
    return unless @release
    return if performed?

    prefill_releases [@release]

    render Releases::AssetListComponent.new(
      @release,
      current_repository,
      truncate: false
    ), layout: false
  end

  def new
    @release = current_repository.releases.build state: :draft
    @release.pending_tag = params[:tag] if params[:tag]
    @release.body = params[:body] if params[:body]
    @release.name = params[:title] if params[:title]
    @release.target_commitish = params[:target] if params[:target]
    @release.prerelease = (params[:prerelease] == "1" || params[:prerelease] == "true")

    if @release.potential_github_action?
      @release.build_repository_action_release
      @release.repository_action = @release.repository.action_at_root
    end

    render "releases/new"
  end

  def create
    @release = current_repository.releases.build author: current_user, reflog_data: request_reflog_data("releases create button")
    saved = save_release_from_params

    respond_to do |wants|
      wants.html do
        if saved
          redirect_to release_path(@release)
        else
          if @release.errors[:pre_receive].any?
            flash.now[:hook_message] = "Tag could not be created."
            flash.now[:hook_out] = @release.errors[:pre_receive].join(", ")
          elsif @release.errors[:tag_name].present?
            flash.now[:error] = "We weren’t able to create the release for you. Make sure you have a valid tag."
          elsif @release.errors[:body].present?
            flash.now[:error] = "We weren’t able to create the release for you. The release description is too large."
          else
            flash.now[:error] = "We weren’t able to create the release for you. Please correct the errors below."
          end
          render "releases/new"
        end
      end
      wants.json do
        if saved
          render status: 201, json: release_json
        else
          render status: 422, json: { errors: @release.errors.full_messages }
        end
      end
    end
  end

  def download # rubocop:todo GitHub/UseRestfulActions
    include_drafts = current_user_can_push?
    @release = find_release_by_slug(params[:name], include_drafts)
    return if performed?

    @asset = if !@release # nada
    # legacy route with :asset_id
    elsif (asset_id = params[:asset_id].to_i) > 0
      @release.release_assets.find_by_id(params[:asset_id].to_i)
    # current route with :name/*path
    elsif params[:path].present?
      path = params[:path].join("/")
      @release.release_assets.find_by_name(path) if GitHub::UTF8.valid_unicode3?(path)
    end

    if @asset.nil? || @asset.state != "uploaded"
      render_404 and return
    end
    @asset.download

    redirect_to @asset.direct_external_storage_url(current_user: current_user, current_repository: current_repository, request_method: request.request_method)
  end

  param_encoding :edit, :name, "ASCII-8BIT"

  def edit
    @release = find_release_by_slug
    prefill_releases [@release] if @release
    @real_release = @release

    if @release && @release.potential_github_action?
      @release.build_repository_action_release if @release.repository_action_release.nil?
    end

    truncate_release_description(@release)
    render "releases/edit" unless performed?
  end

  param_encoding :update, :name, "ASCII-8BIT"

  def update
    # Routes format must be set to false to avoid inferring request format from the file extension.
    # At the same time default file format must be set to `:html` to ensure that rails pages work as expected.
    # According to the docs default format cannot be overridden, therefore we need to set it explicitly based on the
    # Accept header.
    request.format = :json if request.headers["Accept"] == "application/json"

    @release = find_release_by_slug
    return if performed?

    saved = save_release_from_params

    respond_to do |wants|
      wants.html do
        if saved
          redirect_to release_path(@release)
        else
          @real_release = Releases::Public.load_release(@release.id)
          if @release.errors[:pre_receive].any?
            flash.now[:hook_message] = "Tag could not be created."
            flash.now[:hook_out] = @release.errors[:pre_receive].join(", ")
          elsif @release.errors[:tag_name].present?
            flash.now[:error] = "We weren’t able to create the release for you. Make sure you have a valid tag."
          elsif @release.errors[:body].present?
            flash.now[:error] = "We weren’t able to update the release for you. The release description is too large."
          else
            flash.now[:error] = "We weren’t able to create the release for you. Please correct the errors below."
          end
          render "releases/edit"
        end
      end
      wants.json do
        if saved
          render status: 200, json: release_json
        else
          render status: 422, json: { errors: @release.errors.full_messages }
        end
      end
    end
  end

  param_encoding :destroy, :name, "ASCII-8BIT"

  def destroy
    @release = find_release_by_slug!
    next_action = :index
    if !@release
      flash[:message] = "No release was found"
    elsif @release.only_tag?
      expected_oid = params[:expected_commit_oid] || @release.tag.sha
      reflog = request_reflog_data("releases delete button")
      begin
        if @release.delete_tag(expected_oid, current_user, reflog)
          flash[:message] = "Your tag was removed"
        else
          actual = current_repository.tags.find(@release.tag_name)
          flash[:error] = "The #{@release.tag_name} tag was not removed because it was not at #{expected_oid}: #{actual.inspect}"
        end
      rescue Git::Ref::HookFailed => e
        flash[:hook_out] = e.message
        flash[:hook_message] = "Tag could not be deleted."
      end
      next_action = :tag_history
    elsif @release.destroy
      flash[:message] = "Your release was removed"
    end
    redirect_to action: next_action
  end

  def create_tag # rubocop:todo GitHub/UseRestfulActions
    return render_404 if !request.xhr?

    name = params[:tag_name].gsub(/[^0-9A-Za-z_\.]/, "-")
    branch_name = params[:name] || current_repository.default_branch
    ref = current_repository.refs.find(branch_name)
    target = ref ? ref.target : current_repository.ref_to_sha(branch_name)

    current_repository.tags.create(name, target, current_user, reflog_data: request_reflog_data("create tag through releases"))
    GitHub.instrument "tag.create", user: current_user
    head :ok
  rescue Git::Ref::ExistsError
    render status: 403, json: { error: "The tag `#{name}' already exists." }
  end

  param_encoding :check_tag, :tag_name, "ASCII-8BIT"

  # Determines the status of a tag. Possible results:
  #
  # 1. Tag has a persisted Release record (duplicate)
  # 2. Tag exists, without Release record (valid)
  # 3. Tag does not exist, and is well formed (pending)
  # 4. Tag matches an existing branch (branch_exists)
  # 5. Tag does not exist, and is not well formed (invalid)
  def check_tag # rubocop:todo GitHub/UseRestfulActions
    release = find_release_by_slug!(params[:tag_name])

    # Tag exists
    if release
      if release.new_record?
        json = { status: "valid" }
      else
        json = {
          status: "duplicate",
          release_id: release.id,
          url: edit_release_path(release),
        }
      end

    # Tag does not exist
    else
      tag = current_repository.tags.build(params[:tag_name])
      if tag.well_formed?
        if current_repository.branch_exists?(tag.name)
          json = { status: "branch_exists" }
        else
          json = { status: "pending" }
        end
      else
        json = { status: "invalid" }
      end
    end

    respond_to do |format|
      format.json { render json: json }
    end
  end

  def generate_notes # rubocop:todo GitHub/UseRestfulActions
    if params[:tag_name].blank?
      render status: 400, json: { error: "Missing tag_name parameter" } and return
    end

    begin
      title, body, warning_message = Releases::Public.generate_release_notes(
        current_repository,
        params[:tag_name],
        target_commitish: params[:commitish],
        previous_tag_name: params[:previous_tag_name]
      )
    rescue Releases::ConfigurationError => e
      render status: 400, json: { error: "Invalid release notes configuration: #{e.errors.join(", ")}" }
    rescue Releases::Error => e
      render status: 400, json: { error: e.message }
    else
      json = {
        body: body,
        commitish: params[:commitish] || current_repository.default_branch,
        title: title,
        warning_message: warning_message
      }

      respond_to do |format|
        format.json { render json: json }
      end
    end
  end

  def preview # rubocop:todo GitHub/UseRestfulActions
    release = current_repository.releases.build(
      author: current_user,
      body: params[:text],
    )
    release.with_params(params[:release]) if params[:release]
    render html: release.body_html.html_safe # rubocop:disable Rails/OutputSafety
  end

  private

  # Handle auth specifics for feed requests.
  include GitHub::Authentication::Feed

  # Private: Actions that can response to atom requests.
  #
  # Returns an Array or Strings.
  def feed_actions
    %w(index tag_history)
  end

  def action_publishing_to_marketplace?
    return false unless action_params = params.dig(:release, :repository_action_release_attributes)

    ActiveModel::Type::Boolean.new.cast(action_params[:published_on_marketplace]) &&
      !ActiveModel::Type::Boolean.new.cast(release_params[:draft])
  end

  def find_release_by_slug(slug = nil, include_drafts = true)
    if rel = find_release_by_slug!(slug, include_drafts)
      rel
    else
      render_404 && nil
    end
  end

  def find_release_by_slug!(slug = nil, include_drafts = true)
    slug ||= params[:name]
    Releases::Public::Helper.load_or_build_by_tag(current_repository, slug, include_drafts: include_drafts)
  end

  def save_release_from_params
    rel_options = release_params

    rel_options = filter_action_params(rel_options)
    rel_options = filter_stack_params(rel_options)

    rel_options[:tag_name] ||= params[:tag_name] || @release.exposed_tag_name.presence
    rel_options[:generated_notes_state] ||= params[:generated_notes_state]


    was_draft = @release.draft?
    action_was_published_on_marketplace = current_repository.listed_action.present?
    stack_was_published_on_marketplace = false

    rel_options = set_latest_status(rel_options)

    @release.with_params(rel_options)
    # If the existing author cannot be loaded (removed user), use current user and move on
    @release.author = current_user unless @release.author
    @release.repository_action_release.actor = current_user if @release.repository_action_release
    @release.repository_stack_release.actor = current_user if @release.repository_stack_release
    is_new_record = @release.new_record?
    saved = nil
    saved = @release.save
    discussion_enabled = (params[:discussion_enabled] == "true" || params[:discussion_enabled] == "1")

    if discussion_enabled && release_params[:discussion_category_id] && @release.can_add_discussion?(current_repository)
      discussion = @release.build_discussion(
        repository: current_repository,
        user: current_user,
        category_id: release_params[:discussion_category_id],
      )

      if !discussion.save
        flash[:warn] = "We weren't able to create a discussion for this release. Make sure the release has a title and description."
      end
    end

    if saved && @release.repository_action_release&.published_on_marketplace?
      save_action_categories
      instrument_action_list_event unless action_was_published_on_marketplace
    end

    if was_draft && !saved
      @release.draft = true
    end

    @release.actor = current_user

    # Currently for repo based actions, action metadata is only updated when the action is published to the marketplace for each release and its handled as a part of repository_action_releases.
    # In actions on packages, we don't release each action versions to marketplace. So, we don't insert any entries in repository_action_releases table.
    # To handle the action metadata config update, we are updating the repository_action with values from config file.
    update_repository_action_from_config

    saved
  end

  def update_repository_action_from_config
    repository_action = RepositoryAction.find_by(repository: @release.repository)

    if repository_action.present? && repository_action.action_package_listed?
      repository_action.update_from_config!
    end
  end

  def filter_action_params(repo_action_params)
    unless current_repository.listable_action? && current_repository.preferred_readme.present?
      repo_action_params.delete(:repository_action_release_attributes)
    end

    repo_action_params
  end

  def filter_stack_params(repo_stack_params)
    repo_stack_params.delete(:repository_stack_release_attributes)

    repo_stack_params
  end

  def set_latest_status(rel_options)
    saving_draft = rel_options[:draft] == "true" || rel_options[:draft] == "1"
    prereleasing = rel_options[:prerelease] == "true" || rel_options[:prerelease] == "1"

    has_releases = Releases::Public.published_releases_for_repository?(current_repository.id)

    # default to true if publishing a release in a repository without published non-prerelease releases
    if !has_releases && !saving_draft && !prereleasing
      rel_options[:make_latest] = rel_options.fetch(:make_latest, true)
    end

    if rel_options.key?(:make_latest) && (saving_draft || prereleasing)
      rel_options.delete(:make_latest)
    end

    rel_options
  end

  def release_params
    return ActionController::Parameters.new unless params.key?(:release)

    params.require(:release).permit :id,
                                    :name,
                                    :body,
                                    :draft,
                                    :tag_name,
                                    :target_commitish,
                                    :previous_tag_name,
                                    :prerelease,
                                    :make_latest,
                                    :discussion_category_id,
                                    {
                                      repository_action_release_attributes: %i[id published_on_marketplace],
                                    },
                                    {
                                      repository_action_attributes: %i[id security_email],
                                    },
                                    {
                                      repository_stack_release_attributes: %i[id published_on_marketplace],
                                    },
                                    {
                                      repository_stack_attributes: %i[id security_email],
                                    },
                                    {
                                      release_assets_attributes: %i[id name size _destroy],
                                    }
  end

  memoize def ref_sha_path_extractor
    TagExtractor.new(current_repository)
  end

  class TagExtractor < GitHub::RefShaPathExtractor
    def call(path)
      pieces = path.split("/")
      if Release.untagged_name?(pieces[0])
        [pieces[0], pieces[1..-1].join("/")]
      else
        super(path)
      end
    end

    def find_ref_or_sha(maybe_sha, path)
      # Releases can only be searched by tag name, not by SHA
      # This is both an optimization to avoid wasting time searching SHA,
      # and a protection to tags named after a short SHA that would resolve wrong.
      find_ref(path)
    end
  end

  def release_json
    update_url = release_path(@release)
    update_authenticity_token = authenticity_token_for(update_url, method: :put)

    delete_url = release_path(@release)
    delete_authenticity_token = authenticity_token_for(delete_url, method: :delete)

    {
      id: @release.id,
      tag_name: @release.tag_name,
      update_url: update_url,
      update_authenticity_token: update_authenticity_token,
      delete_url: delete_url,
      delete_authenticity_token: delete_authenticity_token,
      edit_url: edit_release_path(@release),
    }
  end

  # The current release's name/path should not affect what is shown in the
  # sidebar.
  #
  # https://github.com/github/github/issues/25011
  def sidebar_tree_name
    current_repository.default_branch
  end

  def save_action_categories
    categories = []

    if (first_category = params.dig(:repository_action, :primary_category_id)).present?
      categories << first_category
    end

    if (second_category = params.dig(:repository_action, :secondary_category_id)).present?
      categories << second_category if second_category != categories.first
    end

    if categories.present?
      filter_categories = @release.repository_action.filter_category_ids
      @release.repository_action.category_ids = categories + filter_categories
    end
  end

  def instrument_action_list_event
    GlobalInstrumenter.instrument(Marketplace::Events::ACTION_LIST,
      actor: current_user,
      repository_owner: current_repository.owner,
      repository_action_id: @release.repository_action_release&.repository_action&.global_relay_id,
      repository: current_repository,
      release_tag_name: @release.tag_name,
    )
  end

  def instrument_view_event
    GlobalInstrumenter.instrument("release.viewed",
      actor: current_user,
      release: @release,
      repository: current_repository,
    )
  end

  def route_supports_advisory_workspaces?
    true
  end

  def truncate_release_description(release, limit = Releases::Public::BODY_CHAR_LIMIT)
    # Existing releases with a body larger than 25000 characters cause rendering issues or slow requests
    # resulting in Unicorn responses. We will truncate in the UI to the new limit. The existing release
    # description can be retrieved in full via API
    if release&.body&.present? && release.body.length > limit
      release.body = release.body.truncate(limit)
      release.is_body_truncated = true
    end
  end

  def prefill_releases(releases)
    tags = releases.filter_map { |release| release.tag if release.tagged? }
    Git::Ref::Collection.preload_target_objects(tags)

    refs = releases.filter_map do |release|
      [release.annotated_tag, release.tag.commit] if release.tagged?
    end
    Release.prefill_verification_status(refs.flatten)

    GitHub::PrefillAssociations.prefill_associations(releases, [
      :author,
      :uploaded_assets,
      :package_versions,
      mentions: :profile,
      discussion: :repository,
      repository_action_release: :repository_action,
    ], available_records: [current_repository])
    GitHub::PrefillAssociations.prefill_batch_method(releases, :prelude_user_logins_by_reaction)
    GitHub::PrefillAssociations.prefill_batch_method(releases, :prelude_viewer_can_react, current_user)
  end

  def prefill_index_releases_atom(releases)
    GitHub::PrefillAssociations.prefill_associations(
      @releases,
      [:author],
      available_records: [current_repository])
  end

  def anonymous_download_disabled?
    current_repository.anonymous_release_download_disabled?
  end

  def restrict_anonymous_download
    unless logged_in?
      render "releases/download_disabled", status: :forbidden
    end
  end
end
