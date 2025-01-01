# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module ReposFilterer
      extend T::Sig
      extend T::Helpers
      include Kernel # For methods like `is_a?`, `class`, etc.
      interface!

      sig { abstract.params(slice4: T.nilable(Integer)).returns(ActiveRecord::Relation) }
      def cs_repo_metadata_rel(slice4: nil); end

      sig { abstract.params(slice4: T.nilable(Integer)).returns(ActiveRecord::Relation) }
      def dbot_repo_metadata_rel(slice4: nil); end

      sig { abstract.params(slice4: T.nilable(Integer)).returns(ActiveRecord::Relation) }
      def ss_repo_metadata_rel(slice4: nil); end

      sig { abstract.params(slice4: T.nilable(Integer)).returns(ActiveRecord::Relation) }
      def any_feature_repo_metadata_rel(slice4: nil); end

      sig { abstract.returns(T::Boolean) }
      def filters_applied?; end

      sig do
        abstract.returns(
          T::Array[T.any(::SecurityOverviewAnalytics::Filters::Filter, ::SecurityCenter::Filters::ByCustomProperty)]
        )
      end
      def repo_metadata_filters; end
    end
  end
end
