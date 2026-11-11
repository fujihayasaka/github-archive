# typed: strict
# frozen_string_literal: true

require "github/security_center/logging_helper"

module SecurityCenter
  module Filters
    class ByArtifactRegistry
      include GitHub::SecurityCenter::LoggingHelper

      sig do
        params(
          incl_filters: T.nilable(T::Array[String]),
          organizations: T::Array[Organization]
        ).void
      end
      def initialize(incl_filters, organizations:)
        @incl_filters = incl_filters
        @organizations = organizations
      end

      sig { params(rel: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
      def apply(rel)
        return rel if is_empty?
        return rel if GitHub.single_tenant_enterprise?
        return rel.none if @organizations.empty?

        if @incl_filters.nil?
          return rel
        end

        valid_filters = @incl_filters.filter do |f|
          ArtifactStorageRecord::SOURCE_REGISTRIES.include?(f)
        end
        if valid_filters.empty?
          return rel.none
        end
        rel = where(rel, valid_filters)

        rel
      end

      sig { returns(T::Boolean) }
      def is_empty?
        @incl_filters.blank?
      end

      private

      sig do
        params(
          rel: ActiveRecord::Relation,
          filters: T::Array[String]
        ).returns(ActiveRecord::Relation)
      end
      def where(rel, filters)
        org_ids = @organizations.map(&:id)
        repo_ids = ArtifactStorageRecord.repository_ids_for_owners_and_registries(org_ids, filters)
        rel.where(repository_id: repo_ids)
      end

      instrument_method \
        :where
    end
  end
end
