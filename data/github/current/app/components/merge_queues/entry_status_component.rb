# typed: true
# frozen_string_literal: true

class MergeQueues::EntryStatusComponent < ApplicationComponent
  # entry - a MergeQueueEntry
  # queue - the MergeQueue that the entry belongs to
  # repository - the Repository containing the merge queue
  # classes - optional String of CSS classes to apply to the containing element
  # style - optional String of CSS styles to apply to the containing element
  # status_icon_size - optional Integer of the height and width of the status icon
  def initialize(entry:, queue:, repository:, classes: nil, data_action: nil, data_target: nil,
                 style: nil, status_icon_size: 16)
    @entry = entry
    @queue = queue
    @repository = repository
    @classes = classes
    @data_action = data_action
    @data_target = data_target
    @style = style
    @status_icon_size = status_icon_size
  end

  private

  attr_reader :repository, :classes, :data_action, :data_target, :style, :status_icon_size, :entry

  memoize def queue
    GitHub::PrefillAssociations.prefill_associations(@queue, [
      :protected_branch,
      :repository,
    ], available_records: [@repository])
    @queue
  end

  def render?
    @entry && @queue && @repository
  end

  def status_icon_color
    entry.entry_state.primer_color
  end

  def status_icon
    entry.entry_state.octicon_name
  end

  memoize def status_icon_aria_label
    entry.entry_state.description
  end

  memoize def show_check_status?
    entry.entry_state == MergeQueues::Entry::State::AwaitingChecks
  end
end
