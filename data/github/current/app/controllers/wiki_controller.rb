# typed: true
# frozen_string_literal: true

class WikiController < AbstractRepositoryController

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Iam,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Memex,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    only: [:pages]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    only: [:compare]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    only: [:history]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::NotificationsEntries,
    only: [:edit]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    only: [:help_redirect]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::NotificationsEntries,
    only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    only: [:redirect]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    only: [:toc]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:new, :edit, :history, :compare, :pages, :show, :index],
    optional: true

  # Experiment: Enable wikis to be crawled by search engines
  # https://github.com/github/security-reviews/issues/362#issuecomment-1018225770
  POPULAR_REPOS_STAR_THRESHOLD = 500

  javascript_bundle :diffs
  stylesheet_bundle :wiki

  include ActionView::Helpers::FormOptionsHelper

  skip_before_action :ask_the_gatekeeper, only: :redirect

  before_action :writable_repository_required,
    except: [:index, :show, :history, :compare, :pages, :preview, :current, :redirect, :help_redirect, :toc]
  before_action :enforce_wiki_disable,     except: [:redirect, :help_redirect]
  before_action :authorization_required,   except: [:index, :show, :pages, :history, :compare, :redirect, :help_redirect, :toc]
  before_action :require_not_blocked,      only: [:create, :update, :revert, :destroy]
  before_action :require_plan_supports_wiki,
    except: [:redirect, :help_redirect]
  before_action :fetch_wiki,               except: [:redirect, :help_redirect]
  before_action :ensure_online,            except: [:redirect, :help_redirect]
  before_action :ensure_can_write,         only: [:new, :create, :edit, :update, :revert, :destroy]
  before_action :content_authorization_required,
    only: [:new, :create, :edit, :update, :destroy]
  before_action :ensure_wiki_exists,       only: :create
  before_action :require_wiki_exists,      only: [:show, :history, :pages, :compare, :edit, :current, :update, :revert, :destroy, :toc]
  before_action :fetch_page_or_file,       only: [:show, :edit, :update, :destroy, :current, :toc]
  before_action :fetch_optional_page,      only: [:history, :compare, :revert]
  # https://github.com/github/special-projects/issues/300
  before_action :block_wiki_indexing, only: [:index, :show]
  layout "repository"

  def index
    if !@unsullied_wiki.exist?
      if current_user_can_write_wiki?
        render "wiki/blank_slate"
      else
        redirect_to repository_path(current_repository)
      end
      return
    end

    respond_to do |format|
      format.html do
        if @page = @unsullied_wiki.pages.default
          render "wiki/show"
        else
          pages
        end
      end
      format.atom do
        @pages = @unsullied_wiki.pages.latest(params[:page])
        commit = @pages.first.try(:latest_revision)

        if commit
          fresh_when strong_etag: commit.oid, last_modified: commit.committed_date, template: false
        end

        if performed? # fresh cache
          response.headers["Cache-Control"] = "public" if current_repository.public?
        else
          expires_in 5.minutes, private: !current_repository.public?
          render "wiki/index", layout: false
        end
      end
    end
  end

  def show
    respond_to do |format|
      format.html do
        if params[:id] =~ /\A(_sidebar|_footer|home)\Z/i && params[:version].blank?
          flash.keep
          return redirect_to(wikis_path, status: 301)
        elsif !@page
          if current_user_can_write_wiki?
            params[:wiki] = { name: params[:id].to_s }
            prepare_gollum_editor
            render "wiki/new"
          else
            params[:id] = nil
            render_invalid_wiki_permissions
          end
        else
          render "wiki/show"
        end
      end
    end
  end

  REVS_PER_PAGE = 30
  def history # rubocop:todo GitHub/UseRestfulActions
    page = [1, params[:page].to_i].max
    offset = if page == 1
      0
    else
      (page - 1) * REVS_PER_PAGE
    end

    subject  = @page ? @page : @unsullied_wiki
    versions = subject.revisions(offset, REVS_PER_PAGE)

    @versions = WillPaginate::Collection.new(page, REVS_PER_PAGE, subject.revision_count)
    @versions.replace(versions)

    render "wiki/history"
  end

  class InvalidDiff < RuntimeError; end

  def compare # rubocop:todo GitHub/UseRestfulActions
    if params[:version_list].present?
      versions = params[:version_list].split(/\.{2,3}/)[0..1].reverse
    elsif params[:versions].present?
      versions = params[:versions]
    else
      raise InvalidDiff
    end

    comparison = RepositoryWiki::Comparison.new(@unsullied_wiki, @page, versions)
    raise InvalidDiff unless comparison.valid?

    if request.post?
      version_list = [comparison.old_revision, comparison.new_revision].compact.join("...")
      redirect_to versions: nil, version_list: version_list
      return
    end

    view = create_view_model(Wiki::CompareView, comparison: comparison)
    render "wiki/compare", locals: { view: view }

  rescue InvalidDiff
    flash[:notice] = "Invalid or empty diff."
    if @page
      redirect_to "#{gh_wiki_path(@page, current_repository)}/_history"
    else
      redirect_to "#{gh_wikis_path(current_repository)}/_history"
    end
  end

  def pages # rubocop:todo GitHub/UseRestfulActions
    render "wiki/pages"
  end

  def toc # rubocop:todo GitHub/UseRestfulActions
    render partial: "wiki/toc", layout: false, locals: { page: @page }
  end

  def preview # rubocop:todo GitHub/UseRestfulActions
    wiki_params = params[:wiki] ||= ActionController::Parameters.new
    wiki_params.delete :commit
    format = wiki_params[:format] || params[:wiki_format]
    format = :markdown if format.blank?
    body   = (wiki_params[:body] || params[:text]).to_s
    @preview = @unsullied_wiki.pages.create_preview(format, body)

    respond_to do |format|
      format.html do
        render "wiki/preview", layout: false
      end
    end
  end

  def new
    params[:wiki] ||= @unsullied_wiki.exist? ? {} : default_home_params
    prepare_gollum_editor
    render "wiki/new"
  end

  def edit
    params[:wiki] ||= flash[:wiki] || {}
    params[:wiki][:name] ||= @page.name
    prepare_gollum_editor
    render "wiki/edit"
  end

  def current # rubocop:todo GitHub/UseRestfulActions
    render plain: @page.latest_revision
  end

  def create
    name, body, format, commit_msg = fetch_wiki_values

    if !name.blank? && !body.blank?
      begin
        if current_repository.public? &&
             current_user.recently_created? &&
             !current_user.spammy &&
             !current_repository.adminable_by?(current_user)

          GlobalInstrumenter.instrument(
            "add_account_to_spamurai_queue",
            {
              account_global_relay_id: current_user.global_relay_id,
              additional_context: "WIKI_CONTROLLER_CREATE",
              origin: :WIKI_CONTROLLER_CREATE,
              queue_global_relay_id: SpamQueue::POSSIBLE_SPAMMER_QUEUE_GLOBAL_RELAY_ID,
            },
          )

          if current_user.recently_created?(1.hour.ago)
            GitHub.dogstats.increment "spam.flagged", tags: ["flag_type:recently_created", "spam_target:wiki"]
            current_user.safer_mark_as_spammy(reason: "Attempted to create Wiki page in < 1 hour on #{current_repository.permalink}/wiki/#{name}", origin: :wiki_controller_create)
            GitHub::SpamChecker.notify(":hammer:ed User '#{current_user.display_login}' for Wiki page creation in < 1 hour on #{current_repository.permalink}/wiki/#{name}")
            # interdict the page creation entirely
            raise GitHub::Unsullied::Wiki::UnwantedEditError
          elsif GitHub::SpamChecker.test_wiki_content([name, body].compact.join(" "))
            GitHub.dogstats.increment "spam.flagged", tags: ["spam_target:wiki"]
            current_user.safer_mark_as_spammy(reason: "Attempted to create Wiki spam on #{current_repository.permalink}/wiki/#{name}", origin: :wiki_controller_create)
            GitHub::SpamChecker.notify(":hammer:ed User '#{current_user.display_login}' for attempted Wiki spam on #{current_repository.permalink}/wiki/#{name}")
            # interdict the page creation entirely
            raise GitHub::Unsullied::Wiki::UnwantedEditError
          else
            GitHub::SpamChecker.notify("Suspicious of new User '#{current_user.display_login}' creating this Wiki page: #{current_repository.permalink}/wiki/#{name}")
          end
        end

        new_page = @unsullied_wiki.pages.create(name, format, body, commit_msg, current_user)

        GitHub.context.push(spamurai_form_signals: spamurai_form_signals)
        # Note "wiki.create" event is actually for wiki **page** creation
        GitHub.instrument "wiki.create", user: current_user, format: format
        GlobalInstrumenter.instrument(
          "wiki.create",
          {
            actor: current_user,
            repository: current_repository,
            page_name: name,
            page_body: body[0..GitHub::SpamChecker::MAX_BLOB_SIZE_TO_CHECK],
            page_url: "#{current_repository.permalink}/wiki/#{name}",
          },
        )

        create_default_home_page

        if current_repository.public?
          options = {
            current_user: current_user.display_login,
            repo_path: current_repository.name_with_display_owner,
            page_id: new_page.to_param,
          }
          WikiPageSpamCheckJob.perform_later(options)
        end

      rescue GitHub::Unsullied::Wiki::DuplicatePageError
        prepare_gollum_editor
        flash.now[:error] = "Page name #{name} exists already."
        render "wiki/new"
      rescue GitHub::Unsullied::Wiki::UnwantedEditError
        prepare_gollum_editor
        flash.now[:error] = "Unable to create page"
        render "wiki/new"
      rescue GitHub::Unsullied::Wiki::TitleTooLongError => e
        prepare_gollum_editor
        flash.now[:error] = e.message
        render "wiki/new"
      rescue GitRPC::Error, GitHub::DGit::Error => e
        flash[:error] = "An unknown error occurred"
        Failbot.report(e)
      rescue GitHub::Unsullied::Wiki::Error => e
        flash[:error] = e.message
      ensure
        if !performed?
          redirect_to new_page ? gh_wiki_path(new_page, current_repository) : gh_wikis_path(current_repository)
        end
      end
    else
      prepare_gollum_editor
      flash.now[:error] = "Name and body cannot be blank."
      render "wiki/new"
    end
  end

  def update
    name, body, format, commit_msg = fetch_wiki_values

    if current_repository.public? &&
         current_user.recently_created? &&
         !current_user.spammy &&
         !current_repository.adminable_by?(current_user)

      GlobalInstrumenter.instrument(
        "add_account_to_spamurai_queue",
        {
          account_global_relay_id: current_user.global_relay_id,
          additional_context: "WIKI_CONTROLLER_UPDATE",
          origin: :WIKI_CONTROLLER_UPDATE,
          queue_global_relay_id: SpamQueue::POSSIBLE_SPAMMER_QUEUE_GLOBAL_RELAY_ID,
        },
      )

      if current_user.recently_created?(1.hour.ago)
        GitHub.dogstats.increment "spam.wiki.very-recent-user-found"
        current_user.safer_mark_as_spammy(reason: "Attempted to update Wiki page in < 1 hour on #{current_repository.permalink}/wiki/#{name}", origin: :wiki_controller_update)
        GitHub::SpamChecker.notify(":hammer:ed User '#{current_user.display_login}' for Wiki page update in < 1 hour on #{current_repository.permalink}/wiki/#{name}")
        # interdict the page update entirely
        raise GitHub::Unsullied::Wiki::UnwantedEditError
      elsif GitHub::SpamChecker.test_wiki_content([name, body].compact.join(" "))
        GitHub.dogstats.increment "spam.wiki.recent-user-found"
        current_user.safer_mark_as_spammy(reason: "Attempted an update w/Wiki spam on #{current_repository.permalink}/wiki/#{name}", origin: :wiki_controller_update)
        GitHub::SpamChecker.notify(":hammer:ed User '#{current_user.display_login}' for attempted update w/Wiki spam on #{current_repository.permalink}/wiki/#{name}")
        # interdict the page update entirely
        raise GitHub::Unsullied::Wiki::UnwantedEditError
      else
        GitHub::SpamChecker.notify("Suspicious of new User '#{current_user.display_login}' updating Wiki page: #{current_repository.permalink}/wiki/#{name}")
      end
    end

    if updated_page = @page.update(name, body, format, commit_msg, current_user)
      GitHub.context.push(spamurai_form_signals: spamurai_form_signals)
      GitHub.instrument "wiki.update", user: current_user, format: format
      GlobalInstrumenter.instrument(
        "wiki.update",
        {
          actor: current_user,
          repository: current_repository,
          page_name: name,
          page_body: body[0..GitHub::SpamChecker::MAX_BLOB_SIZE_TO_CHECK],
          page_url: "#{current_repository.permalink}/wiki/#{name}",
        },
      )

      if current_repository.public?
        options = {
          current_user: current_user.display_login,
          repo_path: current_repository.name_with_display_owner,
          page_id: updated_page.to_param,
        }
        WikiPageSpamCheckJob.perform_later(options)
      end

      if updated_page.default?
        redirect_to wikis_path
      else
        redirect_to gh_wiki_path(updated_page, current_repository)
      end
    else
      prepare_gollum_editor
      render "wiki/edit"
    end
  rescue GitHub::Unsullied::Wiki::DuplicatePageError => e
    flash[:error] = e.message
    redirect_to edit_wiki_path(current_repository.owner, current_repository, @page)
  rescue GitHub::Unsullied::Wiki::UnwantedEditError
    flash[:error] = "Unable to save changes"
    redirect_to edit_wiki_path(current_repository.owner, current_repository, @page)
  rescue GitHub::Unsullied::Wiki::Error => e
    flash[:error] = e.message
    redirect_to edit_wiki_path(current_repository.owner, current_repository, @page)
  end

  def revert # rubocop:todo GitHub/UseRestfulActions
    if @page
      @page.revert(params[:older], params[:newer], current_user)
    else
      @unsullied_wiki.revert(params[:older], params[:newer], current_user)
    end

    GitHub.instrument "wiki.revert", user: current_user, format: @page.format
    redirect_to wiki_page_path(@page)
  rescue GitRPC::InvalidObject
    flash[:notice] = "The range given contains an invalid commit."
    redirect_to wiki_compare_path(@page, "#{params[:older]}...#{params[:newer]}")
  rescue GitRPC::Error
    flash[:notice] = "This patch was not able to be reversed."
    redirect_to wiki_compare_path(@page, "#{params[:older]}...#{params[:newer]}")
  rescue GitHub::Unsullied::Wiki::UnwantedEditError
    flash[:error] = "Unable to revert changes"
    redirect_to wiki_compare_path(@page, "#{params[:older]}...#{params[:newer]}")
  rescue GitHub::Unsullied::Wiki::Error => e
    flash[:error] = e.message
    redirect_to wiki_compare_path(@page, "#{params[:older]}...#{params[:newer]}")
  end

  def destroy
    name, body, format, commit_msg = fetch_wiki_values

    if @page.remove(current_user)
      flash[:notice] = "The wiki page was successfully deleted."
      GitHub.instrument "wiki.destroy", user: current_user
    else
      flash[:notice] = "There was an error trying to delete that page."
    end
    if request.xhr?
      head 200
    else
      redirect_to wikis_path
    end
  rescue GitHub::Unsullied::Wiki::UnwantedEditError
    flash[:error] = "Unable to delete page"
    redirect_to edit_wiki_path(current_repository.owner, current_repository, @page)
  rescue GitHub::Unsullied::Wiki::Error => e
    flash[:error] = e.message
    redirect_to edit_wiki_path(current_repository.owner, current_repository, @page)
  end

  def redirect # rubocop:todo GitHub/UseRestfulActions
    if repo = current_repository
      redirect_to "/#{repo.name_with_display_owner}/wiki/#{Array(params[:args]).join("/")}"
    else
      redirect_to home_path
    end
  end

  def help_redirect # rubocop:todo GitHub/UseRestfulActions
    redirect_to home_path
  end

  private

  # Handle auth specifics for feed requests.
  include GitHub::Authentication::Feed

  # Private: Actions that can response to atom requests.
  #
  # Returns an Array or Strings.
  def feed_actions
    %w(index)
  end

  def require_not_blocked
    head 403 if logged_in? && blocked_by_owner?
  end

  def content_authorization_required
    authorize_content(:wiki, wiki: @unsullied_wiki)
  end

  def authorized?
    case action_name
    when "new", "create", "edit", "update", "destroy", "revert"
      current_user_can_write_wiki? || render_invalid_wiki_permissions
    else
      logged_in?
    end
  end

  def render_invalid_wiki_permissions
    flash[:notice] = "You do not have permission to update this wiki."
    redirect_to "#{wikis_path}/#{params[:id]}"
  end

  def enforce_wiki_disable
    if !current_repository.has_wiki?
      redirect_to repository_path(current_repository)
    end
  end

  def fetch_wiki
    @wiki = current_repository.try(:wiki)
    @unsullied_wiki = current_repository.unsullied_wiki
  end

  def ensure_online
    begin
      GitHub::DGit::Routing.all_repo_replicas(current_repository.id, true).size > 0 &&
      @unsullied_wiki.rpc.online?
    rescue GitHub::DGit::UnroutedError, GitHub::DGit::InsufficientQuorumError => e
      GitHub.logger.error(
        :exception => e,
        "code.namespace" => self.class.name,
        "code.function" => __method__
      )
      render_offline
    end
  end

  def ensure_can_write
    return render_404 if current_repository.archived?
    begin
      GitHub::DGit::Routing.all_repo_replicas(current_repository.id, true).size > 0 &&
      current_repository.dgit_wiki_write_routes
    rescue GitHub::DGit::UnroutedError, GitHub::DGit::InsufficientQuorumError => e
      GitHub.logger.error(
        :exception => e,
        "code.namespace" => self.class.name,
        "code.function" => __method__
      )
      render_offline
    end
  end

  def fetch_page_or_file(id = nil)
    id    ||= params[:id]
    version = params[:version] || (params[:skipmc] ? @unsullied_wiki.default_oid : nil)
    if id.present? && version.to_s =~ /^\d{1,39}$/ && params[:path].blank?
      redirect_to "/#{current_repository.name_with_display_owner}/wiki/#{params[:id]}"
      return
    end

    if !id.blank? && params[:path].blank?
      @page = @unsullied_wiki.pages.find(id, version || @unsullied_wiki.default_oid)
    end

    if @page
    elsif (request.get? || request.head?) && params[:action] == "show"
      # something is putting *path into params[:name]
      path = params[:path]
      path = Array(path ? path.dup : [])
      path.unshift params[:name]    if params[:name].present?
      path.unshift params[:version] if params[:version].present?
      path.unshift id               if id.present?
      file = path * "/"
      if @file = @unsullied_wiki.files.find(file)
        options = { name: file, user_id: params[:user_id],
                   repository: params[:repository] }

        if GitHub.subdomain_isolation
          options[:host] = GitHub.urls.raw_host_name
        end

        if token = raw_wiki_domain_token(:blob, path: file)
          options[:token] = token
        end

        redirect_to raw_wiki_codeload_url(options)
      end

      # if the version is set, we want to try redirecting them to the page
      if !(@file) && params[:version].present?
        flash[:notice] = "Could not find version #{params[:version].inspect}"
        redirect_to "/#{current_repository.name_with_display_owner}/wiki/#{params[:id]}"
      end
    else
      render_404
    end
  end

  # Generates a URL to a raw wiki blob served by codeload.
  #
  # options - An options hash.
  #           :host       - The hostname for the URL.
  #           :token      - A token to be included in the query string.
  #           :name       - The path to the file in the wiki.
  #           :repository - The name of the repo.
  #           :user_id    - The login of the repo owner.
  #
  # Returns a String URL.
  def raw_wiki_codeload_url(options)
    scheme = request.ssl? ? "https" : "http"
    host = options.fetch(:host, request.host)

    path = [
      GitHub.subdomain_isolation? ? %w(wiki) : %w(wiki-raw),
      escape_url_path(options[:user_id]),
      escape_url_path(options[:repository]),
      escape_url_branch(options[:name]),
    ].join("/")

    query = options.slice(:token).to_query
    query_string = query.empty? ? "" : "?#{query}"

    "#{scheme}://#{host}/#{path}#{query_string}"
  end

  def fetch_optional_page
    if params[:id].present?
      @page = @unsullied_wiki.pages.find(params[:id])
      render_404 if !@page
    end
  end

  def block_wiki_indexing
    # Index wikis only if non-world writable and popular based on star threshold set
    if current_repository.world_writable_wiki || current_repository.stargazer_count <= POPULAR_REPOS_STAR_THRESHOLD
      response.headers["X-Robots-Tag"] = "none"
    end
  end

  def fetch_wiki_values(w = params[:wiki] || {})
    name = w[:name] || w[:new_name]
    msg  = w[:commit]
    fmt  = w[:format]

    if fmt.blank? || !GitHub::Unsullied::PagesCollection::FORMAT_NAMES[fmt.to_sym]
      fmt = @page.try(:format) || :markdown
    end

    [name.try(:strip), w[:body], fmt.to_sym, msg.try(:strip)]
  end

  # Create the wiki if it does not exist.
  def ensure_wiki_exists
    return if @unsullied_wiki.exist?
    begin
      current_repository.initialize_wiki(current_user, fork_parent_wiki: false)

      # initialize_wiki can silently refuse to create the wiki, e.g., if the
      # current_user is spammy.  Check that it got created, so we don't get
      # more confusing failures later.
      if @unsullied_wiki.exist?
        flash[:notice] = "Your Wiki was created."
        GlobalInstrumenter.instrument(
          "wiki.initialize",
          {
            repository: current_repository,
          },
        )
      else
        flash[:error] = "Unable to create Wiki."
        redirect_to wikis_path
      end
    rescue GitRPC::Error, ActiveRecord::ActiveRecordError, GitHub::DGit::Error => e
      Failbot.report(e)
      flash[:error] = "There was a problem creating the wiki."
      redirect_to wikis_path
    end
  end

  # Create default Home page if it does not exist.
  def create_default_home_page
    unless @unsullied_wiki.pages.default
      name, body, format, message = fetch_wiki_values(default_home_params)
      @unsullied_wiki.pages.create(name, format, body, message, current_user)
    end
  end

  # Redirect to the wiki enable page if the repo hasn't been created yet.
  def require_wiki_exists
    unless @unsullied_wiki.exist?
      flash.keep
      redirect_to "/#{current_repository.name_with_display_owner}/wiki"
    end
  end

  def require_plan_supports_wiki
    unless wikis_visible_by_default?
      return if current_repository.plan_supports?(:wikis)

      redirect_to repository_path(current_repository), flash: {
        warn: "Upgrade to #{current_repository.next_plan} or make this repository public to enable this feature.",
      }
    end
  end

  def prepare_gollum_editor
    @editor = GitHub::Unsullied::Editor.new("wiki")
    @editor.add_params :name,
      value: (params[:wiki][:name].to_s.tr("-", " ") || @page.try(:name))
    @editor.add_params :format,
      option_tags: wiki_format_options(params[:wiki][:format] || @page.try(:format))
    @editor.add_params :body,
      value: (params[:wiki][:body] || @page.try(:data_utf8)).to_s,
      format: (params[:wiki][:format] || @page.try(:format) || "markdown").to_s
    @editor.add_params :commit,
      value: params[:wiki][:commit].to_s,
      placeholder: "Write a small message here explaining this change. (Optional)"
    @editor.add_params :preview,
      url: "/#{h current_repository.name_with_display_owner}/wiki/_preview"
    @editor.add_params :submit,
      value: "Save",
      title: "Save current changes"
  end

  def wiki_format_options(selected = nil)
    container = GitHub::Unsullied::PagesCollection::FORMAT_NAMES.to_a.map! do |(key, name)|
      [name, key.to_s]
    end.sort

    select = "markdown" if selected.blank?

    options_for_select container, selected.to_s
  end

  def current_commit
    @unsullied_wiki.commits.find(@unsullied_wiki.default_oid)
  end

  def default_home_params
    {
      name: "Home",
      body: render_to_string(partial: "wiki/default_home_body"),
      commit: "Initial Home page",
    }
  end
end
