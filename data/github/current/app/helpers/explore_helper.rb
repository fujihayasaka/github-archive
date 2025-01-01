# typed: false
# frozen_string_literal: true

module ExploreHelper
  include HydroHelper
  include StaticAssetHelper
  # Public: Given an Explore::IndexView and either the name-with-owner or database ID of a
  # repository, this will check if we found the repository and render it if so.

  DATE_OPTIONS = {
    "daily"   => ["today",      1.day.ago],
    "weekly"  => ["this week",  7.days.ago],
    "monthly" => ["this month", 1.month.ago],
  }.freeze

  def date_text
    DATE_OPTIONS.key?(params[:since]) ? DATE_OPTIONS[params[:since]][0] : "this week"
  end

  def five_repo_contributors_cache_key(repo)
    "contributors:5:v4:#{repo.cache_key}"
  end

  def explore_featured_showcases
    Showcase::Collection.published.featured.order("updated_at DESC").limit(9).to_a.shuffle
  end

  def animating?
    unless params[:since].present? ||
      params[:language].present? ||
      params[:label].present? ||
      params[:page].present?
      "anim-fade-in"
    end
  end

  # Internal: Log explore.page_view event
  #
  # user - a User OR nil (required)
  # visitor - a Visitor (required)
  # view_context - where this instrumentation happens (optional), default: :VIEW_CONTEXT_UNKNOWN
  # record_id - the record for the view_context (optional)
  # visible_record_ids - a Hash of record ids (optional)
  #
  # Returns nothing
  def instrument_explore_page_view(
    user:,
    visitor:,
    view_context: :VIEW_CONTEXT_UNKNOWN,
    record_id: nil,
    visible_record_ids: {}
  )
    GlobalInstrumenter.instrument(
      "explore.page_view",
      actor_id: user&.id,
      visitor_id: visitor.id,
      view_context: view_context,
      record_id: record_id,
      visible_good_first_issue_ids: visible_record_ids[:visible_good_first_issue_ids].presence,
      visible_recommended_repository_ids:
        visible_record_ids[:visible_recommended_repository_ids].presence,
      visible_recommended_topic_ids:
        visible_record_ids[:visible_recommended_topic_ids].presence,
      visible_trending_developer_ids: visible_record_ids[:visible_trending_developer_ids].presence,
      visible_trending_repository_ids:
        visible_record_ids[:visible_trending_repository_ids].presence,
    )
  end

  # Internal: returns a hydro click tracking attributes hash
  #
  # actor - a User OR nil (optional), the actor that initiated this click
  # click_context - where this click happens (optional), default: :CLICK_CONTEXT_UNKNOWN
  # click_target - where this click is going
  # to take the actor/visitor (optional), default: :CLICK_TARGET_UNKNOWN
  # click_visual_representation - how this element is presented
  # to the actor/visitor (optional), default: :CLICK_VISUAL_REPRESENTATION_UNKNOWN
  # record_id - the record id of the click_target, if applicable (optional)
  # ga_click_text - the Google Analytics ga_click text to be merged into the resulting Hash
  #
  # Returns a Hash
  def explore_click_tracking_attributes(
    actor: nil,
    click_context: explore_click_context,
    click_target: :CLICK_TARGET_UNKNOWN,
    click_visual_representation: :CLICK_VISUAL_REPRESENTATION_UNKNOWN,
    record_id: nil,
    ga_click_text: nil
  )
    attributes = hydro_click_tracking_attributes(
      "explore.click",
      click_context: click_context,
      click_target: click_target,
      click_visual_representation: click_visual_representation,
      actor_id: actor&.id,
      record_id: record_id,
    )

    if ga_click_text.present?
      attributes.merge(ga_click: ga_click_text)
    else
      attributes
    end
  end

  def explore_click_context
    :CLICK_CONTEXT_UNKNOWN
  end

  # Does the trending cache exist?
  # we want to check for this so users aren't trying to re-prime the cache
  # with their browsers
  def trending_cache_exists(type, period)
    GitHub.cache.exist?("trending:#{type}:query:#{period}")
  end

  def marketplace_card_background_image(background_url)
    if background_url
      "background-image:url('#{image_path background_url}');"
    else
      ""
    end
  end
end
