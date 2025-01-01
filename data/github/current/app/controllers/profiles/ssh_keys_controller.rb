# typed: true
# frozen_string_literal: true

module Profiles
  class SshKeysController < ApplicationController
    set_statsd_sample_rate 0.01, only: :show

    include UserContributionsHelper
    include GitHub::RateLimitedRequest

    SSHKEYS_SHOW_RATE_LIMIT_MAX = 5000

    before_action :ensure_user_visible

    rate_limit_requests \
      only: [:show],
      if: :request_is_rate_limited?,
      key: :sshkeys_rate_limit_key,
      max: SSHKEYS_SHOW_RATE_LIMIT_MAX,
      ttl: 1.minute

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Collab,
      ApplicationRecord::Configurations,
      only: [:show]

    def show
      respond_to do |format|
        format.keys { render plain: this_user.verified_keys.map { |k| "#{k}\n" }.join }
      end
    end

    private

    def target_for_conditional_access
      return :no_target_for_conditional_access unless this_user.present? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      this_user
    end

    def ensure_user_visible
      return if this_user && !this_user.hide_from_user?(current_user)
      render_404
    end

    def limit_anonymous_by_ja3_hash?
      GitHub.flipper[:limit_anon_sshkeys_show_by_ja3].enabled?
    end

    def request_is_rate_limited?
      !logged_in? && limit_anonymous_by_ja3_hash?
    end

    def sshkeys_rate_limit_key
      key_base = "#{self.class.to_s.underscore}:#{action_name}"
      actor_identifier = request.env.fetch("HTTP_X_SSL_JA3_HASH", request.remote_ip)

      "#{key_base}:#{actor_identifier}"
    end

  end
end
