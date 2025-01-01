# typed: strict
# frozen_string_literal: true

module React
  class FeatureTracking
    sig { returns(T.nilable(T.proc.returns(T.untyped))) }
    attr_accessor :react_behavior

    sig { returns(T.nilable(T.proc.returns(T.untyped))) }
    attr_accessor :rails_behavior

    sig { void }
    def initialize
      @react_behavior = T.let(nil, T.nilable(T.proc.returns(T.untyped)))
      @rails_behavior = T.let(nil, T.nilable(T.proc.returns(T.untyped)))
    end

    sig { params(block: T.proc.returns(T.untyped)).void }
    def react(&block)
      @react_behavior = block
    end

    sig { params(block: T.proc.returns(T.untyped)).void }
    def rails(&block)
      @rails_behavior = block
    end
  end
end
