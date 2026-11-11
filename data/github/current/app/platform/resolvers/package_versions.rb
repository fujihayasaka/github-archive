# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class PackageVersions < Resolvers::Base
      type Connections.define(Objects::PackageVersion), null: false

      argument :include_deleted, Boolean, "Whether or not deleted versions will be included.", required: false, default_value: false, visibility: :internal
      argument :order_by, Inputs::PackageVersionOrder, "Ordering of the returned packages.", required: false,
          default_value: { field: "created_at", direction: "DESC" }

      def resolve(**arguments)
        return ArrayWrapper.new([]) if object.new_record?

        direction = arguments.dig(:order_by, :direction)
        direction ||= "DESC"

        versions = @object.package_versions.order("package_versions.id #{direction}")
        versions = versions.not_deleted unless arguments[:include_deleted]

        filter(versions, arguments)
      end

      protected

      def filter(versions, arguments)
        versions
      end
    end
  end
end
