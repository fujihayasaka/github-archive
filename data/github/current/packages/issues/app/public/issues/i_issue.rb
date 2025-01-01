# typed: strict
# frozen_string_literal: true

module Issues
  module IIssue
    extend T::Helpers

    include Kernel

    abstract!

    sig { abstract.returns(T.nilable(Integer)) }
    def id; end
  end
end
