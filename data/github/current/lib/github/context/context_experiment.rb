# typed: true
# frozen_string_literal: true

require "context_alternative"

module GitHub
  # Careful when using this experiment class. Since this is modifying state it cannot be partially enabled.
  # Make sure all the experiments are enabled to 100% before even the init function gets executed.
  class ContextExperiment

    include Scientist

    def initialize(github_context, name_prefix)
      @github_context = github_context
      @name_prefix = name_prefix
      @alternative = ContextAlternative.new(github_context.stack)
    end

    def clear
      @github_context.clear
      @alternative.clear
    end
    alias_method :reset, :clear

    def push(hash = nil, &block)
      if block_given?
        # If a block is getting executed we cannot risk running that twice
        # since it could be anything. So we push and pop to the candidate manually.
        frame_id = @alternative.send :add_frame, hash&.dup
        val = @github_context.push(hash, &block)
        @alternative.send :remove_frame, frame_id
        val
      else
        # Since alternative modifies the hash temporarily we need to duplicate the hash
        # or risk mismatches.
        dup = hash&.dup
        Scientist.run @name_prefix + "_push" do |e|
          e.use { @github_context.push(hash) }
          e.try { @alternative.push(dup) }
        end
      end
    end

    def pop
      Scientist.run @name_prefix + "_pop" do |e|
        e.use { @github_context.pop }
        e.try { @alternative.pop }
        e.clean { |h| h&.keys }
      end
    end

    def pop_key(key)
      Scientist.run @name_prefix + "_pop_key" do |e|
        e.use { @github_context.pop_key(key) }
        e.try { @alternative.pop_key(key) }
        e.clean { |h| h&.keys }
      end
    end

    def [](key)
      return @github_context[key] if @lookup_reentry_guard
      @lookup_reentry_guard = true
      val = Scientist.run @name_prefix + "_lookup" do |e|
        e.use { @github_context[key] }
        e.try { @alternative[key] }
        # We cannot log values since they could be sensitive. So we log the key instead,
        # so we have at least an inkling where the problem is. We can update and remove
        # cleaning selectively if we observe problems with particular keys.
        e.clean { key }
      end
      @lookup_reentry_guard = false
      val
    end

    def to_hash
      return @github_context.to_hash if @to_hash_reentry_guard
      @to_hash_reentry_guard = true
      val = Scientist.run @name_prefix + "_to_hash" do |e|
        e.use { @github_context.to_hash }
        e.try { @alternative.to_hash }
        e.clean { |h| h&.keys }
      end
      @to_hash_reentry_guard = false
      val
    end

    def merge(other)
      Scientist.run @name_prefix + "_merge" do |e|
        e.use { @github_context.merge(other) }
        e.try { @alternative.merge(other) }
        e.clean { |h| h&.keys }
      end
    end
  end
end
