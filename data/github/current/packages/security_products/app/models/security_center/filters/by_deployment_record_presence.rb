# typed: strict
# frozen_string_literal: true

require "github/security_center/logging_helper"

module SecurityCenter
  module Filters
    class ByDeploymentRecordPresence
      # Because of how the ToRepositoryIds class parses incoming filters like this one,
      # we expect an array with a single value "deployment" if the user has specified the
      # has:deployment filter. If the user has not specified has:deployment,
      # we expect an empty array.

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
        return rel if !is_valid?

        rel = where(rel)
        rel
      end

      sig { returns(T::Boolean) }
      def is_empty?
        @incl_filters.blank?
      end

      sig { returns(T::Boolean) }
      def is_valid?
        # Check that an unexpected value has not been passed in
        # we only expect the array to ever have one value: "deployment"
        !@incl_filters.nil? && @incl_filters.count == 1 && @incl_filters.first == "deployment"
      end

      private

      sig { params(rel: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
      def where(rel)
        org_ids = @organizations.map(&:id)
        repo_ids = ArtifactDeploymentRecord.repository_ids_for_owners(org_ids)

        rel.where(repository_id: repo_ids)
      end

      instrument_method \
        :where
    end
  end
end
