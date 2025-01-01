# typed: true
# frozen_string_literal: true

module Profiles
  class SshKeysController < ApplicationController
    set_statsd_sample_rate 0.01, only: :show

    include UserContributionsHelper

    before_action :ensure_user_visible

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
  end
end
