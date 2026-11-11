# typed: true
# frozen_string_literal: true

module Releases
  class VerifiedIconComponent < ApplicationComponent
    def initialize(item)
      @item = item

      if item
        @item_type = item.class.name.downcase
        @verification_status = item.verification_status
      end
    end

    def render?
      item && @verification_status.present? && (@verification_status == :verified || @verification_status == :partially_verified)
    end

    def before_render
      if item
        @signature = Commits::SignedCommitBadge.for(item, current_user: current_user)
      end
    end

    attr_reader :item, :item_type, :signature
  end
end
