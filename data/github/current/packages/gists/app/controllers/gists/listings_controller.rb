# typed: true
# frozen_string_literal: true

class Gists::ListingsController < Gists::ApplicationController
  # Handle auth specifics for feed requests.
  include GitHub::Authentication::Feed

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    only: [:discover]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Spokes,
    only: [:forked]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:mine]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:my_forked]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:my_starred]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Spokes,
    only: [:starred]

  def discover # rubocop:todo GitHub/UseRestfulActions
    gists = pagination_info.apply_to_rel(Gist.public_listing, for_public: true).to_a

    respond_to do |wants|
      wants.html do
        view = create_view_model(
          Gists::ListingPageView,
          gists: gists,
          type: :public,
          pagination_info: pagination_info,
          sort_direction: params[:direction],
        )
        render "gists/listings/discover", locals: { view: view }
      end

      wants.atom do
        render "gists/listings/feed", locals: {
          title: "Public Gists",
          gists: gists,
        }
      end

      wants.any { render_404 }
    end
  end

  def forked # rubocop:todo GitHub/UseRestfulActions
    gists = pagination_info.apply_to_rel(Gist.public_listing.forked_gist_ids, for_public: true).to_a
    ids = gists.map(&:parent_id).to_a
    gists.replace load_gists_preserving_order(ids) # replace WillPaginate contents to preserve pagination info

    respond_to do |wants|
      wants.html do
        view = create_view_model(
          Gists::ListingPageView,
          gists: gists,
          type: :forked,
          atom_feed_path: forked_gists_path(format: :atom),
          pagination_info: pagination_info,
          sort_direction: params[:direction],
        )
        render "gists/listings/discover", locals: { view: view }
      end

      wants.atom do
        render "gists/listings/feed", locals: {
          title: "Forked Gists",
          gists: gists,
        }
      end

      wants.any { render_404 }
    end
  end

  def starred # rubocop:todo GitHub/UseRestfulActions
    gists = pagination_info(disable_sort: true).apply_to_rel(GistStar.recently_starred_gists.select(:gist_id), for_public: true).to_a
    ids = gists.map(&:gist_id).to_a
    gists.replace load_gists_preserving_order(ids) # replace WillPaginate contents to preserve pagination info

    respond_to do |wants|
      wants.html do
        view = create_view_model(
          Gists::ListingPageView,
          gists: gists,
          type: :starred,
          atom_feed_path: starred_gists_path(format: :atom),
          pagination_info: pagination_info,
          sort_direction: params[:direction],
        )
        render "gists/listings/discover", locals: { view: view }
      end

      wants.atom do
        render "gists/listings/feed", locals: {
          title: "Starred Gists", gists: gists
        }
      end

      wants.any { render_404 }
    end
  end

  # Legacy redirect to /:user_id
  def mine # rubocop:todo GitHub/UseRestfulActions
    if logged_in?
      redirect_to user_gists_path(current_user), status: 302
    else
      redirect_to new_gist_path, status: 302
    end
  end

  # Legacy redirect to /:user_id/forked
  def my_forked # rubocop:todo GitHub/UseRestfulActions
    if logged_in?
      redirect_to user_forked_gists_path(current_user), status: 302
    else
      redirect_to new_gist_path, status: 302
    end
  end

  # Legacy redirect to /:user_id/starred
  def my_starred # rubocop:todo GitHub/UseRestfulActions
    if logged_in?
      redirect_to user_starred_gists_path(current_user), status: 302
    else
      redirect_to new_gist_path, status: 302
    end
  end

  private

  # Private: Actions that can response to atom requests.
  #
  # Returns an Array or Strings.
  def feed_actions
    %w(discover forked starred)
  end

  def pagination_info(disable_sort: false)
    @pagination_info ||= GistPaginationInfo.new(params, current_page, disable_sort: disable_sort)
  end

  # Loads all Gists for a given list of ids preserving the order
  # of the passed ids. Also preserves duplicate ids if any.
  #
  # We must preserve duplicates or simple_pagination will get confused
  # if there are less entries than the per_page limit and pagination won't
  # be displayed.
  def load_gists_preserving_order(ids)
    gists = Gist.where(id: ids).group_by(&:id)
    ids.each_with_object([]) { |id, coll| coll << gists.fetch(id, []).first }
  end
end
