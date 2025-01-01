# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module DeadLetter
      autoload :CLI, "github/stream_processors/dead_letter/cli"
      autoload :TopicIterator, "github/stream_processors/dead_letter/topic_iterator"
    end
  end
end
