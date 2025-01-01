# typed: true
# frozen_string_literal: true

# A stateless controller to serve Web Worker bootstrap scripts.
#
# https://developer.mozilla.org/en-US/docs/Web/API/Worker/Worker
# https://developer.mozilla.org/en-US/docs/Web/API/SharedWorker
# https://developer.mozilla.org/en-US/docs/Web/Security/Same-origin_policy
#
# Web Workers' script must be served from the first-party origin,
# obeying the browser's same-origin policy. So serve a script from the
# github.com origin that imports the worker file from our CDN's origin.
class WebWorkerController < ApplicationController
  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:serve_worker_from_origin]

  def serve_worker_from_origin # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.js do
        name = helpers.escape_javascript(CGI.escape(params[:path]))
        url = asset_bundle.bundle_url("#{name}.js", expand: false)
        headers["Service-Worker-Allowed"] = "/"

        http_cache_forever(public: true) do
          # if the client requests a module worker, use import instead of importScripts
          use_module_import = params[:module] == "true"
          script = use_module_import ? "import '%s'" % url : "importScripts('%s')" % url
          render js: script
        end
      end
    end
  end

  private

  memoize def asset_bundle
    AssetBundles.new
  end

  def stateless_request?
    true
  end

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

  def tenant_verification_enforceable
    :no
  end
end
