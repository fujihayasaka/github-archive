# typed: true
# frozen_string_literal: true

module Profiles
  module Activities
    class VisibilitiesController < ::ApplicationController
      before_action :require_user
      before_action :require_current_user_is_this_user
      before_action :require_feature_enabled
      before_action :verify_event_hmac

      def create
        resp = twirp_client.hide_event(event_id: event_id)
        success = resp.error.nil?

        GlobalInstrumenter.instrument("profile_activity_event.visibility_changed", {
          actor: current_user,
          visibility: "hidden",
          event_id: event_id,
        })

        render json: { success: success, hidden: true, form: form_component(true) }
      rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
        Failbot.report!(e)
        success = false

        render json: { success: success, hidden: false, form: form_component(false) }
      ensure
        GitHub.dogstats.increment("conduit.hide_event", tags: ["success:#{success}"])
      end

      def destroy
        resp = twirp_client.unhide_event(event_id: event_id)
        success = resp.error.nil?

        GlobalInstrumenter.instrument("profile_activity_event.visibility_changed", {
          actor: current_user,
          visibility: "visible",
          event_id: event_id,
        })

        render json: { success: success, hidden: false, form: form_component(false) }
      rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
        Failbot.report!(e)
        success = false

        render json: { success: success, hidden: true, form: form_component(true) }
      ensure
        GitHub.dogstats.increment("conduit.unhide_event", tags: ["success:#{success}"])
      end

      private

      def form_component(is_hidden)
        render_to_string(Conduit::EventVisibilityFormComponent.new(
          is_hidden: is_hidden,
          event_id: event_id,
        ), formats: [:html], layout: false)
      end

      memoize def event_id
        params[:event_id].to_i
      end

      memoize def this_user
        ::User.find_by_login(params[:user_id]) if params[:user_id] && GitHub::UTF8.valid_unicode3?(params[:user_id])
      end

      def twirp_client
        MonolithTwirp::Conduit::Feeds::V1::GetFeedAPIClient.new(faraday_client)
      end

      def faraday_client
        Faraday.new(url: GitHub.conduit_twirp_url, request: { timeout: 3 }) do |conn|
          conn.request(:retry, max: 2)
          conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: GitHub.conduit_hmac_key
          conn.use GitHub::FaradayMiddleware::RequestID
          conn.adapter Faraday.default_adapter
        end
      end

      def require_user
        render_404 unless this_user
      end

      def require_current_user_is_this_user
        head 403 unless this_user == current_user
      end

      def require_feature_enabled
        render_404 unless user_feature_enabled?(:feed_posts)
      end

      def verify_event_hmac
        head 403 unless SecurityUtils.secure_compare(params[:event_hmac], event_hmac)
      end

      def event_hmac
        Conduit.hmac_for_event_id(event_id)
      end

      def target_for_conditional_access
        return :no_target_for_conditional_access unless this_user.present? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
        this_user
      end
    end
  end
end
