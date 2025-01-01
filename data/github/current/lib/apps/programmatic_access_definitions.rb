# typed: true
# frozen_string_literal: true

module Apps
  class ProgrammaticAccessDefinitions
    def self.load_yaml
      contents = GitHub.programmatic_access_definitions_path.read
      YAML.safe_load(contents, permitted_classes: [Symbol])
    end

    attr_reader :endpoints

    def self.empty
      new(:empty)
    end

    def initialize(contents)
      parse(contents)
    end

    def fetch(endpoint, default = nil)
      endpoints.fetch(endpoint, default)
    end

    def empty?
      endpoints.empty?
    end

    private

    def parse(contents)
      if contents == :empty
        @endpoints = {}
        return
      end

      @endpoints = contents.each_with_object({}) do |endpoint, hash|
        ep = endpoint.delete("endpoint")
        hash[ep] = endpoint
      end
    end
  end
end
