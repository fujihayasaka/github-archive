# typed: true
# frozen_string_literal: true

class Hook::Event
  class MissingToBeRequiredAttribute < StandardError
    def initialize(class_name, missing_attr)
      super "#{class_name} fired with a missing attribute that is slated to be required: #{missing_attr}"
    end
  end
end
