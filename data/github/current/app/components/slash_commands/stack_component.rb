# typed: true
# frozen_string_literal: true

# Combine content into a single renderable object
class SlashCommands::StackComponent < ApplicationComponent
  attr_reader :stack_items
  def initialize(*stack_items)
    @stack_items = stack_items.flatten
  end

  def call
    rendered_stack_items = stack_items.map do |stack_item|
      if renderable?(stack_item)
        render(stack_item)
      else
        stack_item
      end
    end

    safe_join(rendered_stack_items)
  end

  private

  def renderable?(stack_item)
    stack_item.respond_to?(:render_in)
  end
end
