# typed: strict
# frozen_string_literal: true

module Issues
  module ILabel
    extend T::Helpers

    include Kernel

    abstract!

    sig { abstract.returns(T.nilable(Integer)) }
    def id; end

    sig { abstract.returns(String) }
    def name; end

    sig { abstract.returns(T.nilable(String)) }
    def lowercase_name; end
  end
end
