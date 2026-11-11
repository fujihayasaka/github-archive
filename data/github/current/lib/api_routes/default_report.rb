# typed: true
# frozen_string_literal: true

class ApiRoutes::DefaultReport
  def self.collector
    ApiRoutes::DefaultCollector
  end

  attr_reader :collections
  def initialize(collections)
    @collections = collections
  end

  def print
    collections.each do |collection|
      puts <<-EOS
### Within #{collection.namespace}

    #{collection.endpoints.join("\n    ")}

EOS
    end
  end
end
