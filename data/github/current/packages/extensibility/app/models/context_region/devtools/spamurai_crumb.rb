# typed: strict
# frozen_string_literal: true

module ContextRegion
  module Devtools
    class SpamuraiCrumb < IndexCrumb
      sig { override.returns(String) }
      def label
        "Spamurai Central"
      end

      sig { override.returns(T.nilable(Symbol)) }
      def path_name
        :devtools_spamurai_path
      end
    end
  end
end
