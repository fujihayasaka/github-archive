# typed: strict
# frozen_string_literal: true

module Platform
  module Loaders
    class IssueFields < Platform::Loader
      sig { params(org: Orgs::IOrganization).returns(Promise[T::Array[Issues::IIssueField]]) }
      def self.load(org)
        self.for.load(org)
      end

      sig { params(orgs: T::Array[Orgs::IOrganization]).returns(T::Hash[Orgs::IOrganization, T::Array[Issues::IIssueField]]) }
      def fetch(orgs)
        fields = Issues.domain.issue_fields.by_organizations(orgs)
        results = {}
        orgs.each do |org|
          if fields[T.must(org.id)]
            results[org] = fields[T.must(org.id)]
          else
            results[org] = []
          end
        end

        results.to_h
      end
    end
  end
end
