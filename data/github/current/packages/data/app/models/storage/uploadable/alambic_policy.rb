# typed: true
# frozen_string_literal: true

module Storage
  module Uploadable
    module AlambicPolicy
      def storage_alambic_url(policy)
        Storage.not_implemented!(policy, self, :storage_alambic_url)
      end

      def storage_uploadable_attributes
        {}
      end
    end
  end
end
