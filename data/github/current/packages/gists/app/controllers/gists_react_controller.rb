# typed: true
# frozen_string_literal: true

# Renders `/gists` as the `gist-react` React data-router app, gated by the
# `gist_react` feature flag. Logged-out viewers and users without the flag are
# redirected to the gist.github.com subdomain before `index` runs.
#
# MVP: only the `/gists` listing is wired up. The React app owns client-side
# routing beneath `/gists`; further entry points will be added with their
# payloads as the feature is built out.
class GistsReactController < ApplicationController
  before_action :redirect_unless_gist_react_enabled

  global_navigation_title "Gists", path: "/gists"

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Mysql1,
    only: [:index]

  def index
    @hide_footer = true
    render_react_app(
      app_name: "gist-react",
      title: "Gists",
      data_router_enabled: true,
      custom_tags: ["is_react:true", "is_data_router:true"],
      payload: { yourGistsRoute: {} },
    )
  end

  private

  def redirect_unless_gist_react_enabled
    return if current_user&.feature_flag_enabled?(:gist_react, default: false)

    redirect_to(GitHub.gist_url)
  end

  # `/gists` lists the viewer's own gists; `User#target_for_conditional_access`
  # returns `self`, so no target override is needed. The bypass symbol is only
  # reachable if `redirect_unless_gist_react_enabled` hasn't already kicked
  # logged-out viewers out.
  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    current_user
  end
end
