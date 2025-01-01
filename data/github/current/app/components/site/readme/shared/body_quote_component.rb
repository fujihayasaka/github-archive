# typed: true
# frozen_string_literal: true

class Site::Readme::Shared::BodyQuoteComponent < ApplicationComponent
  include ViewComponent::InlineTemplate

  erb_template <<~'ERB'
    <aside>
      <p><%= @quote %></p>
    </aside>
  ERB

  def initialize(quote:)
    @quote = quote
  end

  def render?
    @quote.present?
  end
end
