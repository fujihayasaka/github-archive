# typed: strict
# frozen_string_literal: true

module Issues
  module IIssueFieldValue
    extend T::Helpers
    include Kernel
    abstract!

    sig { abstract.returns(T.nilable(Integer)) }
    def id; end

    sig { abstract.returns(Issues::IIssueField) }
    def issue_field; end

    sig { abstract.returns(Issue) }
    def issue; end

    sig { abstract.returns(T.nilable(Integer)) }
    def issue_id; end

    sig { abstract.returns(T.nilable(String)) }
    def data_type; end

    sig { abstract.returns(T.untyped) }
    def value; end

    sig { abstract.returns(User) }
    def actor; end
  end
end
