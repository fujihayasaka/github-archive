# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class CodeqlDatabase < Connections::Base
      total_count_field

      field :total_storage_size, Integer, description: "The total size used by all CodeQL databases.", null: false
      def total_storage_size
        unless self.class.viewer_is_site_admin?(context[:viewer], self.class.name)
          return nil
        end

        query = if @object.parent.is_a?(::Repository)
          ::CodeqlDatabase.where(repository_id: @object.parent.id)
        elsif @object.parent.is_a?(Platform::Models::AccountStafftoolsInfo)
          ::CodeqlDatabase.where(uploader_id: @object.parent.account.id)
        else
          raise Platform::Errors::Internal, "Unsupported object type: #{@object.parent.class.name}"
        end

        query.sum(:size)
      end
    end
  end
end
