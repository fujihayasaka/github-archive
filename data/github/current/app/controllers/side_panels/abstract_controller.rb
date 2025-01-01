# typed: true
# frozen_string_literal: true

module SidePanels
  class AbstractController < ApplicationController
    abstract!

    before_action :login_required
    before_action :ensure_feature_enabled

    ITEMS_PER_PAGE = 5
    MAX_PAGES = 3

    private

    def max_items_count
      ITEMS_PER_PAGE * MAX_PAGES
    end

    def panel
      params[:panel].to_sym
    end

    def ensure_feature_enabled
      return render_404 unless header_redesign_enabled?
    end

    def target_for_conditional_access
      return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      current_user
    end
  end
end
