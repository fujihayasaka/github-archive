# typed: true
# frozen_string_literal: true

module SidePanels
  class AbstractController < ApplicationController
    abstract!

    before_action :login_required
    before_action :ensure_feature_enabled

    MAX_ITEMS_PER_PAGE = 100
    ITEMS_PER_PAGE = 5
    DEFAULT_PAGES = 3
    MAX_PAGES = 20

    private

    def items_per_page
      if params[:items_per_page].to_i.positive?
        [params[:items_per_page].to_i, MAX_ITEMS_PER_PAGE].min
      else
        ITEMS_PER_PAGE
      end
    end

    def initial_items_per_page
      if params[:initial_items_per_page].to_i.positive?
        [params[:initial_items_per_page].to_i, MAX_ITEMS_PER_PAGE].min
      else
        items_per_page
      end
    end

    def max_pages
      if params[:max_pages].to_i.positive?
        [params[:max_pages].to_i, MAX_PAGES].min
      else
        DEFAULT_PAGES
      end
    end

    def max_items_count
      if FeatureFlag.vexi.enabled?(:initial_per_page_pagination_updates, default: false)
        items_per_page * (max_pages - 1) + initial_items_per_page
      else
        items_per_page * max_pages
      end
    end

    def panel
      params[:panel].to_sym
    end

    def ensure_feature_enabled
      render_404 unless header_redesign_enabled?
    end

    def target_for_conditional_access
      return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      current_user
    end
  end
end
