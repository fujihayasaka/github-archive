# typed: true
# frozen_string_literal: true

module Platform
  class ExperimentRelation
    def initialize(name, control:, candidate:, context: nil, compare: nil, clean: nil, run_if: -> { true }, ignore: -> { false })
      @name = name
      @control = control
      @candidate = candidate
      @run_if = run_if
      @ignore = ignore
      @context = context
      @compare = compare
      @clean = clean
    end

    attr_reader :name, :control, :candidate, :run_if, :ignore, :context, :compare, :clean

    def count(*args)
      Scientist.run "#{name}-count" do |e|
        e.use { control.call.count(*args) }
        e.try { candidate.call.count(*args) }
        e.run_if { run_if.call }
        e.ignore { ignore.call }
        e.context(context) if context
        e.compare { |control, candidate| compare.call(control, candidate) } if compare
        e.clean { |value| clean.call(value) } if clean
      end
    end

    def include?(*args)
      Scientist.run "#{name}-include" do |e|
        e.use { control.call.include?(*args) }
        e.try { candidate.call.include?(*args) }
        e.run_if { run_if.call }
        e.ignore { ignore.call }
        e.context(context) if context
        e.compare { |control, candidate| compare.call(control, candidate) } if compare
        e.clean { |value| clean.call(value) } if clean
      end
    end

    def eql?(*args)
      Scientist.run "#{name}-eql" do |e|
        e.use { control.call.eql?(*args) }
        e.try { candidate.call.eql?(*args) }
        e.run_if { run_if.call }
        e.ignore { ignore.call }
        e.context(context) if context
        e.compare { |control, candidate| compare.call(control, candidate) } if compare
        e.clean { |value| clean.call(value) } if clean
      end
    end

    def ==(*args)
      Scientist.run "#{name}-eql" do |e|
        e.use { control.call.send(:==, *args) }
        e.try { candidate.call.public_send(:==, *args) }
        e.run_if { run_if.call }
        e.ignore { ignore.call }
        e.context(context) if context
        e.compare { |control, candidate| compare.call(control, candidate) } if compare
        e.clean { |value| clean.call(value) } if clean
      end
    end

    def to_ary(*args)
      Scientist.run "#{name}-to-ary" do |e|
        e.use { control.call.send(:to_ary, *args) }
        e.try { candidate.call.public_send(:to_ary, *args) }
        e.run_if { run_if.call }
        e.ignore { ignore.call }
        e.context(context) if context
        e.compare { |control, candidate| compare.call(control, candidate) } if compare
        e.clean { |value| clean.call(value) } if clean
      end
    end

    def first(*args)
      Scientist.run "#{name}-first" do |e|
        e.use { control.call.send(:first, *args) }
        e.try { candidate.call.public_send(:first, *args) }
        e.run_if { run_if.call }
        e.ignore { ignore.call }
        e.context(context) if context
        e.compare { |control, candidate| compare.call(control, candidate) } if compare
        e.clean { |value| clean.call(value) } if clean
      end
    end

    def each(*args)
      Scientist.run "#{name}-each" do |e|
        e.use { control.call.send(:each, *args) }
        e.try { candidate.call.public_send(:each, *args) }
        e.run_if { run_if.call }
        e.ignore { ignore.call }
        e.context(context) if context
        e.compare { |control, candidate| compare.call(control, candidate) } if compare
        e.clean { |value| clean.call(value) } if clean
      end
    end

    def map(&block)
      Scientist.run "#{name}-map" do |e|
        e.use { control.call.send(:map, &block) }
        e.try { candidate.call.send(:map, &block) }
        e.run_if { run_if.call }
        e.ignore { ignore.call }
        e.context(context) if context
        e.compare { |control, candidate| compare.call(control, candidate) } if compare
        e.clean { |value| clean.call(value) } if clean
      end
    end

    def empty?(*args)
      Scientist.run "#{name}-empty" do |e|
        e.use { control.call.empty?(*args) }
        e.try { candidate.call.empty?(*args) }
        e.run_if { run_if.call }
        e.ignore { ignore.call }
        e.context(context) if context
        e.compare { |control, candidate| compare.call(control, candidate) } if compare
        e.clean { |value| clean.call(value) } if clean
      end
    end

    alias_method :size, :count
    alias_method :to_a, :to_ary
  end
end
