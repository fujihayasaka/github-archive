# typed: strict
# frozen_string_literal: true

module Issues
  module IIssueField
    extend T::Helpers

    include Kernel

    abstract!

    sig { abstract.returns(T.nilable(Integer)) }
    def id; end

    sig { abstract.returns(T.nilable(Integer)) }
    def owner_id; end

    sig { abstract.returns(String) }
    def name; end

    sig { abstract.returns(T.nilable(String)) }
    def description; end

    sig { abstract.returns(User) }
    def owner; end

    sig { abstract.returns(Symbol) }
    def data_type; end
  end
end
