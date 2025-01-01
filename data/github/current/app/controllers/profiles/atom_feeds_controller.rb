# typed: true
# frozen_string_literal: true

module Profiles
  class AtomFeedsController < ApplicationController
    include ProfilesHelper
    include UserContributionsHelper
    # Handle auth specifics for feed requests.
    include GitHub::Authentication::Feed

    before_action :ensure_profile_visible

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Collab,
      only: [:show]

    def show
      respond_to do |format|
        format.atom do
          @event_feed_user = this_user
          render "events/index", layout: false
        end
      end
    end

    private

    def target_for_conditional_access
      return :no_target_for_conditional_access unless this_user.present? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      this_user
    end

    memoize def events_timeline_key
      "actor:#{this_user.id}:public"
    end

    # Private: Actions that can response to atom requests.
    #
    # Returns an Array or Strings.
    def feed_actions
      %w(show)
    end
  end
end
