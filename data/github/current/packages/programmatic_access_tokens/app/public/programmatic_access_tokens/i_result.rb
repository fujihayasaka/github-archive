# typed: strict
# frozen_string_literal: true

module ProgrammaticAccessTokens
  module IResult
    extend T::Helpers

    include Kernel

    abstract!

    sig { abstract.returns(T.untyped) }
    def value; end

    sig { abstract.returns(T.nilable(StandardError)) }
    def error; end

    sig { abstract.returns(T::Boolean) }
    def success?; end

    sig { abstract.returns(T::Boolean) }
    def failed?; end
  end
end
