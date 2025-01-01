# typed: true
# frozen_string_literal: true

module ApiSchema
  class JSONFile
    attr_reader :path
    def initialize(path)
      @path = path
    end

    def basename
      @basename ||= File.basename(path, ".*")
    end

    def canonical_id
      "https://schema.github.com/v3/#{basename}.json"
    end

    def normalized?
      file_contents.chomp == JSON.pretty_generate(data).chomp
    end

    def syntax_valid?
      !!data
    rescue JSON::ParserError
      false
    end

    def data
      @data ||= JSON.parse(file_contents)
    end

    def file_contents
      @file_contents ||= File.read(path)
    end
  end
end
