# typed: true
# frozen_string_literal: true

# Use this to create a centered button in your email. Useful as the primary call-to-action.
#
# <%= render(Mail::ContainerComponent.new) do %>
#   <%= render(Mail::ButtonComponent.new(text: "Click me", url: "github.com", classes: "btn-primary btn-large")) %>
# <% end %>
class Mail::ButtonComponent < ApplicationComponent
  attr_reader :classes, :text, :url, :outlook_safe

  def initialize(text:, url:, classes: nil, outlook_safe: false)
    @classes = class_names("btn", classes)
    @text = text
    @url = url
    @outlook_safe = outlook_safe
  end

  def primary_button?
    classes.include?("btn-primary")
  end
end
