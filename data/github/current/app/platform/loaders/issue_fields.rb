# typed: strict
# frozen_string_literal: true

module Platform
  module Loaders
    class IssueFields < Platform::Loader
      sig { params(org: Orgs::IOrganization, viewer: T.nilable(User)).returns(Promise[T::Array[Issues::IIssueField]]) }
      def self.load(org, viewer: nil)
        self.for(viewer).load(org)
      end

      sig { params(viewer: T.nilable(User)).void }
      def initialize(viewer = nil)
        @viewer = viewer
      end

      sig { params(orgs: T::Array[Orgs::IOrganization]).returns(T::Hash[Orgs::IOrganization, T::Array[Issues::IIssueField]]) }
      def fetch(orgs)
        fields = Issues.domain.issue_fields.by_organizations(orgs)

        # Preload :owner for all fields at once to avoid N+1 across orgs
        all_fields = fields.values.flatten
        ::ActiveRecord::Associations::Preloader.new(records: all_fields, associations: :owner).call if all_fields.any?

        results = {}
        orgs.each do |org|
          org_fields = fields[T.must(org.id)] || []
          if org_fields.any?
            results[org] = Issues.domain.issue_fields.filter_visible_pinned_fields(org_fields, viewer: @viewer)
          else
            results[org] = []
          end
        end

        results.to_h
      end
    end
  end
end
