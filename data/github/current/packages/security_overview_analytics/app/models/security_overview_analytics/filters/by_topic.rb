# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Filters
    class ByTopic
      extend T::Sig
      include Filter

      sig do
        params(
          incl_filters: T.nilable(T::Array[String]),
          excl_filters: T.nilable(T::Array[String]),
          organizations: T::Array[::Organization],
        ).void
      end
      def initialize(incl_filters, excl_filters, organizations:)
        @incl_filters = incl_filters
        @excl_filters = excl_filters
        @organizations = organizations
      end

      sig { override.params(rel: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
      def apply(rel)
        rel = where(rel, @incl_filters) if @incl_filters.present?
        rel = where(rel, @excl_filters, neg: true) if @excl_filters.present?
        rel
      end

      sig { override.returns(T::Boolean) }
      def is_empty?
        @incl_filters.blank? && @excl_filters.blank?
      end

      sig { override.returns(T::Boolean) }
      def has_incl_filters?
        @incl_filters.present?
      end

      private

      sig do
        params(
          rel: ActiveRecord::Relation,
          filters: T::Array[String],
          neg: T::Boolean
        ).returns(ActiveRecord::Relation)
      end
      def where(rel, filters, neg: false)
        topic_ids = Topic.where(name: filters).pluck(:id)
        repo_ids = ::Repository.active.where(owner: @organizations)
          .joins(:repository_topics)
          .where(repository_topics:
            {
              state: ::RepositoryTopic.applied_state_values,
              topic_id: topic_ids
            }
          ).pluck(:id)
          .uniq

        if neg
          rel.where.not(repository_id: repo_ids)
        else
          rel.where(repository_id: repo_ids)
        end
      end
    end
  end
end
