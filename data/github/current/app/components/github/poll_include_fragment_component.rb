# typed: true
# frozen_string_literal: true

module GitHub
  class PollIncludeFragmentComponent < ApplicationComponent
    erb_template <<~ERB
      <%= render Primer::BaseComponent.new(**@system_arguments) do %>
        <%= content %>
        <div data-show-on-forbidden-error hidden>
          <%= render Primer::Beta::Blankslate.new(border: true, bg: :default, spacious: true, border_radius: 2) do |c| %>
            <% c.with_heading(tag: :h3) do %>
              Uh oh!
            <% end %>
            <% c.with_description do %>
              <p class="color-fg-muted my-2 mb-2 ws-normal">There was an error while loading. <a data-turbo="false" class="Link--inTextBlock" href="" aria-label="Please reload this page">Please reload this page</a>.</p>
            <% end %>
          <% end %>
        </div>
      <% end %>
    ERB

    def initialize(src: nil, **system_arguments)
      @system_arguments = system_arguments
      @system_arguments[:tag] = "poll-include-fragment"
      @system_arguments[:src] = src

      if ApplicationController::FetchNonceDependency::CurrentNonce.nonce
        @system_arguments[:"data-nonce"] = ApplicationController::FetchNonceDependency::CurrentNonce.nonce
      end
    end
  end
end
