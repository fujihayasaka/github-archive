# typed: strict
# frozen_string_literal: true

module Issues
  module IIssueFieldSingleSelect
    extend T::Helpers
    include IIssueField

    sig { abstract.returns(T::Array[Issues::IIssueFieldOption]) }
    def options; end

    abstract!
  end
end
