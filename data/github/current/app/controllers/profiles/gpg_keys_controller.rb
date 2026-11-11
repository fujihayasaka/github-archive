# typed: true
# frozen_string_literal: true

module Profiles
  class GpgKeysController < ApplicationController
    set_statsd_sample_rate 0.01, only: :show

    include UserContributionsHelper

    before_action :ensure_user_visible

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Collab,
      ApplicationRecord::IamAbilities,
      only: [:show]

    def show
      respond_to do |format|
        format.gpg  { render plain: this_user.gpg_keys.primary_keys.keychain }
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
