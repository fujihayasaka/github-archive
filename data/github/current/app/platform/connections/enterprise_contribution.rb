# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class EnterpriseContribution < Connections::Base
      visibility :internal

      total_count_field description: "Identifies the total count of enterprise contributions across all enterprise installations."

      def total_count
        enterprise_contributions = @object.items
        enterprise_contributions.sum(&:contributions_count)
      end
    end
  end
end
