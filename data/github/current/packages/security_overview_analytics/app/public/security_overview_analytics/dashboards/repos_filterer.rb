# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module ReposFilterer
      extend T::Helpers
      include Kernel # For methods like `is_a?`, `class`, etc.
      interface!

      sig { abstract.params(repos_slice4: T.nilable(Integer)).returns(ActiveRecord::Relation) }
      def cs_repo_metadata_rel(repos_slice4: nil); end

      sig { abstract.params(repos_slice4: T.nilable(Integer)).returns(ActiveRecord::Relation) }
      def dbot_repo_metadata_rel(repos_slice4: nil); end

      sig { abstract.params(repos_slice4: T.nilable(Integer)).returns(ActiveRecord::Relation) }
      def ss_repo_metadata_rel(repos_slice4: nil); end

      sig { abstract.params(repos_slice4: T.nilable(Integer)).returns(ActiveRecord::Relation) }
      def any_feature_repo_metadata_rel(repos_slice4: nil); end

      sig { abstract.returns(T::Array[String]) }
      def applied_filters; end
    end
  end
end
