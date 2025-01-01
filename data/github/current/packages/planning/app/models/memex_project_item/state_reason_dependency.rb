# typed: true
# frozen_string_literal: true

module MemexProjectItem::StateReasonDependency
  extend ActiveSupport::Concern

  Values = {
    not_planned: 1,
    reopened: 2,
  }.freeze

  included do
    T.unsafe(self).enum :state_reason, Values, prefix: true
  end
end
