# typed: true
# frozen_string_literal: true

module GitHub
  module Middleware
    class ClusterDisabler
      def initialize(app)
        @app = app
      end

      def call(env)
        request = Rack::Request.new(env)
        return @app.call(env) unless request.GET.has_key?("disable_clusters")
        return @app.call(env) unless GitHub::StaffOnlyCookie.read(request.cookies) || Rails.env.development?

        clusters_to_disable = request.GET["disable_clusters"].split(",").map do |cluster_name|
          begin
            cluster_name.constantize
          rescue NameError
            nil
          end
        end.compact

        ActiveRecord::Base.disable_queries_to_databases(clusters_to_disable) do
          @app.call(env)
        end
      end
    end
  end
end
