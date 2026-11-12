# frozen_string_literal: true

module Middlewares
  class ReadReplica < Coach::Middleware
    def call
      ActiveRecord::Base.connected_to(role: :reading) do
        next_middleware.call
      end
    end
  end
end
