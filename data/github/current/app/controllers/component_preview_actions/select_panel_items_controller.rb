# typed: true
# frozen_string_literal: true

module ComponentPreviewActions
  class SelectPanelItemsController < ApplicationController
    SELECT_PANEL_ITEMS = [
      { value: 1, selected: true, title: "Phaser", description: "The iconic handheld laser beam" },
      { value: 2, title: "Photon torpedo", description: "Starship-mounted missile" },
      { value: 3, title: "Bat'leth", description: "The Klingon warrior's preferred means of achieving honor" },
      { value: 4, title: "Lightsaber", description: "An elegant weapon for a more civilized age", recent: true },
      { value: 5, title: "Proton pack", description: "Ghostbusting equipment" },
      { value: 6, title: "Sonic screwdriver", description: "The Time Lord's multi-purpose tool" },
      { value: 7, title: "Tricorder", description: "Handheld sensor device", recent: true },
      { value: 8, title: "TARDIS", description: "Time and relative dimension in space" }
    ]

    around_action(only: :index) do |_, action|
      ActiveRecord::Base.connected_to(role: :writing) do
        action.call
      end
    end

    def index
      # delay a bit so loading spinners, etc can be seen
      sleep 2

      if params.fetch(:fail, "false") == "true"
        uuid = params[:uuid]

        # use the uuid to succeed for the first request and fail for all subsequent requests
        if !uuid || seen_uuid?(uuid)
          render status: :internal_server_error, plain: "An error occurred"
          return
        end

        mark_seen_uuid(uuid) if uuid
      end

      show_results = params.fetch(:show_results, "true") == "true"
      query = (params[:q] || "").downcase

      results = if show_results
        SELECT_PANEL_ITEMS.select do |item|
          [item[:title], item[:description]].join(" ").downcase.include?(query)
        end
      else
        []
      end

      respond_to do |format|
        format.any(:html, :html_fragment) do
          render(
            "component_preview_actions/select_panel_items/index",
            locals: { results: results },
            layout: false,
            formats: [:html, :html_fragment]
          )
        end
      end
    end

    private

    # I have no idea how we're going to replicate the kv store in PVC
    def seen_uuid?(uuid)
      GitHub.kv.exists(key_for(uuid)).value { false }
    end

    def mark_seen_uuid(uuid)
      GitHub.kv.set(key_for(uuid), "true")
    end

    def key_for(uuid)
      "select-panel-seen-request-#{uuid}"
    end

    def target_for_conditional_access
      :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    end
  end
end
