# typed: true
# frozen_string_literal: true

class Gists::GistsController < Gists::ApplicationController
  include ActionView::Helpers::NumberHelper
  include StaleModelDetection # Used for task list updates and #update_file
  # Provides url helper for the raw action
  include BlobHelper
  include GitHub::Memoizer

  before_action :ask_the_gatekeeper
  before_action :login_required,
    # star, unstar, and suggestions need logged in user
    except: [:new, :create, :show, :raw,
                :edit, :update, :update_file,
                :stargazers, :forks, :detect_language, :destroy, :fork,
                :revisions, :archive, :load_comments]

  before_action :authorization_required,
    # edit, update, update_file, destroy need authz to the gist
    except: [:new, :create, :show, :raw, :stargazers, :star, :unstar, :fork, :forks,
                :detect_language, :revisions, :archive, :suggestions,
                :subscribe, :subscription, :load_comments]

  before_action :account_2fa_requirement_interrupt, only: [:new, :edit]

  before_action :mask_url_if_secret_gist, only: [:show, :edit]
  before_action :require_xhr, only: :suggestions

  skip_before_action :auto_oauth, only: :show # only enabled for HTML formats

  # Rails CSRF checks also verify that authenticated .js files aren't loaded
  # cross-origin. We disable CSRF checks for the :show action to allow
  # cross-origin loads of JS gist-embeds. Because this is a GET endpoint, there
  # shouldn't be any harm in disabling CSRF checks.
  skip_before_action :verify_authenticity_token, only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Spokes,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsSummaries,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    only: [:edit]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    only: [:forks]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    only: [:stargazers]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    only: [:archive]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    only: [:load_comments]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Collab,
    only: [:subscription]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    only: [:suggestions]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    only: [:revisions]

  def suggestions # rubocop:todo GitHub/UseRestfulActions
    target = params[:target] || "emoji"

    case target
    when "user"
      suggester = Suggester::GistUserSuggester.new(viewer: current_user, gist: this_gist)
      render json: suggester.mentions
    when "emoji"
      render partial: "comments/suggesters/emoji_suggester", locals: {
        emojis: GitHub::Emoji,
        # FIXME: GistComment#body column is still TEXT, can't use the latest Unicode
        use_colon_emoji: true,
        tone: logged_in? ? current_user.profile_settings.preferred_emoji_skin_tone : 0,
      }
    end
  end

  def subscribe # rubocop:todo GitHub/UseRestfulActions
    list = this_gist.notifications_list
    thread = this_gist.notifications_thread

    case params[:id]
    when "subscribe"
      Notifications::Subscriptions.subscribe_to_thread(current_user, list, thread, "manual")
    when "unsubscribe", "mute"
      Notifications::Subscriptions.unsubscribe_from_thread(current_user, this_gist)
    end

    respond_to do |format|
      format.html do
        if request.xhr?
          render(
            Notifications::ThreadSubscriptionComponent.new(
              list: list,
              thread: thread,
              form_path: subscribe_gist_path,
              websocket_url: subscription_gist_path,
            ),
            layout: false,
          )
        else
          redirect_to(user_gist_path(this_gist.user_param, this_gist))
        end
      end
    end
  end

  def subscription # rubocop:todo GitHub/UseRestfulActions
    list = this_gist.notifications_list
    thread = this_gist.notifications_thread

    render(
      Notifications::ThreadSubscriptionComponent.new(
        list: list,
        thread: thread,
        form_path: subscribe_gist_path,
        websocket_url: subscription_gist_path,
      ),
      layout: false,
    )
  end

  def new
    unless logged_in? || GitHub.anonymous_gist_creation_enabled?
      redirect_to starred_gists_path and return
    end

    if logged_in? && current_user.must_verify_email?
      flash.now[:warn] = "You don't have any verified emails. We require verifying at least one email to create a gist."
    end

    gist = Gist.new(user: current_user, public: false, contents: contents_from_params)
    view = create_view_model(Gists::NewPageView, gist: gist, max_recent: 4)
    render "gists/gists/new", locals: { view: view }
  end

  def create
    new_gist_params = gist_params
    new_gist_params[:user] = current_user if logged_in?
    new_gist_params[:creator_ip] = request.remote_ip unless logged_in?

    creator = Gist::Creator.new(new_gist_params)

    GitHub.context.push(spamurai_form_signals: spamurai_form_signals)


    if gist = creator.create
      if !logged_in?
        # Keep track of gists an anonymous user creates so they can delete them.
        session[:anon_gists] ||= []
        session[:anon_gists] << gist.id.to_s
      end

      GitHub.dogstats.increment("gist.web.create", \
                                tags: ["visibility:#{gist.visibility}",
                                      "ownership:#{gist.ownership}"])

      log_data[:visibility] = gist.visibility
      flash[:ga_gist_created] = true # Track GA event on next page load
      redirect_to user_gist_path(gist.user_param, gist)
    else
      gist = creator.gist
      flash.now[:error] = gist.errors.full_messages.to_sentence
      view = create_view_model(Gists::NewPageView, gist: gist, max_recent: 4)
      render "gists/gists/new", locals: { view: view }
    end
  end

  def load_comments # rubocop:todo GitHub/UseRestfulActions
    view = create_view_model(
      Gists::ShowPageView,
      gist: this_gist,
      revision: commit_sha,
      files: all_files,
      anonymous_user_is_creator: anonymous_user_is_creator?(this_gist),
      cap_view_filter: cap_view_filter
    )
    render "gists/gists/_timeline_marker", locals: { timeline_marker: this_gist, view: view, forward_in_time_pagination: forward_in_time_pagination? }, layout: false
  end

  def show
    respond_to do |wants|
      wants.html do
        auto_oauth
        return if performed?

        async_mark_thread_as_read this_gist

        view = create_view_model(
          Gists::ShowPageView,
          gist: this_gist,
          revision: commit_sha,
          files: all_files,
          anonymous_user_is_creator: anonymous_user_is_creator?(this_gist),
          cap_view_filter: cap_view_filter,
        )
        render "gists/gists/show", locals: { view: view, forward_in_time_pagination: forward_in_time_pagination? }
      end

      wants.js do
        blank_404 do
          view = create_view_model(
            Gists::ShowPageView,
            gist: this_gist,
            revision: commit_sha,
            files: embed_files(params[:file]),
            cap_view_filter: cap_view_filter,
          )
          render "gists/gists/show", formats: [:js], locals: { view: view, forward_in_time_pagination: forward_in_time_pagination? }
        end
      end

      wants.pibb do
        blank_404 do
          # PIBBs can be embedded in iFrames on external sites.
          SecureHeaders.override_x_frame_options(request, "ALLOWALL")
          SecureHeaders.override_content_security_policy_directives(
            request,
            frame_ancestors: [SecureHeaders::PolicyManagement::STAR],
          )

          view = create_view_model(
            Gists::ShowPageView,
            gist: this_gist,
            revision: commit_sha,
            files: embed_files(params[:file]),
            cap_view_filter: cap_view_filter,
          )
          render "gists/gists/show",  formats: [:pibb], locals: { view: view, forward_in_time_pagination: forward_in_time_pagination? }
        end
      end

      wants.text do
        if params[:revision] && revision = commit_sha
          file = this_gist.sorted_files(revision).first.name
          redirect_to raw_user_gist_sha_file_path(this_gist.user_param, this_gist, revision, file), status: 301
        else
          redirect_to raw_user_gist_path(this_gist.user_param, this_gist), status: 301
        end
      end

      wants.any { render_404 }
    end
  end

  def raw # rubocop:todo GitHub/UseRestfulActions
    origin = request.headers["HTTP_ORIGIN"]

    render_url = CodeRenderingService::OriginUrlResolver.host_url(origin)
    response.headers["Access-Control-Allow-Origin"] = render_url

    sha = params[:sha] ||= this_gist.sha
    file = params[:file] ||= this_gist.sorted_files.first.name

    options = {
      user_id: this_gist.user_param,
      gist_id: this_gist.repo_name,
      sha: sha,
      file: file,
    }
    redirect_to build_raw_url(type: :gist, route_options: options)
  end

  def edit
    view = create_view_model(Gists::EditPageView, gist: this_gist)
    render "gists/gists/edit", locals: { view: view }
  end

  def update
    gist = this_gist
    previous_gist_snapshot = gist.gist_snapshot

    if gist.update(gist_params.merge(committing_user: current_user))
      gist.instrument_hydro_update_event(actor: current_user, previous_gist_snapshot: previous_gist_snapshot)
      flash[:ga_gist_updated] = true # Track GA event on next page load
      redirect_to user_gist_path(gist.user_param, gist)
    else
      flash.now[:error] = gist.errors.full_messages.to_sentence
      view = create_view_model(Gists::EditPageView, gist: gist)
      render "gists/gists/edit", locals: { view: view }
    end
  end

  def make_public # rubocop:todo GitHub/UseRestfulActions
    gist = this_gist
    previous_gist_snapshot = gist.gist_snapshot

    if gist.update(public: true)
      gist.instrument_hydro_update_event(actor: current_user, previous_gist_snapshot: previous_gist_snapshot)
      redirect_to user_gist_path(gist.user_param, gist)
    else
      flash.now[:error] = gist.errors.full_messages.to_sentence
      view = create_view_model(Gists::EditPageView, gist: gist)
      render "gists/gists/edit", locals: { view: view }
    end
  end

  # Used for TaskList updates on a file.
  def update_file # rubocop:todo GitHub/UseRestfulActions
    content =
      if operation = TaskListOperation.from(params[:task_list_operation])
        if target_file = this_gist.files.find { |f| f.oid == params[:oid] }
          operation.call(target_file.data)
        end
      else
        params[:gist][:content]
      end

    if content
      updated_oid = this_gist.update_file(
        blob_oid: params[:oid],
        content: content,
        user: current_user)
    end

    if updated_oid
      if request.xhr?
        update_url = update_user_gist_file_url(this_gist.user_param, this_gist, updated_oid)
        update_authenticity_token = authenticity_token_for(update_url, method: :put)

        render(
          status: :ok,
          json: {
            url: update_url,
            authenticity_token: update_authenticity_token,
          },
        )
      else
        redirect_to user_gist_path(this_gist.user_param, this_gist)
      end
    else
      if request.xhr?
        head :unprocessable_entity
      else
        redirect_to user_gist_path(this_gist.user_param, this_gist),
          alert: "Oops, looks like you may have been trying to update a stale gist. Please refresh and try again."
      end
    end
  end

  def stargazers # rubocop:todo GitHub/UseRestfulActions
    view = create_view_model(
      Gists::StargazersPageView,
      gist: this_gist,
      current_page: current_page,
      cap_view_filter: cap_view_filter,
    )
    render "gists/gists/stargazers", locals: { view: view }

    fresh_when strong_etag: this_gist.viewer_cache_key(current_user), template: false
  end

  def forks # rubocop:todo GitHub/UseRestfulActions
    view = create_view_model(
      Gists::ForksPageView,
      gist: this_gist,
      current_page: current_page,
      cap_view_filter: cap_view_filter,
    )
    render "gists/gists/forks", locals: { view: view }

    fresh_when strong_etag: this_gist.viewer_cache_key(current_user), template: false
  end

  def detect_language # rubocop:todo GitHub/UseRestfulActions
    render json: { language: detect_filename_language(params[:filename]) }
  end

  def destroy
    this_gist.remove

    if session_includes_gist?(this_gist)
      GitHub.dogstats.increment("gist.web.destroy", \
        tags: ["reason:deleted_by_session"])
    elsif this_gist.deletable_by_ip?(request.remote_ip)
      GitHub.dogstats.increment("gist.web.destroy", \
        tags: ["reason:deleted_by_ip"])
    else
      GitHub.dogstats.increment("gist.web.destroy", \
        tags: ["reason:deleted_by_user"])
    end

    flash[:notice] = "Gist deleted successfully."

    if this_gist.user
      redirect_to user_gists_path(this_gist.user_param)
    else
      redirect_to new_gist_path
    end
  end

  def fork # rubocop:todo GitHub/UseRestfulActions
    forked_gist = this_gist.fork(current_user)
    if forked_gist.valid?
      flash[:ga_gist_forked] = true # Track GA event on next page load
      redirect_to user_gist_path(forked_gist.user_param, forked_gist)
    else
      flash[:error] = forked_gist.errors.full_messages.to_sentence
      redirect_to user_gist_path(this_gist.user_param, this_gist)
    end
  end

  def star # rubocop:todo GitHub/UseRestfulActions
    current_user.star(this_gist, context: "gist")

    respond_to do |wants|
      wants.json { render json: { count: number_with_delimiter(this_gist.stargazer_count) } }
      wants.html { redirect_to user_gist_path(this_gist.user_param, this_gist) }
    end
  end

  def unstar # rubocop:todo GitHub/UseRestfulActions
    current_user.unstar(this_gist, context: "gist")

    respond_to do |wants|
      wants.json { render json: { count: number_with_delimiter(this_gist.stargazer_count) } }
      wants.html { redirect_to user_gist_path(this_gist.user_param, this_gist) }
    end
  end

  def revisions # rubocop:todo GitHub/UseRestfulActions
    commits = this_gist.paged_commits(this_gist.sha, current_page)

    view = create_view_model(
      Gists::RevisionPageView,
      gist: this_gist,
      commits: commits,
      params: params,
      cap_view_filter: cap_view_filter,
    )
    render "gists/gists/revisions", locals: { view: view }

    fresh_when strong_etag: this_gist.viewer_cache_key(current_user), template: false
  end

  def archive # rubocop:todo GitHub/UseRestfulActions
    commitish = params["commitish"] || this_gist.default_branch
    ac = this_gist.archive_command(commitish, params[:format])
    url = ac.codeload_url(current_user)
    expires_in 0.seconds # make sure nothing caches the redirect url (e.g. heroku)
    redirect_to url
  end

  private

  memoize def forward_in_time_pagination?
    GitHub.flipper[:gist_forward_pagination].enabled?(this_gist)
  end

  def resource_for_conditional_access
    # return the controller itself for creation actions (which don't yet have a gist)
    # so that it can answer return the future owner of the gist.
    return self if %w(create new).include?(action_name)
    # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    return :no_resource_for_conditional_access unless this_gist
    # rubocop:enable GitHub/SpecifyResourceForConditionalAccess
    this_gist
  end

  def target_for_conditional_access
    # future owner of the gist
    if %w(create new).include?(action_name)
      return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      return current_user
    end

    return :no_target_for_conditional_access unless this_gist # rubocop:todo GitHub/SpecifyTargetForConditionalAccess
    this_gist.target_for_conditional_access
  end

  # Gists are disabled on Proxima so no need to run policy (which will cause test failures)
  def tenant_verification_enforceable
    :no
  end

  # Enterprise Managed Users are not allowed to create, star, subscribe to or fork Gists
  # Only write operations will reach this stage
  def emu_ownership_satisfied(resource:, target_provider:)
    :no
  end

  # Override authorized to check if the current_user can admin the current gist
  #
  # This is called as part of authorization_required filter.
  def authorized?
    return true if this_gist.ui_content_adminable_by?(current_user)

    # Let anonymous users who created the gist delete it
    action_name == "destroy" && anonymous_user_is_creator?(this_gist)
  end

  # Just the necessary params for creating a new Gist
  #
  # We massage file_contents to fit the contents interface
  # on Gists.
  def gist_params
    gist_params = params.require(:gist).slice(:description, :public)
                                       .permit(:description, :public)
    gist_params[:contents] = params.to_unsafe_h[:gist][:contents].map do |file|
      file.update(name: file[:name].b)
    end
    gist_params
  end

  # Needed for `media_domain_url` used by `renderable_blob_url`
  def tree_name # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @tree_name ||= params[:ref] || "main"
  end
  helper_method :tree_name

  def commit_sha
    return @commit_sha if @commit_sha
    return this_gist.sha unless target = params[:revision]

    commit = this_gist.commit_for_ref(target)
    raise NotFound unless commit
    @commit_sha = commit.oid
  rescue GitRPC::ObjectMissing
    raise NotFound
  end
  helper_method :commit_sha

  def gist_specified?
    params[:user_id].present? && params[:gist_id].present?
  end

  # Is the current anonymous user the creator of this Gist?
  #
  # Returns Boolean
  def anonymous_user_is_creator?(gist)
    return false if gist.blank?
    return false unless gist.anonymous?

    session_includes_gist?(gist) || gist.deletable_by_ip?(request.remote_ip)
  end
  helper_method :anonymous_user_is_creator?

  # Does the current session include this Gist?
  #
  # Returns Boolean
  def session_includes_gist?(gist)
    session[:anon_gists]&.include?(gist.id.to_s)
  end

  # There are many reasons we may not be able to show a gist. This
  # filter goes through all possible scenarios and renders the appropriate
  # template if we cannot show the code.
  #
  # dmca         - You're hosting material that's not yours.
  # spammy       - Gist's owner has been marked as Spammy
  # ofac         - User is sanctioned by OFAC
  #
  # You can fake each of these states with params[:fakestate] equal to the
  # words listed above.
  #
  # Returns nothing.
  def ask_the_gatekeeper
    return unless gist_specified?
    return render_404 unless this_gist

    state = params[:fakestate] if real_user_site_admin?

    country            = request.headers["HTTP_X_COUNTRY"]
    gist_spammy        = this_gist.spammy? || state == "spammy"
    gist_dmca          = this_gist.access.dmca? || state == "dmca"
    gist_country_block = this_gist.access.country_block?(country)
    ofac_sanctioned    = (this_gist.private? &&
                          current_user&.has_any_trade_restrictions?) || state == "ofac"

    if gist_spammy && !this_gist.adminable_by?(current_user)
      GitHub.dogstats.increment("gist-state.spammy")
      render_404
    elsif gist_dmca
      GitHub.dogstats.increment("gist-state.dmca")
      render "gists/gists/states/dmca", locals: { gist: this_gist }, layout: "layouts/gists_disabled"
    elsif gist_country_block
      country_block_url = this_gist.country_blocks[gist_country_block]
      if GitRepositoryBlock::COUNTRY_BLOCK_DESCRIPTIONS.has_key?(gist_country_block)
        render "gists/gists/states/nation_blocklist", locals: { gist: this_gist, country_block_url: country_block_url }, layout: "layouts/gists_disabled"
      else
        render_404
      end
    elsif ofac_sanctioned && action_name != "make_public"
      render "gists/gists/states/ofac", locals: { gist: this_gist }, layout: "layouts/gists_disabled"
    end
  end

  def mask_url_if_secret_gist
    if this_gist.try(:secret?)
      flash.now[:override_octolytics_location] = true
    end
  end

  # Internal: parses contents to preload the Gist creator form
  # from params and formats them for Gist#contents. Properly formatted params look like:
  #
  #   files[][name]=foo.rb&files[][content]=foo%20content&files[][name]=empty.md
  #
  # Gist however expects that contents is an array of hashes with :name and :value keys.
  # For the above example, this method would return the following:
  #
  #   [
  #     {:name => "foo.rb",   :value => "foo content"},
  #     {:name => "empty.md", :value => nil}
  #   ]
  #
  # If contents are not supplied or invalid contents are provided, an empty array
  # will be returned.
  def contents_from_params
    files = params.to_unsafe_h[:files]

    if files.is_a?(Array) && files.all? { |f| f.is_a?(Hash) }
      GitHub.dogstats.increment("gist.new.prefill")

      files.map do |f|
        { name: f[:name], value: f[:content] }
      end
    else
      []
    end
  end

  def all_files # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @all_files ||= this_gist.sorted_files(commit_sha)
  end

  def embed_files(specified_file = nil)
    if specified_file.present?
      target = all_files.find { |blob| blob.name == specified_file }
      raise NotFound unless target

      [target]
    else
      all_files
    end
  end

  # Preserve Gist 2 behavior for PIBB/JS embeds where we respond with a blank
  # 404 page. Default behavior for GitHub is to render the full 404 page.
  def blank_404
    yield
  rescue NotFound
    head :not_found
  end
end
