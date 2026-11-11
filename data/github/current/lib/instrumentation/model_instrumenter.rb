# typed: true
# frozen_string_literal: true

require "instrumentation/model"

module Instrumentation
  class ModelInstrumenter
    include Model
    attr_reader :model

    def initialize(model)
      @model = model
      check_model_defined_methods
    end

    # If model defines event_prefix delegate to it, otherwise
    # override Instrumentation::Model implementation to use prefix for model
    def event_prefix
      model_event_prefix || model_name_event_prefix
    end

    # If model defines event_payload delegate to it,
    # otherwise use default from Instrumentation::Model
    def event_payload
      return model.event_payload if model.respond_to?(:event_payload)
      super
    end

    private

    def check_model_defined_methods
      [:event_payload, :event_prefix].each do |meth|
        if model.private_methods.include?(meth)
          raise "#{self.class.name} initialized with model instance of #{model.class.name} which defines private method #{meth} which should be public"
        end
      end
    end

    def model_event_prefix
      return nil unless model.respond_to?(:event_prefix)
      model.event_prefix
    end

    def model_name_event_prefix
      @model_name_event_prefix ||= model.class.name.underscore.to_sym
    end
  end
end
