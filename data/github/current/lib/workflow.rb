# typed: true
# frozen_string_literal: true

# Copyright (c) 2016 Lorefnon
# Copyright (c) 2010-2014 Vladimir Dobriakov
# Copyright (c) 2008-2009 Vodafone
# Copyright (c) 2007-2008 Ryan Allen, FlashDen Pty Ltd

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

module Workflow
  extend T::Helpers

  requires_ancestor { ActiveRecord::Base }

  class Error < StandardError; end
  class NoTransitionAllowed < Error; end
  class TransitionHalted < Error; end

  def self.included(base)
    super
    base.before_validation :write_initial_state
  end

  module ClassMethods
    extend T::Helpers
    extend T::Sig

    requires_ancestor { T.class_of(ActiveRecord::Base) }

    attr_reader :workflow_spec

    sig { params(column: Symbol, specification: T.proc.bind(Specification).void).void }
    def workflow(column, &specification)
      @workflow_state_column_name = column
      @workflow_spec = Specification.new(Hash.new, &specification)
      define_workflow_methods
      define_scopes

      define_method("#{@workflow_state_column_name}=") do |val|
        matching_state = workflow_spec.states.select { |_k, v| v.name.to_s == val.to_s }.values.first
        val = matching_state.value if matching_state
        super(val)
      end
    end

    def workflow_column
      @workflow_state_column_name
    end

    private

    def define_scopes
      @workflow_spec.states.values.each do |state|
        define_singleton_method("with_#{state}_state") do
          where(workflow_column.to_sym => state.value)
        end

        define_singleton_method("without_#{state}_state") do
          where.not(workflow_column.to_sym => state.value)
        end

        define_method("without_#{state}_state") do
          ActiveSupport.deprecator.warn("Workflow#without#{state}_state is deprecated as an instance method.")

          where.not(T.cast(self.class, Workflow::ClassMethods).workflow_column.to_sym => state.value)
        end
      end
    end

    def define_workflow_methods
      @workflow_spec.states.values.each do |state|
        state_name = state.name
        module_eval do
          define_method "#{state_name}?" do
            state_name == current_state.name
          end
        end

        unique_events = state.events.values.flatten.uniq do |event|
          [:name, :transitions_to, :meta, :action].map { |m| event.send(m) }
        end

        unique_events.each do |event|
          event_name = event.name
          module_eval do
            define_method "#{event_name}!".to_sym do |*args, **kwargs|
              process_event!(event_name, *args, **kwargs)
            end

            define_method "can_#{event_name}?" do
              !!current_state.events.fetch(event_name, []).detect do |event|
                event.condition_applicable?(self) && event
              end
            end
          end
        end
      end
    end
  end

  mixes_in_class_methods(ClassMethods)

  def workflow_column
    T.cast(self.class, Workflow::ClassMethods).workflow_column
  end

  def workflow_spec
    T.cast(self.class, Workflow::ClassMethods).workflow_spec
  end

  def current_state
    loaded_state_value = read_attribute(workflow_column)
    if loaded_state_value
      loaded_state_name = workflow_spec.states.select { |_k, v| v.value.to_s == loaded_state_value.to_s }.keys.first
    end

    res = workflow_spec.states[loaded_state_name.to_sym] if loaded_state_name
    res || workflow_spec.initial_state
  end

  def write_initial_state
    write_attribute(workflow_column, current_state.value)
  end

  def process_event!(name, *args, **kwargs)
    event = current_state.events.fetch(name, []).detect do |event|
      event.condition_applicable?(self) && event
    end

    if event.nil?
      return T.unsafe(self).run_on_unavailable_transition(current_state, name, *args, **kwargs)
    end

    @halted_because = nil
    @halted = false

    check_transition(event)

    from = current_state
    to_state = workflow_spec.states[event.transitions_to]
    to_value = to_state.value

    T.unsafe(self).run_before_transition(from, to_state, name, *args, **kwargs)
    return false if halted?

    return_value = T.unsafe(self).run_action(event.action, *args, **kwargs) || T.unsafe(self).run_action_callback(event.name, *args, **kwargs)

    return false if halted?

    T.unsafe(self).run_on_transition(from, to_state, name, *args, **kwargs)

    T.unsafe(self).run_on_exit(from, to_state, name, *args)

    transition_value = persist_workflow_state(to_value)

    T.unsafe(self).run_on_entry(to_state, from, name, *args, **kwargs)

    T.unsafe(self).run_after_transition(from, to_state, name, *args, **kwargs)

    return_value.nil? ? transition_value : return_value
  end

  def persist_workflow_state(new_value)
    update_column(workflow_column, new_value)
  end

  def halt(reason = nil)
    @halted_because = reason
    @halted = true
  end

  def halt!(reason = nil)
    @halted_because = reason
    @halted = true
    raise TransitionHalted.new(reason)
  end

  def halted?
    @halted
  end

  def halted_because
    @halted_because
  end

  def check_transition(event)
    # Create a meaningful error message instead of
    # "undefined method `on_entry' for nil:NilClass"
    # Reported by Kyle Burton
    if !workflow_spec.states[event.transitions_to]
      raise Error.new("Event[#{event.name}]'s " +
                      "transitions_to[#{event.transitions_to}] is not a declared state.")
    end
  end

  def run_before_transition(from, to, event, *args, **kwargs)
    T.unsafe(self).instance_exec(from.name, to.name, event, *args, **kwargs, &workflow_spec.before_transition_proc) if
      workflow_spec.before_transition_proc
  end

  def run_on_unavailable_transition(from, to_name, *args, **kwargs)
    if !workflow_spec.on_unavailable_transition_proc || !T.unsafe(self).instance_exec(from.name, to_name.to_sym, *args, &workflow_spec.on_unavailable_transition_proc)
      raise NoTransitionAllowed.new("There is no event #{to_name.to_sym} defined for the #{current_state} state")
    end
  end

  def run_on_transition(from, to, event, *args, **kwargs)
    T.unsafe(self).instance_exec(from.name, to.name, event, *args, **kwargs, &workflow_spec.on_transition_proc) if workflow_spec.on_transition_proc
  end

  def run_after_transition(from, to, event, *args, **kwargs)
    T.unsafe(self).instance_exec(from.name, to.name, event, *args, **kwargs, &workflow_spec.after_transition_proc) if
      workflow_spec.after_transition_proc
  end

  def run_action(action, *args, **kwargs)
    T.unsafe(self).instance_exec(*args, **kwargs, &action) if action
  end

  def has_callback?(action)
    # 1. public callback method or
    # 2. protected method somewhere in the class hierarchy or
    # 3. private in the immediate class (parent classes ignored) or
    # 4. private in a module nested in the immediate class
    action = action.to_sym
    return true if self.respond_to?(action)
    return true if self.class.protected_method_defined?(action)
    return true if self.private_methods(false).map(&:to_sym).include?(action)

    if self.private_methods(true).map(&:to_sym).include?(action)
      method_owner = method(action).owner
      if method_owner.respond_to?(:module_parent_name) && method_owner.module_parent_name == self.class.name
        return true
      end
    end

    false
  end

  def run_action_callback(action_name, *args, **kwargs)
    action = action_name.to_sym
    T.unsafe(self).send(action, *args, **kwargs) if has_callback?(action)
  end

  def run_on_entry(state, prior_state, triggering_event, *args, **kwargs)
    if state.on_entry
      T.unsafe(self).instance_exec(prior_state.name, triggering_event, *args, **kwargs, &state.on_entry)
    else
      hook_name = "on_#{state}_entry"
      T.unsafe(self).send hook_name, prior_state, triggering_event, *args, **kwargs if has_callback?(hook_name)
    end
  end

  def run_on_exit(state, new_state, triggering_event, *args, **kwargs)
    if state
      if state.on_exit
        T.unsafe(self).instance_exec(new_state.name, triggering_event, *args, **kwargs, &state.on_exit)
      else
        hook_name = "on_#{state}_exit"
        T.unsafe(self).self.send hook_name, new_state, triggering_event, *args, **kwargs if has_callback?(hook_name)
      end
    end
  end

  class Event
    attr_accessor :name, :transitions_to, :meta, :action, :condition, :invert_condition

    def initialize(name, transitions_to, condition: nil, invert_condition: false, meta: {}, &action)
      @name = name
      @transitions_to = transitions_to.to_sym
      @meta = meta
      @action = action
      @condition =
        if condition.nil? || condition.is_a?(Symbol) || condition.respond_to?(:call)
          condition
        else
          raise TypeError, "condition must be nil, an instance method name symbol or a callable (eg. a proc or lambda)"
        end
      @invert_condition = invert_condition
    end

    def condition_applicable?(object)
      if condition
        result = object.send(condition)
        if invert_condition
          !result
        else
          result
        end
      else
        true
      end
    end

    def to_s
      @name.to_s
    end
  end

  class Specification
    attr_accessor :states, :initial_state, :meta,
                  :on_transition_proc, :before_transition_proc,
                  :after_transition_proc, :on_unavailable_transition_proc

    def initialize(meta = {}, &specification)
      @states = Hash.new
      @meta = meta
      instance_eval(&specification)
    end

    def state_names
      @states.keys
    end

    private

    def state(name, value = nil, options = {}, &events_and_etc)
      value ||= name

      new_state = Workflow::State.new(name, value, self, options[:meta])
      @initial_state = new_state if @states.empty?
      @states[name] = new_state
      @scoped_state = new_state
      instance_eval(&events_and_etc) if events_and_etc
    end

    def event(name, transitions_to:, **kwargs, &action)
      @scoped_state.events[name] ||= []
      condition = nil
      invert_condition = false
      if kwargs[:if]
        condition = kwargs[:if]
      elsif kwargs[:unless]
        condition = kwargs[:unless]
        invert_condition = true
      end
      @scoped_state.events[name] << Workflow::Event.new(name, transitions_to, condition: condition,
        invert_condition: invert_condition, meta: (kwargs[:meta] || {}), &action)
    end

    def on_entry(&proc)
      @scoped_state.on_entry = proc
    end

    def on_exit(&proc)
      @scoped_state.on_exit = proc
    end

    def after_transition(&proc)
      @after_transition_proc = proc
    end

    def before_transition(&proc)
      @before_transition_proc = proc
    end

    def on_transition(&proc)
      @on_transition_proc = proc
    end

    def on_unavailable_transition(&proc)
      @on_unavailable_transition_proc = proc
    end
  end

  class State
    include Comparable
    attr_accessor :name, :value, :events, :meta, :on_entry, :on_exit

    def initialize(name, value, spec, meta = {})
      @name, @value, @spec, @events, @meta = name, value, spec, Hash.new, meta
    end

    def <=>(other_state)
      states = @spec.states.keys
      raise ArgumentError, "state `#{other_state}' does not exist" unless states.include?(other_state.to_sym)
      states.index(self.to_sym) <=> states.index(other_state.to_sym)
    end

    def to_s
      "#{name}"
    end

    def to_sym
      name.to_sym
    end
  end
end
