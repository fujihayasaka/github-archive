# typed: true
# frozen_string_literal: true

# Use this to create a preheader in the contents of your HTML email.
# This needs to be placed at the top of the content_for :header.
#
# An email preheader is the text that appears after the subject line in
# an email inbox. This component provides the ability to add one without
# the contents needing to be visible in the email.
#
# <% content_for :header do %>
#   <%= render(Mail::PreheaderComponent.new(contents: "Hello!")) %>
#   Welcome, <%= @business.name %>, to GitHub
# <% end %>

class Mail::PreheaderComponent < ApplicationComponent
  attr_reader :text

  def initialize(text:)
    @text = text
  end
end
