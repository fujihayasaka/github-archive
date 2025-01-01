# typed: strict
# frozen_string_literal: true

class MemexProject
  # This subclass allows the view_group_id field to be manually set. This is helpful in the case when you
  # want to delegate ID derivation to an external provider. The main use-case for this was to allow
  # the MemexProjectItemResponse to control group ID derivation.
  class PrecomputedGroup < Group
    include Comparable
    extend T::Sig

    sig { returns(T.nilable(String)) }
    attr_reader :view_group_id

    sig do
      params(
        column: T.nilable(MemexProjectColumn),
        title: String,
        value: T.untyped,
        view: T.nilable(MemexProjectView),
        view_group_id: T.nilable(String)
      ).void
    end
    def initialize(column: nil, title: "", value: nil, view: nil, view_group_id: nil)
      super(column:, title:, value:, view:)

      @view_group_id = T.let(view_group_id, T.nilable(String))
    end
  end
end
