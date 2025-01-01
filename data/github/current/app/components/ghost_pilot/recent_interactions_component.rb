# typed: true
# frozen_string_literal: true

module GhostPilot
  class RecentInteractionsComponent < BaseContextComponent
    erb_template <<-ERB
      <% if lazy_load %>
        <%= render GhostPilot::AsyncContextFragmentComponent.new(src: src) %>
      <% else %>
        <span hidden
          id="<%= element_id %>"
          data-allow-truncation
          data-description="User Recent Interactions"
          data-value="<%= format_array_into_markdown_list(recent_interaction_titles) %>"></span>
      <% end %>
    ERB

    attr_reader :organization_id, :recent_interactions, :lazy_load

    def initialize(organization_id: nil, recent_interactions: nil, lazy_load: false)
      @organization_id = organization_id
      @recent_interactions = recent_interactions
      @lazy_load = lazy_load


      if !lazy_load && @recent_interactions.nil?
        raise ArgumentError, "recent_interactions is required"
      end
    end

    def element_id
      "user-recent-interactions"
    end

    def src
      ghost_pilot_recent_interactions_path({ organization_id: organization_id })
    end

    def recent_interaction_titles
      recent_interactions.map(&:interactable).map(&:title)
    end
  end
end
