# typed: true

module RuboCop
  module Cop
    module GitHub
      class AvoidActiveRecordCallbacks < Base
        def callback(node); end
      end
    end
  end
end
