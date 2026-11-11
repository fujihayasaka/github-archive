# typed: strict
# frozen_string_literal: true

# Provides a helper to check whether the GLB (Global Load Balancer) has
# activated DataDome for the current request. The GLB sets the GitHub-owned
# header X-GitHub-DataDome-Enabled BEFORE calling the DataDome API, so it
# survives DataDome API timeouts/errors (fail-open).
module DatadomeGlbGating
  extend ActiveSupport::Concern
  extend T::Helpers
  requires_ancestor { ApplicationController }

  included do
    T.bind(self, T.class_of(ApplicationController))
    helper_method :datadome_enabled_by_glb?
  end

  private

  # Returns true if the GLB matched this request to a DataDome path ACL and
  # the percentage flag was active. This header is set before the DataDome Lua
  # hook runs, so it is present even when the DataDome API times out.
  sig { returns(T::Boolean) }
  def datadome_enabled_by_glb?
    request.headers["HTTP_X_GITHUB_DATADOME_ENABLED"].present?
  end
end
