# typed: true
# frozen_string_literal: true

# Use this to create a row of content in HTML emails.
# Used in conjuction with the Mail::ColumnComponent.
#
# <%= render(Mail::RowComponent.new) do %>
#   <%= render(Mail::ColumnComponent.new) do %>
#     <p>Your email content here</p>
#   <% end %>
# <% end %>
#
# Based off of Inky's implementation: https://get.foundation/emails/docs/grid.html#rows
class Mail::RowComponent < ApplicationComponent
  attr_reader :classes

  def initialize(classes: nil)
    @classes = classes
  end
end
