# typed: true
# frozen_string_literal: true

# Use this to separate parts of the main body of an email by horizontal lines.
# Use this in conjunction with a main layout with an outer border but without padding.
# When using this component, it's recommended to put all content of the email (except
# for the header and footer) inside a series of these components.
# The row adds padding by default but you can instruct it not to.
# The last row should not add a bottom border, as it will interfere with the outer border.
#
# <%= render(Mail::BorderedRowComponent.new) do %>
#   <p>Awesome content followed by a separator line extending to the outside border of the email</p>
# <% end %>
# <%= render(Mail::BorderedRowComponent.new(last: true)) do %>
#   <p>The last content of this email</p>
# <% end %>
#
class Mail::BorderedRowComponent < ApplicationComponent
  attr_reader :last, :skip_padding, :classes

  def initialize(classes: nil, last: false, skip_padding: false)
    @classes = classes
    @last = last
    @skip_padding = skip_padding
  end
end
