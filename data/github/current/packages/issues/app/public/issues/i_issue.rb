# typed: strict
# frozen_string_literal: true

module Issues
  module IIssue
    extend T::Helpers

    include Kernel

    abstract!

    sig { abstract.returns(T.nilable(Integer)) }
    def id; end

    sig { abstract.returns(String) }
    def title; end

    sig { abstract.returns(T.nilable(String)) }
    def body; end
  end
end
