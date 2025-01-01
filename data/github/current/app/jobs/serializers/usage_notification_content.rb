# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module Serializers
  class UsageNotificationContent < ActiveJob::Serializers::ObjectSerializer
    def serialize(model)
      super(model.as_json)
    end

    def deserialize(hash)
      Billing::Notifications::UsageNotificationContent.new(**hash.excluding(ActiveJob::Arguments::OBJECT_SERIALIZER_KEY).deep_symbolize_keys)
    end

    private

    def klass
      Billing::Notifications::UsageNotificationContent
    end
  end
end
