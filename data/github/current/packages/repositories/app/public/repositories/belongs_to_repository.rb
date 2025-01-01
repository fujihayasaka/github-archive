# typed: strict
# frozen_string_literal: true

module Repositories
  module BelongsToRepository
    extend T::Helpers

    requires_ancestor { ActiveRecord::Base }

    abstract!

    sig { abstract.returns(T.nilable(Integer)) }
    def repository_id; end

    sig { params(base: Module).void }
    def self.included(base)
      base.include GH::Associations::BatchMethodAdapters
      base.extend GH::Domain::CallerService
      super
    end

    module ClassMethods
      extend T::Helpers

      sig { params(options: T::Hash[Symbol, T.untyped]).void }
      def belongs_to_repository_via_domain(options = {})
        feature_flag = options.delete(:feature_flag)
        return_type = options.delete(:return_type) || T.nilable(::Repositories::IRepository)

        T.bind(self, T.class_of(ActiveRecord::Base))
        belongs_to :repository, **options

        T.unsafe(self).belongs_to_domain(:repository, foreign_key: :repository_id, return_type:, feature_flag:, ar_relation: true) do |repository_ids|
          if repository_ids.length == 1
            # This conditional behavior allows better sql matching (LIMIT 1) with existing `find_by` calls leading
            # to more cache hits on the Rails SQL cache in our current hybrid state.
            [Repositories.domain.by_id(repository_ids.first)].compact
          else
            Repositories.domain.by_ids(repository_ids, allow_deleted: true)
          end
        end
      end
    end

    mixes_in_class_methods(ClassMethods)
  end
end
