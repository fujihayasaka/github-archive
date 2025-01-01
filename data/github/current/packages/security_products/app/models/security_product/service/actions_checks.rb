# typed: true
# frozen_string_literal: true

# This module augments a Service with helper methods to lazily instantiate or assign a
# SecurityProductsEnablement::Actions::RunnerChecker object to check the repository's
# available runner pool.
#
# Not all SecurityProduct::Service objects require this capability so it is not part
# of the base class. This ensures that we explicitly call out those that have a
# dependency by including this module.
module SecurityProduct
  class Service
    module ActionsChecks
      extend ActiveSupport::Concern

      # This method is used by the SecurityProduct::Service manager to inject a runner checker
      # that has been 'warmed' with previous requests for the repository.
      def actions_runner_checker=(checker)
        Kernel.raise ArgumentError, "SecurityProductsEnablement::Actions::RunnerChecker already assigned" if defined?(@actions_runner_checker)
        Kernel.raise ArgumentError, "SecurityProductsEnablement::Actions::RunnerChecker is for a different repository" unless @repository.id == checker.repository.id

        @actions_runner_checker = checker
      end

      # This method will lazy-instantiate a runner checker if one has not been set by the caller, so we cannot use
      # GitHub::Memoizer for this - we _must always_ check if the instance variable has been created via the setter
      # before creating and memoizing a new instance.
      def actions_runner_checker
        return @actions_runner_checker if defined?(@actions_runner_checker)

        @actions_runner_checker = SecurityProductsEnablement::Actions::RunnerChecker.new(@repository)
      end
    end
  end
end
