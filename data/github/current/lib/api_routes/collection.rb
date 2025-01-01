# typed: true
# frozen_string_literal: true
module ApiRoutes
  # A collection of routes within a namespace.
  class Collection
    include Enumerable

    attr_reader :namespace_class, :endpoints
    def initialize(namespace)
      @namespace_class = namespace
      @endpoints = []
    end

    def namespace
      namespace_class.to_s
    end

    def documentation_namespace
      @documentation_namespace ||= doc_namespace_replacements.reduce(namespace.split("::").last.titleize) do |s, (k, v)|
        s.gsub(k, v)
      end
    end

    def add(endpoints)
      @endpoints += endpoints
    end

    def <<(endpoint)
      endpoints << endpoint
    end

    def each(&block)
      endpoints.each(&block)
    end

    private

    def doc_namespace_replacements
      {
        "Porter" => "Source Imports",
        "Repo Pages" => "GitHub Pages",
      }
    end

  end
end
