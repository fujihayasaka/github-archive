# typed: true
# frozen_string_literal: true

# This component is inspired by Primer::Beta::Details.
# We couldn't use that component because the <summary> in <details> is supposed to be the main clickable region
# but we needed other parts of the <summary> to also be clickable.
class Suggestions::CollapsibleComponent < ApplicationComponent
  renders_one :summary, lambda { |**system_arguments|
    system_arguments[:tag] = :div
    SummaryComponent.new(open: @open, **system_arguments)
  }

  renders_one :body, lambda { |**system_arguments|
    system_arguments[:tag] = :div
    BodyComponent.new(open: @open, **system_arguments)
  }

  def initialize(open: false, **system_arguments)
    @open = open
    @system_arguments = system_arguments

    @system_arguments[:tag] = :"suggestions-collapsible"
    @system_arguments[:data] ||= {}
    @system_arguments[:data][:open] = true if @open
  end

  class SummaryComponent < ApplicationComponent
    erb_template <<~ERB
      <%= content_tag(@system_arguments[:tag], class: @system_arguments[:classes]) do %>
        <div class="flex-shrink-0">
          <button
            type="button"
            class="btn-octicon"
            aria-label="Toggle diff contents"
            aria-expanded="true"
            data-target="suggestions-collapsible.collapseButton"
            data-action="click:suggestions-collapsible#toggle"
            style="width:22px;<% unless @open %>display:none;<% end %>"
          >
            <%= primer_octicon(:"chevron-down") %>
          </button>

          <button
            type="button"
            class="btn-octicon"
              aria-label="Toggle diff contents"
              aria-expanded="true"
              data-target="suggestions-collapsible.openButton"
              data-action="click:suggestions-collapsible#toggle"
              style="width:22px;<% if @open %>display:none;<% end %>"
            >
            <%= primer_octicon(:"chevron-right") %>
          </button>
        </div>

        <%= content %>
      <% end %>
    ERB

    def initialize(open: false, **system_arguments)
      @open = open

      @system_arguments = system_arguments
      @system_arguments[:tag] ||= :div
      @system_arguments[:classes] = class_names(
        @system_arguments[:classes],
        "d-flex",
      )
    end
  end

  class BodyComponent < ApplicationComponent
    def initialize(open: false, **system_arguments)
      @open = open
      @system_arguments = system_arguments
      @system_arguments[:tag] ||= :div
    end

    def call
      style = "display:none" unless @open
      data = { target: "suggestions-collapsible.body" }
      content_tag(@system_arguments[:tag], class: @system_arguments[:classes], data:, style:) { content }
    end
  end
end
