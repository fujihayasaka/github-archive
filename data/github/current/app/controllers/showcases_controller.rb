# typed: false
# frozen_string_literal: true

class ShowcasesController < ApplicationController

  # CAP bypassed as collections are public and not supported in ghes
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  before_action :showcase_disabled

  stylesheet_bundle "site"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def index
    return redirect_to collections_path if !GitHub.enterprise?

    respond_to do |format|
      format.html do
        # show drafts to githubbers
        if preview_features? || (site_admin? && enterprise?)
          @collections = Showcase::Collection
        else
          @collections = Showcase::Collection.published
        end

        @collections = @collections
          .includes(items: { item: :primary_language })
          .order("published ASC, updated_at DESC")
          .simple_paginate(page: current_page, per_page: 15)

        render "showcases/index"
      end

      format.atom do
        @collections = Showcase::Collection.published.order("updated_at DESC").limit(15).to_a
        render "showcases/feed", formats: [:atom], layout: false
      end
    end
  end

  def show
    @collection = Showcase::Collection.find_by_slug(params[:id])

    return render_404 unless can_render_collection?

    if redirect_to_topic?
      topic_name = Showcase::Collection::TOPIC_MAPPINGS[@collection.slug]
      redirect_to "/topic/#{topic_name}"
    elsif redirect_to_collection?
      redirect_to "/collections/#{@collection.slug}"
    elsif redirect_to_explore?
      redirect_to explore_path
    else
      @items = @collection.items.preload(item: [:primary_language, { owner: :profile }]).sorted_by(item_order)

      render "showcases/show"
    end
  end

  def search # rubocop:todo GitHub/UseRestfulActions
    @phrase = params[:q]
    @page = current_page

    query = Search::Queries::ShowcaseQuery.new \
        phrase:       @phrase,
        current_user: current_user,
        remote_ip:    request.remote_ip,
        page:         @page,
        highlight:    true
    @results = query.execute

    render "showcases/search"
  end

  private

  # Handle auth specifics for feed requests.
  include GitHub::Authentication::Feed

  # Private: Actions that can response to atom requests.
  #
  # Returns an Array or Strings.
  def feed_actions
    %w(feed)
  end

  def can_render_collection?
    @collection && (@collection.published? || preview_features? || (site_admin? && enterprise?))
  end

  helper_method :item_order
  def item_order
    @order = item_order_options.delete(params[:s]) || "stars"
  end

  helper_method :item_order_options
  def item_order_options
    %w[stars language]
  end

  helper_method :related_collections
  def related_collections # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @related_collections ||= Search::Queries::RelatedShowcase.new(@collection.id).execute
  end

  helper_method :recent_collections
  def recent_collections
    Showcase::Collection.published.where("id != ?", @collection.id).order("created_at DESC").limit(2).to_a
  end

  helper_method :stargazers_you_know
  def stargazers_you_know(repository_id)
    current_user.following_starred(repository_id)
  end

  def redirect_to_topic?
    return false unless logged_in?
    return false if GitHub.enterprise?

    mappings = Showcase::Collection::TOPIC_MAPPINGS
    mappings.keys.include?(@collection.slug)
  end

  def redirect_to_explore?
    return false if GitHub.enterprise?

    Showcase::Collection::DELETED_SLUGS.include?(@collection.slug)
  end

  def redirect_to_collection?
    return false if GitHub.enterprise?

    Showcase::Collection::COLLECTION_SLUGS.include?(@collection.slug)
  end
end
