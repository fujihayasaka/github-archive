# typed: true
# frozen_string_literal: true

class Repository::NetworkGraph
  # NetworkGraph's special commit object. Adds graph specific attributes to the
  # basic Commit object. Delegates all other commit information to the wrapped
  # commit object.
  class Commit
    attr_accessor :children, :drawn, :time_position, :space_position
    attr_accessor :timestamp

    def initialize(wrapped)
      @wrapped = wrapped
    end

    def add_child(child)
      @children ||= []
      @children << child
    end

    def method_missing(meth, *args, &block)
      if @wrapped.respond_to?(meth)
        @wrapped.__send__(meth, *args, &block)
      else
        super
      end
    end
  end
end
