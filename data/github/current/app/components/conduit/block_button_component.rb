# typed: true
# frozen_string_literal: true

module Conduit
  class BlockButtonComponent < ApplicationComponent
    attr_accessor :actor, :org_report_path

    def initialize(actor: nil, org_report_path: nil)
      @actor = actor
      @org_report_path = org_report_path
    end

    def render?
      actor.present?
    end

    def actor_is_org?
      actor.is_a?(Organization)
    end

    memoize def actor_is_sponsored_by_viewer?
      actor.sponsored_by_viewer?(current_user)
    end

    memoize def viewer_is_sponsored_by_actor?
      actor.sponsoring_viewer?(current_user)
    end
  end
end
