# typed: true
# frozen_string_literal: true

module SearchPriorityHelper
  extend ActiveSupport::Concern

  included do
    T.bind(self, T.any(T.class_of(SearchShortcut), T.class_of(TeamSearchShortcut)))

    scope :by_priority, -> { order(priority: :desc) }
    prioritizable_by subject: :itself, context: :dashboard
  end
end
