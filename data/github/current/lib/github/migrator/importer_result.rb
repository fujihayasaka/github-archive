# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class ImporterResult
      attr_reader :model, :warning

      def initialize(model, warning: nil)
        @model   = model
        @warning = warning
      end

      def success?
        model.present?
      end
    end
  end
end
