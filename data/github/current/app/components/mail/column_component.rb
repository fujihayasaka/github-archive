# typed: true
# frozen_string_literal: true

# Use this to create a column of content in HTML emails.
# Used in conjuction with the Mail::RowComponent.
#
# <%= render(Mail::RowComponent.new) do %>
#   <%= render(Mail::ColumnComponent.new) do %>
#     <p>Your email content here</p>
#   <% end %>
#   <%= render(Mail::ColumnComponent.new) do %>
#     <p>Another column here</p>
#   <% end %>
# <% end %>
#
# Based off of Inky's implementation: https://get.foundation/emails/docs/grid.html#columns
class Mail::ColumnComponent < ApplicationComponent
  attr_reader :classes, :align

  def initialize(classes: nil, align: nil)
    @classes = class_names("text-left", classes)
    @align = align
  end
end
