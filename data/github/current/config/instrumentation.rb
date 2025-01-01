# typed: true
# frozen_string_literal: true

require "cache_key_logging_denylist"
require "github/template_tracing"
require "github/template_tracing_renderer"

# Loaded when instrumentation is enabled for the current process to install any
# custom hooks. The file is loaded during Rails's after_initialize hook so
# most classes should be available.
#
# See also: config/initializers/instrumentation.rb

# Instrument Memcached time
class Memcached::Rails
  def self.collector
    GitHub::DataCollector::MemcacheInstrumenterCollector.get_instance
  end

  def self.query_time
    collector.query_time
  end

  def self.query_time=(value)
    collector.query_time = value
  end

  def self.query_count
    collector.query_count
  end

  def self.query_count=(value)
    collector.query_count = value
  end

  def self.query_tracing
    collector.query_tracing
  end

  def self.query_tracing=(value)
    collector.query_tracing = value
  end
end

module Memcached::Rails::WithTiming
  [:decr, :incr, :get, :get_multi, :set, :add, :replace, :delete, :prepend, :append].each do |op|
    class_eval <<-RUBY, __FILE__, __LINE__ + 1
      def #{op}(*args, &block)
        elapsed = nil

        if (prev = Memcached::Rails.query_tracing) == false
          Memcached::Rails.query_tracing = true
          start = Time.now
        end

        if !defined?(@_partition)
          @_partition = respond_to?(:current_partition) ? current_partition || "unknown" : "unknown"
        end

        # We must escape # here to ensure we defer the string interpolation until the method is executed
        tags = [
          "rpc_operation:#{op}",
          "cache_class:\#{self.class.name.underscore}",
          "partition:\#{@_partition}",
        ]

        tags.concat(GitHub.context[:remote_call_source_datadog_tags]) if GitHub.context[:remote_call_source_datadog_tags]

        start_time = GitHub::Dogstats.monotonic_time
        begin
          super(*args, &block)
        ensure
          elapsed = GitHub::Dogstats.duration(start_time)

          GitHub.dogstats.distribution("rpc.memcached.dist.time", elapsed, tags: tags)
        end
      ensure
        if prev == false
          Memcached::Rails.query_time += elapsed.nil? ? (Time.now-start) : (elapsed / 1000)
          Memcached::Rails.query_count += 1
          Memcached::Rails.query_tracing = prev
        end
      end
    RUBY
  end
end

Memcached::Rails.send(:prepend, Memcached::Rails::WithTiming)

# Instrument activerecord object instantiation
# This is called for every query so must do as little work as possible
if !GitHub::AppEnvironment.test?
  Trilogy::ActiveRecordInstantiationSubscriber.subscribe # rubocop:disable GitHub/DoNotReferenceTrilogy
end

class ActionView::Template
  class << self
    attr_accessor :template_trace, :template_trace_enabled
  end

  def self.template_trace_reset
    self.template_trace = GitHub::TemplateTracing.new
  end
  self.template_trace_enabled = false
end

module ActionView::Template::WithTiming
  def render(view, locals, buffer = nil, implicit_locals: [], add_to_stack: true, &block)
    T.bind(self, ActionView::Template)
    if !ActionView::Template.template_trace_enabled
      return super(view, locals, buffer, implicit_locals:, add_to_stack:, &block)
    end

    begin
      ActionView::Template.template_trace.start(virtual_path)
      super(view, locals, buffer, implicit_locals:, add_to_stack:, &block)
    ensure
      ActionView::Template.template_trace.finished(virtual_path)
    end
  end
end

ActionView::Template.send(:prepend, ActionView::Template::WithTiming)

if Rails.env.development? || GitHub.admin_host?
  module ViewComponent::Base::WithTiming
    def render_in(view_context, &block)
      T.bind(self, ViewComponent::Base)
      if !ActionView::Template.template_trace_enabled
        return super(view_context, &block)
      end

      begin
        ActionView::Template.template_trace.start(virtual_path)
        super(view_context, &block)
      ensure
        ActionView::Template.template_trace.finished(virtual_path)
      end
    end
  end

  ViewComponent::Base.send(:prepend, ViewComponent::Base::WithTiming)
end


# Load all subscribers from config/instrumentation/
Dir[Rails.root + "config/instrumentation/*.rb"].each { |l| require l }

# Load all subscribers from packages' config/instrumentation/
Dir[Rails.root + "packages/*/config/instrumentation/*.rb"].each { |l| require l }

HydroLoader.load_github unless GitHub.lazy_load_hydro?
