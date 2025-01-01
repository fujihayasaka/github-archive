# typed: true
# frozen_string_literal: true

module ContextRegion
  module Devtools
    class SpamuraiCrumb < IndexCrumb
      def label
        "Spamurai Central"
      end

      def path_name
        :devtools_spamurai_path
      end
    end
  end
end
