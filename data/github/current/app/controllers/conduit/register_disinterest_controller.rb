# typed: true
# frozen_string_literal: true

module Conduit
  class RegisterDisinterestController < ApplicationController
    before_action :login_required
    before_action :require_xhr, only: [:create, :destroy]
    before_action :validate_create_params, only: [:create]
    before_action :validate_destroy_params, only: [:destroy]

    def create
      ::Conduit::UserDisinterest::REASONS.each do |reason|
        if params["reason_#{reason.to_s.downcase}"].present?
          GlobalInstrumenter.instrument("feeds.user_disinterest", payload_for(params, reason))
        end
      end

      # cached feed is no longer valid, deleting...
      invalidate_cache

      head :ok
    end

    def destroy
      GlobalInstrumenter.instrument("feeds.user_disinterest", payload_for(params))

      head :ok
    end

    private

    def payload_for(params, reason = nil)
      {
        actor_id: current_user.id,
        resource_id: params[:resource_id].to_i,
        resource_type: params[:resource_type],
        event_id: params[:event_id].to_i,
        dismissed_at: Time.now.utc,
        dismissed_reason: reason,
        card_type: params[:card_type],
        undo: params[:undo] == "true",
        identifier: params[:identifier]
      }
    end

    def validate_create_params
      return if valid_shared_params? && valid_create_params?

      head 404
    end

    def validate_destroy_params
      return if valid_shared_params? && valid_destroy_params?

      head 404
    end

    def valid_shared_params?
      params[:event_id].to_i.to_s == params[:event_id] &&
      params[:resource_id].to_i.to_s == params[:resource_id]
    end

    def valid_create_params?
      params[:undo] == "false"
    end

    def valid_destroy_params?
      params[:reason] == "reason_unknown" &&
      params[:undo] == "true"
    end

    def invalidate_cache
      Conduit::KVBackedCache.invalidate_for(current_user)
    end

    def target_for_conditional_access
      return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      current_user
    end
  end
end
