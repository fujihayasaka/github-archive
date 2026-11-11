# typed: strict
# frozen_string_literal: true

module InProductTargeting
  # Typed context passed to nudge eligibility and `on_win:` procs.
  #
  # Each page coordinated by InProductTargeting::PageNudgeCoordinator declares
  # a subclass carrying the inputs its eligibility procs rely on (for example
  # `const :organization, ::Organization` for org overview), so a missing
  # input is a Sorbet error at the registration site rather than a nil
  # dereference inside an eligibility proc at request time.
  #
  # See ADR "Cross-Surface Nudge Priority Coordination" Step 2.5
  # (github/in-product-messaging, docs/dev/adr/nudge-priority-coordination/).
  #
  # This inherits from T::InexactStruct rather than T::Struct because
  # sorbet-runtime forbids subclassing a T::Struct subclass, and page contexts
  # are exactly such a hierarchy.
  #
  # Props should be value-comparable (carry a meaningful `==`):
  # PageNudgeCoordinator compares two call sites' contexts prop-by-prop with
  # `==` to warn when they disagree within a request. A reference-identity-only
  # prop weakens that diagnostic (it can silently match differing contexts). The
  # comparison is best-effort and never affects which nudges render, so this is
  # a guideline for clean telemetry, not a hard requirement.
  #
  # No production page subclasses exist yet. They are added when each page is
  # migrated onto the coordinator (per the ADR rollout), behind that page's
  # own feature flag.
  class PageContext < T::InexactStruct
    extend T::Helpers

    abstract!
  end
end
