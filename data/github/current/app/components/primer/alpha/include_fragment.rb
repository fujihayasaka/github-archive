# typed: true
# frozen_string_literal: true

module Primer
  module Alpha
    # Override Primer's component to add the blankslate error message on all include-fragment elements.
    # Once this is tested and ready, we can move it to the main Primer::IncludeFragment and remove this override.
    class IncludeFragment < Primer::Component # rubocop:disable ViewComponent/ComponentsHaveUnitTests, ViewComponent/EncouragePreviewsForPrimer
      status :alpha

      ALLOWED_LOADING_VALUES = [:lazy, :eager].freeze
      DEFAULT_LOADING = :eager

      erb_template <<~ERB
        <%= render Primer::BaseComponent.new(**@system_arguments) do %>
          <%= content %>
          <div data-show-on-forbidden-error hidden>
            <%= render Primer::Beta::Blankslate.new(border: true, bg: :default, spacious: true, border_radius: 2) do |c| %>
              <% c.with_heading(tag: :h3) do %>
                Uh oh!
              <% end %>
              <% c.with_description do %>
                <p class="color-fg-muted my-2 mb-2 ws-normal">There was an error while loading. <a class="Link--inTextBlock" data-turbo="false" href="" aria-label="Please reload this page">Please reload this page</a>.</p>
              <% end %>
            <% end %>
          </div>
        <% end %>
      ERB

      # @param src [String] The URL  from which to retrieve an HTML element fragment.
      # @param loading [Symbol] <%= one_of([:lazy, :eager]) %>
      # @param accept [String] What to send as the Accept header.
      # @param system_arguments [Hash] <%= link_to_system_arguments_docs %>
      def initialize(src: nil, loading: nil, accept: nil, **system_arguments)
        @system_arguments = system_arguments
        @system_arguments[:tag] = "include-fragment"
        @system_arguments[:loading] = loading
        @system_arguments[:src] = src
        @system_arguments[:accept] = accept if accept

        if loading
          @system_arguments[:loading] = fetch_or_fallback(ALLOWED_LOADING_VALUES, loading.to_sym, DEFAULT_LOADING)
        end

        if Primer::CurrentAttributes.nonce
          @system_arguments[:"data-nonce"] = Primer::CurrentAttributes.nonce
        end
      end
    end
  end
end
