# typed: false
# frozen_string_literal: true

module Platform
  module Interfaces
    module RawBlobUrl
      include Platform::Interfaces::Base
      description "Represents the raw blob url for a tree entry."


      mobile_only true

      field :url, Scalars::URI, description: "The URL to this file.", null: true

      def url
        @object.repository.async_default_branch.then do |default_branch|
          root_commit_arguments = context.scoped_context[:root_commit_arguments]
          committish = if root_commit_arguments
            root_commit_arguments[:expression] || root_commit_arguments[:oid]
          else
            default_branch
          end

          TreeEntryRenderHelper.raw_blob_url(
            @context[:viewer],
            @object.repository,
            committish,
            @object.path,
            expires_key: :blob,
          )
        end
      end
    end
  end
end
