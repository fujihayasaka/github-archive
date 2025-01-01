# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::Overview::StatusLabelComponent < ApplicationComponent
  include ViewComponent::InlineTemplate

  erb_template <<~'ERB'
    <%= render Primer::Beta::Label.new(**@kwargs) do %>
      <%= title %>
    <% end %>
  ERB

  sig { returns T::Array[Symbol] }
  def self.valid_states
    SponsorsListing.workflow_spec.state_names
  end

  sig { params(state: T.any(String, Symbol), kwargs: T.untyped).void }
  def initialize(state:, **kwargs)
    valid_states = self.class.valid_states
    @state = T.let(fetch_or_fallback(valid_states, state, valid_states.first), Symbol)
    @kwargs = kwargs.merge(scheme: scheme, title: "Label: #{title}", test_selector: "status-label")
  end

  private

  sig { returns Symbol }
  def scheme
    case @state
    when :approved
      :success
    when :disabled
      :danger
    else
      :warning
    end
  end

  sig { returns String }
  memoize def title
    case @state
    when :approved
      "Active"
    when :disabled
      "Disabled"
    else
      "Pending"
    end
  end
end
