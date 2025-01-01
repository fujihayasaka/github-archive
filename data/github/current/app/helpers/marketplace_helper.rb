# typed: false
# rubocop:disable Primer/PrimerOcticon
# frozen_string_literal: true

module MarketplaceHelper
  extend ActionView::Helpers::TagHelper
  include GitHub::ResilienceMixin
  include StaticAssetHelper
  include Marketplace::Domain::Provider

  DEFAULT_SORT_VALUE = "popularity-desc"
  DEFAULT_SORT_LABEL = "Most installed/starred"
  SORTS = [
    [DEFAULT_SORT_LABEL, DEFAULT_SORT_VALUE],
    ["Best match", "match-desc"],
    ["Recently added", "created-desc"],
    ["Most used in past week", "top-1-desc"],
    ["Most used in past month", "top-30-desc"],
    ["Most used in past 6 months", "top-180-desc"]
  ].freeze

  SORTS_WITH_DEPENDENT_SORT = [
    [DEFAULT_SORT_LABEL, DEFAULT_SORT_VALUE],
    ["Recently added", "created-desc"],
    ["Best match", "match-desc"],
    ["Repos using (Actions)", "dependents-count-desc"]
  ].freeze

  SORT_VALUE_TO_LABEL =
    {
      DEFAULT_SORT_VALUE => DEFAULT_SORT_LABEL,
      "created-desc" => "Recently added",
      "match-desc" => "Best Match",
      "top-1-desc" => "Most used in past week",
      "top-30-desc" => "Most used in past month",
      "top-180-desc" => "Most used in past 6 months"
    }

  SORT_VALUE_TO_LABEL_WITH_DEPENDENT_SORT = SORT_VALUE_TO_LABEL.merge({ "dependents-count-desc" => "Repos using (Actions)" })

  # Public: Generates an optimized image tag. Loads the correct asset based on the user's type of display (high resolution vs low)
  #   Only for CDN assets that have Fastly IO enabled.
  #   Fastly IO docs: https://docs.fastly.com/api/imageopto
  def marketplace_optimized_image_tag(url, options = {})
    optimized_url = Addressable::URI.parse(url)

    image_params = {
      width: options[:width],
      height: options[:height],
      format: options[:format] || "jpeg",
      auto: options[:auto] || "webp",
    }.compact

    optimized_url.query_values = (optimized_url.query_values || {}).merge(image_params)

    options[:srcset] = "#{optimized_url}&dpr=1.5 1.5x, #{optimized_url}&dpr=2 2x"

    ActionController::Base.helpers.image_tag(optimized_url.to_s, options.except(:format, :auto))
  end

  def marketplace_logo(name:, logo_url:, bgcolor:, classes: nil, by_github: false)
    classes = "CircleBadge #{classes}"
    classes = "#{classes} CircleBadge--github" if by_github

    style = "background-color: ##{ bgcolor };"

    content_tag(:div, class: classes, style: style) do
      image_tag(logo_url.to_s, class: "CircleBadge-icon", alt: "")
    end
  end

  def marketplace_plan_cancel_button(on_free_trial:, next_billing_date:, options: {})
    if on_free_trial
      button_text = "Cancel free trial"
      options[:"data-confirm"] = "Cancelling this free trial will cancel your subscription to this app and your free trial will expire. This change will take effect immediately. Are you sure you wish to continue?"
    else
      button_text = "Cancel this plan"
      options[:"data-confirm"] = "Cancelling this plan will end your subscription to this app on #{next_billing_date.to_formatted_s(:date)}. Are you sure you wish to continue?"
    end
    button_tag(button_text, options)
  end

  def marketplace_logo_text_class(light = true)
    if light
      "color-text-white"
    else
      "color-fg-default"
    end
  end

  def marketplace_card_background_image(background_url)
    if background_url
      "background-image:url('#{image_path background_url}');"
    else
      ""
    end
  end

  # Public: Should any Marketplace-related calls to action be shown?
  def show_marketplace_calls_to_action?
    GitHub.marketplace_enabled? && logged_in?
  end

  # Public: Should the Marketplace call to action for continuous integration be shown
  # for the given repository?
  def show_marketplace_ci_cta?(repository)
    with_database_error_fallback(fallback: false) do
      return false unless repository && !repository.advisory_workspace?
      return false unless show_marketplace_calls_to_action?
      return false if marketplace_domain.repository_settings.has_ci?(repository)
      return false if repository.organization&.plan&.business?

      repository.adminable_by?(current_user)
    end
  end

  def marketplace_onboarding_status_icon(completed = false)
    if completed
      octicon("check", class: "color-fg-success")
    else
      octicon("dot-fill", class: "hx_dot-fill-pending-icon")
    end
  end

  def is_enterprise_managed?(target_actor)
    (target_actor.user? && target_actor.is_enterprise_managed?) || (target_actor.organization? && target_actor.enterprise_managed_user_enabled?)
  end

  def marketplace_search_type(search_type)
    case search_type
    when "MARKETPLACE_ACTIONS"
      "Actions"
    when "MARKETPLACE"
      "Apps"
    when "MARKETPLACE_COPILOT"
      "Copilot Apps"
    when "MARKETPLACE_STACKS"
      "Stacks"
    end
  end

  def is_publisher_from_restricted_region(listing_slug)
    Marketplace::Listing::RESTRICTED_REGIONS.include?(Marketplace::Listing.find_by(slug: listing_slug).owner&.profile_location)
  end

  def is_actor_from_restricted_region(actor_login)
    (%w[BY RU].include?(GitHub::Location.look_up(request.try(:remote_ip))[:country_code]) || Marketplace::Listing::RESTRICTED_REGIONS.include?(User.find_by_login(actor_login)&.profile_location))
  end

  def marketplace_listing_state_color(listing)
    if listing.draft?
      "blue"
    elsif listing.archived? || listing.rejected?
      "red"
    elsif listing.verified?
      "green"
    elsif listing.unverified?
      "yellow"
    else
      # The rest of the states are different types of approval requested
      "purple"
    end
  end

  def marketplace_listing_state_octicon(listing)
    if listing.draft?
      "pencil"
    elsif listing.archived? || listing.rejected?
      "circle-slash"
    elsif listing.verified? || listing.unverified?
      "check"
    else
      # The rest of the states are different types of approval requested
      "eye"
    end
  end

  def searching?
    params[:query].present? ||
      params[:category].present? ||
      params[:type].present? ||
      params[:copilot_app].present?
  end
end
