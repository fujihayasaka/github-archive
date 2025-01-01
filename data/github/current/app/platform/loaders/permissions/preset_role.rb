# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    module Permissions
      class PresetRole < Platform::Loader
        def self.load(name:)
          self.for.load(name)
        end

        def fetch(names)
          Role.presets.where(name: names).index_by(&:name)
        end
      end
    end
  end
end
