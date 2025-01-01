# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class PackageFiles < Resolvers::Base

      type Connections.define(Objects::PackageFile), null: false

      argument :order_by, Inputs::PackageFileOrder, "Ordering of the returned package files.",
        required: false, default_value: { field: "created_at", direction: "ASC" }

      def resolve(**rest)
        direction = rest.dig(:order_by, :direction)
        direction ||= "ASC"

        files = @object.files.uploaded.scoped
        files = files.order("package_files.created_at #{direction}")

        filter(files, rest)
        files
      end

      protected

      def filter(files, arguments)
        files
      end
    end
  end
end
