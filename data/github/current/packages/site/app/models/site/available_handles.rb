# typed: true
# frozen_string_literal: true

module Site
  class AvailableHandles
    class << self # rubocop:disable Style/ClassMethodsDefinitions
      APPROVED_HANDLES_DATA_PATH = "config/site/approved_handles.json"
      APPROVED_HANDLES_DIVERSITY_DATA_PATH = "config/site/approved_handles_diversity.json"

      def approved_handles
        @@approved_handles ||= load_json(APPROVED_HANDLES_DATA_PATH)
        @@approved_handles["handles"] || []
      end

      def diversity_handles
        @@diversity_handles ||= load_json(APPROVED_HANDLES_DIVERSITY_DATA_PATH)
        @@diversity_handles["handles"] || []
      end
    end

    def self.load_json(file_path)
      file_path = Rails.root.join(file_path)

      return {} if !File.exist?(file_path)

      begin
        GitHub::JSON.load File.read(file_path)
      rescue JSON::ParserError
        {}
      end
    end
  end
end
