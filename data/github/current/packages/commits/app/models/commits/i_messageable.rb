# typed: strict
# frozen_string_literal: true

module Commits
  module IMessageable
    extend T::Helpers

    include Kernel

    requires_ancestor { Object }

    abstract!

    sig { abstract.returns((String)) }
    def message; end

    sig { abstract.returns((String)) }
    def oid; end

    sig { abstract.returns((Repository)) }
    def repository; end
  end
end
