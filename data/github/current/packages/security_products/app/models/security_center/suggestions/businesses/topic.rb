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

          ::Topic
            .select(:name, :short_description)
            .where(id: topic_ids)
            .then do |rel|
              next rel unless selected_values.present?
              rel.where.not(name: selected_values)
            end
            .then do |rel|
              next rel unless value.present?
              rel.where("name LIKE ?", "%#{value}%")
            end
            .then do |rel|
              next rel.order(:name) unless value.present?
              # This puts exact matches first, then sorts by name ASC
              # e.g. ORDER BY `topics`.`name` = $value DESC, `topics`.`name` ASC
              exact_match = ::Topic.arel_table[:name].eq(value)
              rel.order(Arel::Nodes::Descending.new(exact_match)).order(:name)
            end
            .limit(limit)
            .map do |topic|
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
