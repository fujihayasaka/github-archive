# typed: true
# frozen_string_literal: true

class Context
  class Expander
    def self.expand(payload)
      # This will be a modified copy of `payload` if any modifications are required
      event_payload = T.let(nil, T.nilable(T::Hash[T.untyped, T.untyped]))
      payload.each do |key, value|
        if value.respond_to?(:event_context)
          event_payload ||= payload.dup
          event_payload.delete(key)
          event_payload.update(value.event_context(prefix: key))
        elsif value.is_a?(Array) && value.any? { |v| v.respond_to?(:event_context) }
          values = value.collect do |val|
            if val.respond_to?(:event_context)
              val.event_context
            else
              val
            end
          end
          event_payload ||= payload.dup
          event_payload.update(key => values)
        end
      end

      # Return the modified one, if any modifications were applied.
      # Otherwise, return the unmodified hash as given.
      event_payload || payload
    end
  end

  attr_reader :stack

  def initialize(stack = [])
    @stack = stack
  end

  # Public: clears the context stack.
  #
  # Returns nothing.
  def clear
    @stack.clear
    @hash = nil
  end
  alias_method :reset, :clear

  # Public: push the given hash onto the context stack.
  #
  # If a block is given, yield to it and pop the hash back off when done.
  #
  # hash - Hash of values.
  #
  # Returns the block's return value or nothing.
  def push(hash = nil)
    if hash
      @stack.push Expander.expand(hash)
      @hash = nil
    end
    yield if block_given?
  ensure
    pop if hash && block_given?
  end

  # Public: Pop the top-most hash from the stack.
  #
  # Returns the Hash popped from the stack.
  def pop
    @hash = nil
    @stack.pop
  end

  # Public: Pops the first hash containing the key from the stack
  def pop_key(key)
    @hash = nil

    popped = T.let(nil, T.nilable(T::Hash[T.untyped, T.untyped]))
    (@stack.length - 1).downto(0) do |i|
      hash = @stack[i]
      if hash.has_key?(key)
        popped = @stack.delete_at(i)
        break
      end
    end

    popped
  end

  # Public: retreives the current value of the context stack.
  #
  # NOTE: This has to squash the context stack first so it can be an
  # expensive operation.
  #
  # Returns the value found for the key.
  def [](key)
    h = to_hash
    h.has_key?(key) ? h[key] : h[key.to_s]
  end

  def []=(key, value)
    raise NotImplementedError,
      "Use Context#push to put values on the context stack"
  end

  # Public: squashes the context stack into a single Hash.
  #
  # Returns the context stack as a Hash.
  def to_hash
    @hash ||=
      begin
        hash = {}
        @stack.each do |h|
          hash.merge! h
        end
        hash
      end
  end

  # Public: Merges another Hash into the squashed context stack.
  #
  # Returns a new merged Hash.
  def merge(other)
    to_hash.merge(other)
  end

end
