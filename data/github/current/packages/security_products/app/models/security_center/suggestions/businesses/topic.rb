# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Suggestions
    module Businesses
      class Topic < Base

        sig { returns(T::Array[Organization]) }; attr_reader :authorized_orgs

        sig { params(authorized_orgs: T::Array[Organization], kwargs: T.untyped).void }
        def initialize(authorized_orgs:, **kwargs)
          super(**T.unsafe(kwargs))
          @authorized_orgs = authorized_orgs
        end

        sig { override.returns(T::Array[Suggestion]) }
        memoize def suggestions
          return [] if authorized_orgs.blank?
          return [] if topic_ids.blank?

          topics_rel =
            ::Topic
              .select(:name, :short_description)
              .where(id: topic_ids)
              .order(:name)

          topics_rel = topics_rel.limit(limit) if limit.present?
          topics_rel = topics_rel.where.not(name: selected_values) if selected_values.present?
          topics_rel = topics_rel.where("name LIKE ?", "%#{value}%") if value.present?

          topics_rel.map do |topic|
            Suggestion.new(
              description: topic.short_description,
              value: topic.name
            )
          end
        end

        private

        sig { returns(T::Array[Integer]) }
        memoize def topic_ids
          ::RepositoryTopic
            .distinct
            .select(:repository_id, :topic_id)
            .joins(:repository)
            .where(
              "repositories.owner_id": authorized_orgs,
              state: ::RepositoryTopic.applied_state_values
            )
            .limit(1_000)
            .pluck(:topic_id)
        end
      end
    end
  end
end
