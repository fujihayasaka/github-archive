# typed: true
# frozen_string_literal: true

module Rest
  module Previews
    DEFAULT = {} unless const_defined?(:DEFAULT)

    def self.register(data)
      preview = Rest::Preview.new(**data)
      DEFAULT[preview.name] = preview
    end

    def self.get(preview_name)
      DEFAULT.fetch(preview_name)
    end

    def self.media_versions
      DEFAULT.values.map(&:media_version)
    end

    def self.version(name)
      get(name).media_version
    end

    def self.owning_teams(name)
      get(name).owning_teams
    end

    Dir.glob("./app/api/app/previews/*").each do |file|
      Rest::Previews.register YAML.safe_load(File.read(file)).symbolize_keys
    end
  end
end
