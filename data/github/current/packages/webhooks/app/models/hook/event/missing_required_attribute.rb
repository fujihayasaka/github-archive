# typed: true
# frozen_string_literal: true

class Hook::Event
  class MissingRequiredAttribute < StandardError
    def initialize(class_name, missing_attr)
      super "#{class_name} fired with a missing required attribute: #{missing_attr}"
    end

    def failbot_context
      {
        "app" => "github-event-dispatch",
      }
    end
  end
end
