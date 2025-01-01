# typed: true
# frozen_string_literal: true

require "context" # for using the Expander class

# This class is intended as an alternative to Context providing the same methods.
#
# Complexity comparisons:
#
#   n: Number of context frames on the stack
#   k: Number of keys in a single frame
#   k': Total number of different keys
#
# Method      | Context  | ContextAlternative
# clear       | O(1)     | O(1)
# push        | O(1)     | O(k)
# pop         | O(1)     | O(k)
# pop_key     | O(n)     | O(k + log n)
# [] (lookup) | O(n * k) | O(log n)
# to_hash     | O(n * k) | O(k' * log n)
#
# The push and pop complexity is linear in the number of keys in the pushed/popped context
# but usually, at least in push, this price is paid anyway if the caller needs to construct the hash first.
# What we gain is a significant improvement for lookup, conversion to hash and pop_key.
#
class ContextAlternative

  # This class maintains two data structures to represent internal state.
  #  - @frames contains the stack of pushed frames. Each frame is a pair of an integer frame
  #    id and the pushed hash. A frame higher on the stack has a greater id than one lower on the stack.
  #  - @data is a hash that stores for each key present in any of the frames a sorted array of the ids
  #    the key is present in.
  # Note that we could consider adding a hash containing the current lookup mapping. This would reduce
  # the cost of lookup to O(1) and to_hash to O(k') by increasing the cost of pop and pop_key by a factor of log n.



  # Public: creates a new instance initialized with the given stack.
  def initialize(stack = [])
    @frames = []
    @data = {}
    stack.each { |h| push(h) }
  end

  # Public: clears the context stack.
  #
  # Returns nothing.
  def clear
    @frames = []
    @data = {}
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
    frame_id = 0
    if hash
      hash = Context::Expander.expand(hash)
      frame_id = add_frame(hash)
    end
    yield if block_given?
  ensure
    remove_frame(frame_id) if block_given? && frame_id != 0
  end

  # Private: add a frame to the stack and record the frame id for all the keys.
  #
  # Returns the id of the new frame
  private def add_frame(hash)
    frame_id = get_max_frame_id + 1
    hash.each_key do |key|
      frame_ids = @data[key] ||= []
      frame_ids.append(frame_id)
    end

    @frames.append([frame_id, hash])

    frame_id
  end

  # Private: Look up the current maximum frame id.
  private def get_max_frame_id
    return 0 if @frames.empty?
    @frames.last.first
  end

  # Public: Pop the top-most hash from the stack.
  #
  # Returns the Hash popped from the stack.
  def pop
    return nil if @frames.empty?
    frame = @frames.pop

    # We do not use remove_frame here since removing from the end is
    # more efficient than binary search.
    hash = frame.last
    hash.each_key do |key|
      @data[key].pop
      @data.delete(key) if @data[key].empty?
    end

    hash
  end

  # Public: Pops the first hash containing the key from the stack
  def pop_key(key)
    frame_id = @data[key]&.last
    return nil if frame_id.nil?

    remove_frame(frame_id)
  end

  private def remove_frame(frame_id)
    # TODO Perhaps optimize to just call pop if we're removing the top frame

    idx = @frames.bsearch_index { |f| f.first >= frame_id }
    frame = @frames.delete_at(idx)
    hash = frame.last

    hash.each_key do |key|
      frame_ids = @data[key]
      if frame_ids.length == 1
        @data.delete(key)
      else
        idx = frame_ids.bsearch_index { |i| i >= frame_id }
        frame_ids.delete_at(idx)
      end
    end

    hash
  end

  # Public: retrieves the current value of the context stack.
  #
  # Returns the value found for the key.
  def [](key)
    frame_id = @data[key]&.last
    if frame_id.nil?
      key = key.to_s
      frame_id = @data[key]&.last
    end
    return nil if frame_id.nil?

    frame = @frames.bsearch { |f| f.first >= frame_id }
    frame.last[key]
  end

  def []=(key, value)
    raise NotImplementedError,
          "Use ContextAlternative#push to put values on the context stack"
  end

  # Public: squashes the context stack into a single Hash.
  #
  # Returns the context stack as a Hash.
  def to_hash
    h = {}
    @data.each do |key, frame_ids|
      frame_id = frame_ids.last
      h[key] = @frames.bsearch { |f| f.first >= frame_id }.last[key]
    end

    h
  end

  # Public: Merges another Hash into the squashed context stack.
  #
  # Returns a new merged Hash.
  def merge(other)
    to_hash.merge(other)
  end
end
