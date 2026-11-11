# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module ProcessorReadiness
      extend ActiveSupport::Concern

      included do
        T.bind(self, T.class_of(Hydro::Processor))

        set_callback :open, :before do
          ProcessorReadiness.report_ready
        end
      end

      STREAM_PROCESSOR_READY_FILE = "/tmp/stream-processor.startup"

      # Create a file to show that this processor is ready to accept messages.
      # This is used in Kubernetes to set a container to the Running state.
      def self.report_ready
        File.write(STREAM_PROCESSOR_READY_FILE, "ready")
      end
    end
  end
end
