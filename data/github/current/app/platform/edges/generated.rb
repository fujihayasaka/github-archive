# typed: true
# frozen_string_literal: true

module Platform
  module Edges
    # A namespace in which to store edge type classes
    # (e.g. by `Connections.define`) which would be otherwise anonymous
    # and thus a bit of a pain to develop with and debug. Assigning a
    # class or module to a constant automatically populates its `name`
    # and gives it a nice inspect implementation, turning this:
    #
    #     irb(main):001:0> wut_is_this
    #     => #<Class:0x00007f2630028d68>
    #
    # into this:
    #
    #     irb(main):001:0> wut_is_this
    #     => Platform::Edges::Generated::PullRequestThread
    #
    # In particular this is important for IDE tooling and static analysis,
    # which is better at handling classes that have names.
    #
    # See `Platform::Connections::Base.edge_type`, where constants are
    # added to this module.
    module Generated
    end
  end
end
