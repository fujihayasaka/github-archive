# typed: false
# frozen_string_literal: true

require "set"

# Mixin to instrument attribute access on ActiveRecord models, tagged on a per-route basis
module AttributeAccessTelemetry
  extend ActiveSupport::Concern

  included do
    after_initialize :instrument_on_attribute_access

    private

    def instrument_on_attribute_access
      return if @_attribute_readers_instrumented

      self.class.column_names.each do |attribute|
        singleton_class.class_eval do
          define_method(attribute) do |*args, &block|
            instrument_attribute_access(attribute)
            super(*args, &block)
          end
        end
      end

      @_attribute_readers_instrumented = true
    end
  end

  def read_attribute(attr_name, &block)
    instrument_attribute_access(attr_name) if model_column_names.include?(attr_name.to_s)
    super(attr_name, &block)
  end

  private

  def instrument_attribute_access(attribute_name)
    return unless should_instrument_attribute_access?
    return unless GitHub.context[:controller].present? && GitHub.context[:controller_action].present?
    return unless controller_actor.feature_flag_enabled?(:application_record_attribute_access_telemetry_route, default: false)
    return if source_tags.empty?

    tags = build_telemetry_tags(attribute_name)
    GitHub.dogstats.increment("github.application_record.attribute_access", tags: tags)
  rescue
    # we don't want anything bad to happen if telemetry fails
  end

  def should_instrument_attribute_access?
    return @should_instrument_attribute_access if defined?(@should_instrument_attribute_access)

    id = attributes_before_type_cast["id"]
    return @should_instrument_attribute_access = false unless id.present?

    actor = "#{self.class.name}:#{id}"
    @should_instrument_attribute_access = FeatureFlag.vexi.enabled?(:application_record_attribute_access_telemetry, actor, default: false)
  end

  def build_telemetry_tags(attribute_name)
    @telemetry_tags ||= {}
    return @telemetry_tags[attribute_name] if @telemetry_tags.key?(attribute_name)
    tags = ["attribute:#{attribute_name}", "model:#{safe_model_name}"]
    tags.concat(source_tags)
    @telemetry_tags[attribute_name] = tags
  end

  def model_column_names
    @model_column_names ||= Set.new(self.class.column_names)
  end

  def safe_model_name
    @safe_model_name ||= self.class.model_name.name.underscore.downcase
  end

  def source_tags
    @source_tags ||= (GitHub.context[:remote_call_source_datadog_tags] || {})
  end

  def controller_actor
    return @controller_actor if defined?(@controller_actor)
    controller = GitHub.context[:controller]
    action = GitHub.context[:controller_action]
    @controller_actor = GitHub::ControllerRouteActor.build(controller, action)
  end
end
