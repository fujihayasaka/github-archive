# frozen_string_literal: true

require "erb"

module FixtureHelpers
  def fixture(path)
    file_fixture(path).read
  end

  def json_fixture(path)
    JSON.parse(file_fixture(path + ".json").read)
  end

  def erb_fixture(path, values = {})
    body = fixture(path + ".erb")
    ERB.new(body).result(Namespace.new(values).get_binding)
  end

  class Namespace
    def initialize(hash)
      hash.each do |key, value|
        singleton_class.send(:define_method, key) { value }
      end
    end

    def get_binding # rubocop:disable Naming/AccessorMethodName
      binding
    end
  end
end
