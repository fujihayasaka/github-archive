# typed: strict
# frozen_string_literal: true

# Boot wiring for the nudge priority coordination framework.
#
# See ADR "Cross-Surface Nudge Priority Coordination"
# (github/in-product-messaging, docs/dev/adr/nudge-priority-coordination/).
#
# The coordinator is gated on the in_product_messaging_priority_coordinator
# feature flag (default off). Two pieces are wired up at boot regardless of the
# flag: the suppression-flush adapter registered below (a nil check per
# successful request) and the Hydro forwarder subscriptions in this package's
# config/instrumentation.
#
# The registry is NOT frozen from here. A boot hook (to_prepare /
# after_initialize) that called PriorityRegistry.freeze! would reference — and
# therefore autoload — the registry, the coordinator, and User during app boot,
# tripping the lazy-load guard (test/integration/environment_test.rb). Instead
# the registry freezes itself when its file is first loaded (lazily, post-boot);
# see PriorityRegistry.

# Boot-safe Rack adapter for the suppression flush. Registered here (not in
# config/application.rb) so the reference to the package's own middleware stays
# inside the package — the lib pseudo-package may not depend on application
# packages.
#
# This initializer runs during load_config_initializers, before the IPT package
# is autoloadable, so it cannot name an InProductTargeting constant at class-body
# time (that raises `uninitialized constant InProductTargeting`). This plain,
# immediately-defined adapter only references the package from inside `call`,
# resolved lazily at request time — when the package is loaded.
#
# `call` delegates to the single shared body
# InProductTargeting::SuppressionFlusher.flush_after, which is also what the
# unit-tested InProductTargeting::SuppressionFlushMiddleware calls, so the
# mounted adapter and the tested class cannot drift. Delegating to a module
# method (not a per-request middleware instance) keeps the disabled path at one
# constant lookup and a nil check, with no allocation.
class IpmSuppressionFlushAdapter
  sig { params(app: T.untyped).void }
  def initialize(app)
    @app = T.let(app, T.untyped)
  end

  sig { params(env: T::Hash[String, T.untyped]).returns(T.untyped) }
  def call(env)
    InProductTargeting::SuppressionFlusher.flush_after(@app, env)
  end
end

# Not mounted on GHES or Proxima, environments the coordination framework
# excludes (see the ADR).
unless GitHub.enterprise? || GitHub.multi_tenant_enterprise?
  Rails.application.config.middleware.use IpmSuppressionFlushAdapter
end
