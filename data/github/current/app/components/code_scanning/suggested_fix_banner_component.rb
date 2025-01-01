# typed: true
# frozen_string_literal: true

class CodeScanning::SuggestedFixBannerComponent < ApplicationComponent
  STATES = %w(default loading attention).freeze
  DEFAULT_STATE = "default"

  renders_one :action, types: {
    generate_fix_button: lambda { |form_url:, **kwargs|
      GenerateFixButtonComponent.new(**T.unsafe({ form_url: form_url, disabled: @disabled }.merge(kwargs)))
    },
    content: lambda { |**system_arguments|
      system_arguments[:tag] = :div
      Primer::BaseComponent.new(**system_arguments)
    }
  }

  def initialize(state: DEFAULT_STATE, disabled: false, **system_arguments)
    @state = fetch_or_fallback(STATES, state.to_s, DEFAULT_STATE)
    @system_arguments = system_arguments
    @disabled = disabled
  end

  private

  attr_reader :state

  def attention?
    state == "attention"
  end

  def loading?
    state == "loading"
  end

  class GenerateFixButtonComponent < ApplicationComponent
    erb_template <<~ERB
      <%= form_tag(@form_url, class: "m-0") do %>
        <%= render Primer::Beta::Button.new(type: :submit, disabled: @disabled) do |button| %>
          <% button.with_leading_visual_icon(icon: :"shield-check", color: :muted) %>
          <%= content? ? content : "Generate fix"  %>
        <% end %>
      <% end %>
    ERB

    def initialize(form_url:, disabled: false)
      @form_url = form_url
      @disabled = disabled
    end
  end
end
