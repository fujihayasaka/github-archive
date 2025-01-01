# typed: true
# frozen_string_literal: true

module Repositories
  class ArchivedNoticeComponent < ApplicationComponent
    include TradeControlsHelper

    attr_reader :repository

    def initialize(repository:)
      @repository = repository
    end

    def show_trade_notice?
      !trade_notice_dismissed? && is_member?
    end

    def trade_controls_read_only?
      @repository.trade_controls_read_only?
    end

    def organization_sdn_restricted?
      if GitHub.flipper[:archived_notice_component_kv_fallback].enabled?(@repository)
        with_database_error_fallback(fallback: false) do
          @repository.owner.organization? && @repository.owner.has_commercial_interaction_restriction?
        end
      else
        @repository.owner.organization? && @repository.owner.has_commercial_interaction_restriction?
      end
    end

    def can_admin?
      @repository.owner.adminable_by?(current_user)
    end

    private

    def is_member?
      @repository.member?(current_user) || @repository.owner.organization? && @repository.owner.member?(current_user)
    end

    def trade_notice_dismissed?
      current_user&.dismissed_notice?(Billing::OFACCompliance::TRADE_CONTROLS_READ_ONLY)
    end
  end
end
