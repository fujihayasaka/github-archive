# typed: true
# frozen_string_literal: true

module Issues
  class TrackedIssuesProgressComponent < ApplicationComponent

    MODES = [:title, :title_small, :inline, :tasklist_item].freeze

    def initialize(mode:, total:, completed:, color: nil, is_tasklist: false)
      @mode, @total, @completed, @color, @is_tasklist = mode, total, completed, color, is_tasklist
    end

    private

    def render?
      MODES.include?(@mode) &&
      @total.is_a?(Integer) &&
      @completed.is_a?(Integer) &&
      @total > 0 && @completed >= 0 && @completed <= @total
    end

    def border_color
      @is_tasklist ? "var(--borderColor-default, var(--color-border-default))" : "var(--borderColor-accent-muted, var(--color-accent-subtle))"
    end

    def type
      # :title and :title_small should be the only components updating progress
      # Needed is task_list.ts#updateProgress
      if @is_tasklist
        @mode == :tasklist_item ? :tasklist_item : :tasklist_block
      else
        (@mode == :title || @mode == :title_small) ? :checklist : :other
      end
    end

    def label
      #  This property should be coordinated with it's corespondent from tracked-issue-progress.ts#update
      if @mode == :tasklist_item
        "#{@completed} of #{@total}"
      else
        if @completed > 0
          if @completed == @total
            "#{pluralize(@total, "task")} done"
          else
            "#{@completed} of #{pluralize(@total, "task")}"
          end
        else
          pluralize(@total, "task")
        end
      end
    end

    def percentage
      value = @completed.fdiv(@total) * 100
      number_with_precision(value, precision: 0, strip_insignificant_zeros: true)
    end

    def render_progress?
      @completed > 0
    end
  end
end
