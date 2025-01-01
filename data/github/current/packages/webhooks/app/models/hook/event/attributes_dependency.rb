# typed: true
# frozen_string_literal: true

require "set"

class Hook::Event
  module AttributesDependency
    extend ActiveSupport::Concern

    module ClassMethods
      attr_reader :valid_attribute_keys, :required_attribute_keys, :to_be_required_attribute_keys
      extend T::Helpers

      # Private: Used to define the available attributes for a given
      # event. Attributes passed to the Hook::Event on initialization
      # which are not explicitly defined will be ignored.
      #
      # attrs   - the list of attributes to define
      # options - optional event attribute configuration:
      #           :required - if true an error will be raised if
      #           the event is initialized without the required
      #           attributes
      #           :to_be_required - if true an error will be sent to failbot
      #           but will not stop the delivery of a webhook
      def event_attr(*attrs)
        options = attrs.extract_options!

        @valid_attribute_keys ||= Set.new
        @required_attribute_keys ||= Set.new
        @to_be_required_attribute_keys ||= Set.new

        @valid_attribute_keys.merge(attrs.map!(&:to_sym))
        @required_attribute_keys.merge(attrs) if options[:required]
        @to_be_required_attribute_keys.merge(attrs) if options[:to_be_required]

        attrs.each do |attr|
          T.unsafe(self).define_method(attr) do
            T.unsafe(self).attributes[attr]
          end

          T.unsafe(self).define_method(:"#{attr}=") do |value|
            T.unsafe(self).attributes[attr] = value
          end
        end
      end
      protected :event_attr

      def inherited(subclass)
        super

        subclass.event_attr :triggered_at
        subclass.event_attr :delivered_hook_ids
        subclass.event_attr :primary_resource_data
        subclass.event_attr :repository_id
        subclass.event_attr :organization_id
        subclass.event_attr :actor_id
        subclass.event_attr :business_id
        subclass.event_attr :event_guid
        subclass.event_attr :flags

      end
    end # ClassMethods

    attr_reader :attributes

    def initialize(attributes = {})
      @attributes = attributes.symbolize_keys.slice(*T.unsafe(self).class.valid_attribute_keys)

      return if Rails.env.test? && !Hook.delivers_in_test?

      validate_required_attributes
      validate_to_be_required_attributes
    end

    private

    include Kernel

    def validate_required_attributes
      return unless T.unsafe(self).class.required_attribute_keys
      T.unsafe(self).class.required_attribute_keys.each do |required_attr|
        raise MissingRequiredAttribute.new(T.unsafe(self).class.name, required_attr) unless attributes[required_attr].present?
      end
    end

    # Private: Validates the presence of attributes that will be required in
    # the future. If an attribute that has been marked as :to_be_required in the
    # event_attr and we're running in production, a needle will be sent to the
    # github-event-dispatch bucket and delivery of the webhook will proceed
    # without the attribute in the payload. If we're running in development or
    # test, an exception will be raised.
    #
    # Returns nothing.
    def validate_to_be_required_attributes
      return unless self.class.to_be_required_attribute_keys.present?

      self.class.to_be_required_attribute_keys.each do |required_attr|
        if attributes[required_attr].nil?
          error = MissingToBeRequiredAttribute.new(self.class.name, required_attr)

          if Rails.env.production?
            error.set_backtrace(caller)
            Failbot.report(error, app: "github-event-dispatch")
          else
            raise error
          end
        end
      end
    end
  end
end
