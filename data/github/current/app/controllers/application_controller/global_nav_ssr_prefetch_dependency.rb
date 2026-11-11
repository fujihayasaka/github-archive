# typed: true
# frozen_string_literal: true

# Fires an async SSR request for the global nav React partial early in the
# request lifecycle, storing the in-flight renderer in the ReactPartialStore,
# which later gets picked up by render_react_partial in the HeaderComponent.

module ApplicationController::GlobalNavSsrPrefetchDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { ApplicationController }

  private

  # Override in subclasses to provide the selected link for the global nav SSR
  # prefetch. This runs early in the filter chain (before most before_actions),
  # so we use a method override rather than reading @selected_link which may not
  # be set yet.
  sig { returns(T.nilable(Symbol)) }
  def global_nav_selected_link
    nil
  end

  sig { returns(T::Boolean) }
  def should_prefetch_global_nav_ssr?
    return false unless logged_in?

    return false unless FeatureFlag.vexi.enabled?(:prefetch_global_nav_ssr, current_user, default: false)
    return false unless FeatureFlag.vexi.enabled?(:global_nav_react, current_user, default: false)

    return false unless request.get?
    return false unless request.format.html?
    return false if request.xhr?

    # Skip fragment requests that don't render the full application layout
    return false if pjax?
    return false if turbo_frame_request?

    true
  end

  sig { void }
  def prefetch_global_nav_ssr
    org = respond_to?(:current_organization) ? T.unsafe(self).current_organization : nil

    header_view = Site::HeaderView.new(
      current_user: current_user,
      current_repository: current_repository,
      current_organization: org,
      is_mobile_request: GitHub::Mobile.mobile_user_agent?(request.user_agent.to_s),
      current_copilot_user: current_copilot_user_v2,
      params: params,
      response: response,
    )

    nav_payload = GlobalNavigation::GlobalNavigationPayload.new(
      current_user: current_user,
      current_copilot_user: current_copilot_user_v2,
      current_repository: current_repository,
      current_organization: org,
      selected_link: global_nav_selected_link,
      is_search_page: is_a?(CodesearchController),
      view: header_view,
      source: "rails"
    )

    tracking_tags = T.let(["source:rails"], T::Array[String])
    tracking_tags << "context_region_type:#{nav_breadcrumb&.crumb_type}" if nav_breadcrumb

    props = GitHub.dogstats.time("global_navigation.react_props", tags: tracking_tags) do
      nav_payload.payload(
        return_to: return_to_path,
        context_crumb: nav_breadcrumb,
        path_resolver: -> (path_method, args) { T.unsafe(self).send(path_method, *args) }, # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
        params: params,
        display_switch_account_popover: false
      )
    end

    props[:contextRegion][:currentPath] = canonical_request.path

    controller = T.cast(self, ApplicationController)
    renderer = React::PartialRenderer.new(
      controller: controller,
      name: "global-nav-bar",
      origin: nil,
      props: props,
      request: request,
      ssr_hints: Alloy::SelectiveSsr::Hints.new,
      disable_ssr: false,
      force_ssr: false,
      user: current_user,
    ).start_async

    prerender_react_partial(name: "global-nav-bar", renderer: renderer)
  end
end
