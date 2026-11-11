# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class EnterpriseTeam < Connections::Base
      description "A list of enterprise teams owned by the enterprise."
      total_count_field
    end
  end
end
