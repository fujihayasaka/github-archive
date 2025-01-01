# typed: strict
# frozen_string_literal: true

module Issues
  module IIssueFieldOption
    extend T::Helpers
    include Kernel
    abstract!

    sig { abstract.returns(T.nilable(Integer)) }
    def id; end

    sig { abstract.returns(String) }
    def name; end

    sig { abstract.returns(String) }
    def color; end

    sig { abstract.returns(User) }
    def owner; end

    sig { abstract.returns(Issues::IIssueField) }
    def issue_field; end
  end
end
