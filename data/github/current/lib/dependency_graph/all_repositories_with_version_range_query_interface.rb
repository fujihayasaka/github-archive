# typed: strict
# frozen_string_literal: true

# DependencyGraph API and Dependency Graph Platform both provide this interface to VulnerableVersionRangeAlerter
# with the former being the legacy service and the latter the replacement.
#
# This interface is used to make sure we don't drift from the expected contract in the replacement implementation.
module DependencyGraph
  module AllRepositoriesWithVersionRangeQueryInterface
    extend T::Helpers
    interface!

    # It is expected that this method caches the remote service response when called and any further calls to the
    # interface for alertable dependents or cursor values will not trigger network calls under any circumstances.
    sig { abstract.void }
    def execute_query! ; end

    sig { abstract.returns(T::Array[DependencyGraph::Alerting::AlertableDependent]) }
    def alertable_dependents; end

    sig { abstract.returns(T.nilable(String)) }
    def last_cursor ; end

    sig { abstract.returns(T.nilable(String)) }
    def dependent_end_cursor; end

    sig { abstract.returns(T.nilable(T::Boolean)) }
    def has_next?; end
  end
end
