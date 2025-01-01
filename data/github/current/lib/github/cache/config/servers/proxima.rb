# typed: true
# frozen_string_literal: true

module GitHub
  module Cache
    class Config
      module Servers
        class Proxima
          include GitHub::Memoizer

          sig { returns(T.nilable(T::Array[String])) }
          memoize def servers
            YAML.load(File.read(SERVER_CONFIG_PATH))[GitHub::Config::Proxima.current_stamp]
          end
        end
      end
    end
  end
end
