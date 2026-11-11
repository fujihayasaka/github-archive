# typed: strict
# frozen_string_literal: true

module Issues
  module IPinnedIssueComment
    extend T::Helpers

    include Kernel

    abstract!

    sig { abstract.returns(T.nilable(Integer)) }
    def id; end

    sig { abstract.returns(T.nilable(IssueComment)) }
    def issue_comment; end

    sig { abstract.returns(T.nilable(User)) }
    def pinned_by; end

    sig { abstract.returns(T.nilable(Repository)) }
    def repository; end

    sig { abstract.returns(T.nilable(Issue)) }
    def issue; end
  end
end
