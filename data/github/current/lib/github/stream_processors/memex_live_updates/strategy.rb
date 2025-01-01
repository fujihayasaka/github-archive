# typed: true
# frozen_string_literal: true

require "github/stream_processors/memex_live_updates/strategy/base"
require "github/stream_processors/memex_live_updates/strategy/result"

module GitHub
  module StreamProcessors
    module MemexLiveUpdates
      module Strategy
        extend T::Helpers

        requires_ancestor { Kernel }

        def registered_topics
          Base.subclasses.map(&:topics).flatten.uniq
        end
        module_function :registered_topics

        def for_message(message)
          klass = Base.subclasses.find do |subclass|
            subclass.topics.any? { |topic| message.topic =~ topic }
          end

          unless klass
            raise NotImplementedError, "Strategy for #{message.topic} has not been registered"
          end

          klass.new(message)
        end
        module_function :for_message
      end
    end
  end
end
