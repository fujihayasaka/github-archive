# typed: true
# frozen_string_literal: true

class Gists::UsersController < Gists::ApplicationController
  before_action :ensure_user_or_redirect, except: [:new]
  before_action :ensure_user_viewable, except: [:new]
  skip_before_action :auto_oauth, only: [:new, :show]

  stylesheet_bundle :profile

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Spokes,
    only: [:forked]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Spokes,
    only: [:starred]

  def new
    return_to = Addressable::URI.parse(params[:return_to] || new_gist_url(host: GitHub.gist3_host_name))
    return_to.query_values = (return_to.query_values || {}).merge("signup" => "true")

    signup_params = {
      host: GitHub.host_name,
      return_to: return_to.to_s,
    }

    if params[:source]
      signup_params[:source] = params[:source]
    end

    redirect_to signup_url(signup_params)
  end

  def show
    respond_to do |wants|
      wants.html do
        auto_oauth
        return if performed?

        gists = this_user.gists.active.visible_to(current_user, visibility: params[:visibility],
                                                 viewer_is_owner: your_profile?)

        if params[:visibility] == "public" || !your_profile?
          gists = gists.from("`#{Gist.table_name}` IGNORE INDEX FOR ORDER BY (PRIMARY)")
        end

        gists = fetch_paginated_gists_by_id(gists)

        template_view_options = {
          user: this_user,
          gists: gists,
          atom_feed_path: user_gists_path(this_user, format: :atom),
          sidebar_counts: sidebar_counts,
          current_page: :all,
          has_filterable_gists: this_user.gists.is_not_disabled.exists?,
          sort_direction: params[:direction],
          viewer: current_user,
        }

        render_gist_profile(template_view_options)
      end

      wants.atom do
        gists = this_user.gists
          .from("`#{Gist.table_name}` IGNORE INDEX FOR ORDER BY (PRIMARY)")
          .are_public.is_not_disabled.order(pagination_info.sort_sql).limit(30).to_a

        render "gists/listings/feed", locals: {
          title: "Recent Gists from #{this_user.login}",
          gists: gists,
        }
      end

      wants.any { render_404 }
    end
  end

  def forked # rubocop:todo GitHub/UseRestfulActions
    respond_to do |wants|
      wants.html do
        forked_gists = this_user.gist_forks.
          visible_to(current_user, visibility: params[:visibility], viewer_is_owner: your_profile?)
        forked_gists = paginate_gists(forked_gists)

        template_view_options = {
          user: this_user,
          gists: forked_gists,
          atom_feed_path: user_forked_gists_path(this_user, format: :atom),
          sidebar_counts: sidebar_counts,
          current_page: :forked,
          has_filterable_gists: this_user.gist_forks.filter_spam_for(current_user).exists?,
          sort_direction: params[:direction],
          viewer: current_user,
        }

        render_gist_profile(template_view_options)
      end

      wants.atom do
        render "gists/listings/feed", locals: {
          title: "Recent Gists forked by #{this_user.login}",
          gists: this_user.gist_forks.are_public.order(Gist.sanitize_sql_for_order(pagination_info.sort_sql)).
            filter_spam_for(current_user).limit(30),
        }
      end
    end
  end

  def starred # rubocop:todo GitHub/UseRestfulActions
    respond_to do |wants|
      wants.html do
        starred_gists = this_user.starred_gists.
          visible_to(current_user, visibility: params[:visibility], viewer_is_owner: your_profile?)
        starred_gists = paginate_gists(starred_gists)

        template_view_options = {
          user: this_user,
          gists: starred_gists,
          atom_feed_path: user_starred_gists_path(this_user, format: :atom),
          sidebar_counts: sidebar_counts,
          current_page: :starred,
          has_filterable_gists: this_user.starred_gists.filter_spam_for(current_user).exists?,
          sort_direction: params[:direction],
          viewer: current_user,
        }

        render_gist_profile(template_view_options)
      end

      wants.atom do
        render "gists/listings/feed", locals: {
          title: "Recent Gists starred by #{this_user.login}",
          gists: this_user.starred_gists.are_public.filter_spam_for(current_user).
            order(Gist.sanitize_sql_for_order(pagination_info.sort_sql)).limit(30),
        }
      end
    end
  end

  private

  def render_gist_profile(template_view_options)
    if actor = this_user
      render "gists/users/show", locals: {
        actor: actor,
        view: GistUsers::ShowPageView.new(template_view_options),
      }
    else
      render_404
    end
  end

  def your_profile?
    this_user == current_user
  end

  def sidebar_counts
    your_profile? ? your_sidebar_counts : public_sidebar_counts
  end

  def public_sidebar_counts
    {
      forked: this_user.gist_forks.are_public.filter_spam_and_disabled_for(current_user).count,
      starred: this_user.starred_gists.are_public.filter_spam_and_disabled_for(current_user).count,
      all: this_user.gists.are_public.filter_spam_and_disabled_for(current_user).count,
    }
  end

  def your_sidebar_counts
    {
      forked: this_user.gist_forks.filter_spam_and_disabled_for(current_user).count,
      starred: this_user.starred_gists.filter_spam_and_disabled_for(current_user).count,
      all: this_user.gists.active.filter_spam_and_disabled_for(current_user).count,
    }
  end

  def paginate_gists(gists)
    if !your_profile?
      gists = gists.are_public
    end

    pagination_info.apply_to_rel(gists, for_public: !your_profile?)
  end

  # Handle auth specifics for feed requests.
  include GitHub::Authentication::Feed

  # Private: Actions that can response to atom requests.
  #
  # Returns an Array or Strings.
  def feed_actions
    %w(show forked starred)
  end

  def ensure_user_or_redirect
    return if this_user

    # User wasn't found, let's see if this is a Gist
    if this_gist = Gist.active.find_by(repo_name: params[:user_id])
      # Preserve all params that embeds can use
      options = { format: params[:format] }
      options[:callback] = params[:callback] if params[:callback]
      options[:file] = params[:file] if params[:file]
      options[:_] = params[:_] if params[:_]

      # Preserve notifications referrer parameters through the redirect
      options.merge!(notifications_referrer_params)

      if params[:sha]
        redirect_to user_gist_at_revision_path(this_gist.user_param, this_gist, params[:sha], options) and return
      elsif params[:legacy_redirect]
        handle_legacy_redirect(this_gist, params[:legacy_redirect]) and return
      else
        redirect_to user_gist_path(this_gist.user_param, this_gist, options) and return
      end
    else
      render_404
    end
  end

  def ensure_user_viewable
    return render_404 if this_user.is_enterprise_managed?
    return render_404 if this_user.hide_from_user?(current_user)
    return unless this_user.organization?
    return unless this_user.enterprise_managed_user_enabled?
    return unless business = this_user.business
    render_404 unless current_user&.enterprise_managed_business == business
  end

  # Legacy redirect for
  # /:gist_id/{stars,forks/revisions}  => /:user_id/:gist_id/{stars,forks,revisions}
  def handle_legacy_redirect(gist, legacy_redirect_path)
    case legacy_redirect_path
    when "download"
      redirect_to download_user_gist_path(gist.user_param, gist), status: 302
    when "stars"
      redirect_to stargazers_gist_path(gist.user_param, gist), status: 302
    when "forks"
      redirect_to forks_user_gist_path(gist.user_param, gist), status: 302
    when "revisions"
      redirect_to revisions_user_gist_path(gist.user_param, gist), status: 302
    else
      # We have a route constraint that should prevent this from being hit, but explicit wins
      render_404
    end
  end

  def fetch_paginated_gists_by_id(gist_scope)
    paginated_gists = pagination_info.apply_to_rel(gist_scope.select(:id)).to_a
    gist_ids = paginated_gists.map(&:id)
    raw_gists = Gist.find(gist_ids)

    # The gist records need to be inserted into the WillPaginate::Collection, but
    # replace will mess up original total_entries count, so preserve and reset that
    total_gists = paginated_gists.total_entries
    paginated_gists.replace(raw_gists)
    paginated_gists.total_entries = total_gists

    paginated_gists
  end

  memoize def this_user
    User.find_by_login(params[:user_id])
  end

  memoize def pagination_info
    GistPaginationInfo.new(params, current_page)
  end
end
