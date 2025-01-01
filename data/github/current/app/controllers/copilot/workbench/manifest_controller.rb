# typed: true
# frozen_string_literal: true

class Copilot::Workbench::ManifestController < ApplicationController
  before_action :login_required, except: [:show]

  def show
    expires_in 1.week, public: true
    manifest = {
       "name": "GitHub Spark",
       "short_name": "Spark",
       "display": "standalone",
       "description": "Transform ideas into full-stack intelligent apps in a snap. Publish with a click.",
       "scope": "/spark",
       "start_url": "/spark",
       "icons": [{
         "sizes": "114x114",
         "src": static_asset_path("/apple-touch-icon-114x114.png"),
       }, {
         "sizes": "120x120",
         "src": static_asset_path("/apple-touch-icon-120x120.png"),
       }, {
         "sizes": "144x144",
         "src": static_asset_path("/apple-touch-icon-144x144.png"),
       }, {
         "sizes": "152x152",
         "src": static_asset_path("/apple-touch-icon-152x152.png"),
       }, {
         "sizes": "180x180",
         "src": static_asset_path("/apple-touch-icon-180x180.png"),
       }, {
         "sizes": "57x57",
         "src": static_asset_path("/apple-touch-icon-57x57.png"),
       }, {
         "sizes": "60x60",
         "src": static_asset_path("/apple-touch-icon-60x60.png"),
       }, {
         "sizes": "72x72",
         "src": static_asset_path("/apple-touch-icon-72x72.png"),
       }, {
         "sizes": "76x76",
         "src": static_asset_path("/apple-touch-icon-76x76.png"),
       }, {
         "src": static_asset_path("/app-icon-192.png"),
         "type": "image/png",
         "sizes": "192x192"
       }, {
         "src": static_asset_path("/app-icon-512.png"),
         "type": "image/png",
         "sizes": "512x512"
       }],
     }
    render json: manifest, content_type: "application/manifest+json"
  end

  private

  # This controller returns static information about Spark as an application and
  # doesn't involve any specific resources like repos. It's also publicly available,
  # just like https://github.com/manifest.json where the pattern was copied from.
  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def ip_allowlist_enforceable
    :no
  end

  def external_conditional_access_policy_enforceable
    :no
  end

  def require_active_external_identity_session?
    false
  end

  def two_factor_enforceable
    :no
  end
end
