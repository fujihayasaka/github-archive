# frozen_string_literal: true

module HealthService
  module V1
    class Handler
      def ping(_req, _env)
        time = Time.now.utc
        {
          msg: "Healthy at #{time}",
        }
      end
    end
  end
end
