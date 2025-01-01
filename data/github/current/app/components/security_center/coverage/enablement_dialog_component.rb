# typed: true
# frozen_string_literal: true

module SecurityCenter
  module Coverage
    class EnablementDialogComponent < ApplicationComponent
      extend T::Sig

      class Data < T::Struct
        const :repo_id, Integer
        const :repo_name, String
        const :repo_visibility, String
        const :risk_url, String
        const :turbo_frame_src, String
        const :is_advisory_workspace, T::Boolean
      end

      delegate \
        :repo_id,
        :repo_name,
        :repo_visibility,
        :risk_url,
        :turbo_frame_src,
        :column_width,
        :is_advisory_workspace,
        to: :@data

      sig { params(data: Data).void }
      def initialize(data)
        @data = data
      end
    end
  end
end
