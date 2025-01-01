# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Does the same as parent class except
  # replacing task list item markers (`[ ]` and `[x]`) with checkboxes.
  # This filter is used if we need to render progress bar in the
  # issue/PR timeline. In this case we need only to count task list items
  # but we don't need to render checkboxes,
  # so we eliminated this step to avoid additional overhead.
  #
  # Results
  # -------
  #
  # The following keys are written to the result hash:
  #   :task_list_items - An array of TaskList::Item objects.
  class LightweightTaskListFilter < TaskListFilter

    def call(node)
      unless is_element_node?(node)
        call_text(node)
      end
    end

    protected

    def call_text(text)
      text.html.sub!(TaskList::Filter::ItemPatternParser) do |_match|
        item = TaskList::Item.new($1)
        @filter.task_list_items << item
      end
    end
  end
end
