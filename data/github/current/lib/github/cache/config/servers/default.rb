# typed: true
# frozen_string_literal: true

module GitHub
  module Cache
    class Config
      module Servers
        class Default
          def servers
            ["localhost:11211"]
          end
        end
      end
    end
  end
end
