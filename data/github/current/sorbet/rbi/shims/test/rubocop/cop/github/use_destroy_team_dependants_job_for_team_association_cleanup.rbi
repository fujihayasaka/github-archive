# typed: true

module RuboCop
  module Cop
    module GitHub
      class UseDestroyTeamDependantsJobForTeamAssociationCleanup < Base
        def dependent_destroy?(node); end
        def association_with_options?(node); end
        def using_destroy_dependents_in_background?(node); end
      end
    end
  end
end
