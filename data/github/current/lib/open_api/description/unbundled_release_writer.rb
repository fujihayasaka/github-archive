# typed: true
# frozen_string_literal: true

module OpenApi
  module Description
    class UnbundledReleaseWriter < ReleaseWriter
      GENERATED_COMMENT = "# This file was automatically generated. There is no need to modify it manually."

      def path(format: :json)
        @base_path.join(@release.filename)
      end

      delegate :content, to: :@release

      private

      def serialize(content, format:)
        GENERATED_COMMENT + "\n" + YAML.dump(content)
      end
    end
  end
end
