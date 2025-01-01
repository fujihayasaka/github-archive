# typed: true
# frozen_string_literal: true

module Voltron
  module FragmentController
    extend T::Helpers
    requires_ancestor { ApplicationController }
    extend ActiveSupport::Concern

    included do
      T.bind(self, T.class_of(ApplicationController))
      prepend_before_action :set_varnish_iris_sidecar_nonce
      before_action :boomtown_check
      before_action :validate_hmac
      before_action :add_voltron_original_url_to_context
    end

    class_methods do
      # If some before actions only need to happen before the root fragment,
      # call this in your controller to skip the specified before_actions unless
      # the current controller action matches the one specified by `to:`.
      #
      # Out of caution, only skip before actions if the request is coming from voltron
      # (as opposed to staff requesting a fragment directly via the browser)
      #
      # before_action_names - A list of symbols representing the before_actions to conditionally skip
      # to - The name of the controller action that _shouldn't_ skip the before_actions
      def isolate_before_actions(*before_action_names, to:)
        T.bind(self, T.class_of(ApplicationController))

        before_action_names.each do |before_action_name|
          skip_before_action before_action_name, if: -> do
            T.bind(self, ApplicationController)
            action_name != to.to_s && request_coming_from_voltron?
          end
        end
      end
    end

    # Generally, we don't want to render a layout around a fragment.
    # In order to inspect the fragment's performance, staff can
    # directly request a fragment from the browser,
    # with full access to the staffbar performance tools.
    # If we're rendering a flamegraph, don't include the layout.
    def fragment_layout
      return false if request_coming_from_voltron?
      return false unless can_request_fragment_from_browser?
      return false if params[:flamegraph] == "1"

      "layouts/fragment_dev_mode"
    end

    # After the user logs in, return to the path that the browser requested,
    # not to the fragment path that voltron requested.
    def return_to_path
      canonical_request.url
    end

    def validate_hmac
      # allow staff to bypass the hmac checks
      return if can_request_fragment_from_browser?

      timestamp = request.headers["HTTP_X_AUTHORIZATION_TIME"]
      authorization = request.headers["Authorization"]

      return head 403 if timestamp.nil? || timestamp.empty?
      return head 403 if authorization.nil? || authorization.empty?

      time = DateTime.strptime(timestamp, "%s")
      return head 403 if time < 30.seconds.ago

      key = "#{request.fullpath},#{timestamp}"

      is_valid = ActiveSupport::SecurityUtils::secure_compare(
        OpenSSL::HMAC.hexdigest("SHA256", GitHub.voltron_secret, key),
        authorization,
      )

      return head 403 if !is_valid
    end

    private

    def can_request_fragment_from_browser?
      request.headers["Authorization"].nil? && (staffbar_allowed? || Rails.env.development?)
    end

    def set_varnish_iris_sidecar_nonce
      return @varnish_iris_sidecar_nonce if defined?(@varnish_iris_sidecar_nonce)
      @varnish_iris_sidecar_nonce = request.headers["X-Voltron-Varnish-Iris-Nonce"]
      response.headers["X-Iris-Sidecar-ESI-Nonce"] = @varnish_iris_sidecar_nonce if @varnish_iris_sidecar_nonce.present?

      if @varnish_iris_sidecar_nonce.blank? && varnished?
        head 403
      end
    end

    def varnished?
      # TODO move varnished? out of app/helpers/varnish_helper.rb and into a controller?
      GitHub.varnish_enabled? && request.headers["X-GitHub-Dynamic-Cache"] == "web"
    end

    def boomtown_check
      fail if params[:boomtown] == "1" && (employee? || site_admin?)
    end

    def add_voltron_original_url_to_context
      GitHub.context.push(url: canonical_request.url)
    end
  end
end
