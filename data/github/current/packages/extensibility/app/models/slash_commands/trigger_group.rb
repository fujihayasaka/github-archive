# typed: true
# frozen_string_literal: true

module SlashCommands
  class TriggerGroup
    # A TriggerGroup is a group of slash command triggers that
    #   are grouped by their `category` attribute. Individual commands
    #   can set their category using the `category :group_id` method.

    # If you would like to customize the user-facing group name,
    #  (rather than using a humanized version of the group ID)
    #  create an entry in the CATEGORY_LABELS hash below.

    # Note: The order of the groups in this hash will determine
    #   the order in which they are presented to the user.

    GROUP_LABELS = {
      markdown: "Markdown",
      custom: "Custom",
      actions: "GitHub Actions",
      default: "Other"
    }

    attr_reader :id, :triggers

    def initialize(id:, triggers: [])
      @id = id
      @triggers = triggers.sort_by(&:title)
    end

    def label
      GROUP_LABELS[id] || id.to_s.humanize
    end

    def sort_importance
      GROUP_LABELS.find_index { |k, _| k == id } || GROUP_LABELS.length
    end
  end
end
