# typed: true
# frozen_string_literal: true

require "monolith-twirp-event_hydrator-event_hydration"
require "sorbet-runtime"

class WebhookPayloadHydrationTwirpEndpointGenerator < Rails::Generators::Base

  source_root T.let(File.expand_path("templates", __dir__), String)

  class_option :event_type, type: :string, required: true
  class_option :twirp_folder, type: :string, required: false

  sig { void }
  def validate_event_type
    unless event_type_exists?
      raise Thor::Error, <<~ERROR
        Invalid event type: #{event_type_enum_value} does not exist in Hydro::Schemas::EventsPlatform::V0::Entities::EventType.
        Please make sure it exists in hydro-schemas, and that the newest version of the gem
        "monolith-twirp-event_hydrator-event_hydration" is installed. Please reach out in #ecosystem-events for support.
      ERROR
    end
  end

  sig { void }
  def create_implementation_file
    template "handler.rb.erb", "app/api/internal/twirp/#{folder}/#{event_type}_api_handler.rb"
  end

  sig { void }
  def create_test_file
    template "handler_test.rb.erb", "test/integration/api/internal/twirp/#{folder}/#{event_type}_api_handler_test.rb"
  end

  sig { void }
  def mount_service
    inject_into_file "app/api/internal/twirp.rb", "  mount ::#{fully_qualified_class_name}\n", after: "# Webhook payload hydration handlers\n"
  end

  private

  sig { returns(String) }
  def event_type
    T.cast(@options[:event_type], String).downcase.delete_prefix("event_type_")
  end

  sig { returns(String) }
  def event_type_enum_value
    "EVENT_TYPE_#{event_type.upcase}"
  end

  sig { returns(T::Boolean) }
  def event_type_exists?
    Hydro::Schemas::EventsPlatform::V0::Entities::EventType.const_defined?(event_type_enum_value)
  end

  sig { returns(String) }
  def folder
    return T.cast(@options[:twirp_folder], String) if @options[:twirp_folder]
    "#{event_type.pluralize}/webhook_payload_hydration"
  end

  sig { returns(String) }
  def module_path
    folder.split("/").map(&:camelize).join("::")
  end

  sig { returns(String) }
  def class_name
    "#{event_type.gsub(" ", "_")}_api_handler".camelize
  end

  sig { returns(String) }
  def entity_class_name
    "#{event_type.gsub(" ", "_")}".camelize
  end

  sig { returns(String) }
  def fully_qualified_class_name
    "Api::Internal::Twirp::#{module_path}::#{class_name}"
  end

  sig { returns(String) }
  def handles_event_hydrator_twirp_service
    "#{event_type.gsub(" ", "_").camelize}APIService"
  end
end
