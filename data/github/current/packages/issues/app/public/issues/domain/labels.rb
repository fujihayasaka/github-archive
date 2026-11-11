# typed: strict
# frozen_string_literal: true

module Issues
  class Domain
    class Labels < GH::Domain::Base
      # Public: Find labels for the given repository and having the given names
      sig { params(repository_id: Integer, names: T::Array[String]).returns(T::Array[Issues::ILabel]) }
      def by_repository_and_names(repository_id:, names:)
        ::Label.where(repository_id:).with_name(names).to_a
      end

      # Public: Finds labels for the given repository with the given IDs
      sig { params(repository_id: Integer, label_ids: T.nilable(T::Array[String])).returns(T::Array[Issues::ILabel]) }
      def by_repository_and_normalized_ids(repository_id:, label_ids: nil)
        return [] if label_ids.nil? || label_ids.empty?

        ids = []
        label_ids.each do |label_id|
          ids << label_id.to_i unless label_id.blank?
        end
        ids

        by_repository_and_ids(repository_id:, label_ids: ids)
      end

      private

      sig { params(repository_id: Integer, label_ids: T::Array[Integer]).returns(T::Array[Issues::ILabel]) }
      def by_repository_and_ids(repository_id:, label_ids:)
        ::Label.where(repository_id:).where(id: label_ids).to_a
      end
    end
  end
end
