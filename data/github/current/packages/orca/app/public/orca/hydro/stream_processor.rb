# typed: strict
# frozen_string_literal: true

module Orca
  class Hydro
    class StreamProcessor < GitHub::StreamProcessors::BaseProcessor

      DEFAULT_GROUP_ID = T.let("github-#{Rails.env}-orca_processor", String)
      DEFAULT_SUBSCRIBE_TO = /orca\.v0\..*\Z/

      options[:session_timeout] = 60.seconds
      options[:socket_timeout] = 65.seconds
      options[:start_from_beginning] = false

      sig { params(kwargs: T.untyped).void }
      def setup(**kwargs)
        options[:group_id] = DEFAULT_GROUP_ID
        options[:subscribe_to] = DEFAULT_SUBSCRIBE_TO
      end

      sig { params(message: GitHub::StreamProcessors::Message).void }
      def process_message(message)
        environment = message.value[:environment]
        if environment.present? && environment != Rails.env
          return
        end

        ::Orca::Hydro.handle_message(message.topic, message.value)
      end
    end
  end
end
