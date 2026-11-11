# typed: strict
# frozen_string_literal: true

# The shared businesses/_layout.html.erb renders TbbSetupBudgetBannerComponent
# which queries the InProductTargeting cluster. Controllers that declare
# depends_on_clusters get a fresh ClusterDependencies (not inherited from parent),
# so we inject InProductTargeting as an optional cluster when the controller has
# already opted in. Scoped to GET/HEAD since those are the only methods that
# render the layout.
#
# Include this concern in any controller that renders through
# businesses/_layout.html.erb and declares its own depends_on_clusters.
module Businesses::Concerns::BusinessLayoutClusterDependencies
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { ApplicationController }

  sig { returns(T.nilable(T::Array[T.class_of(ApplicationRecord::Base)])) }
  def optional_clusters
    base = super
    return base unless T.unsafe(self.class).cluster_dependencies
    return base unless request.get? || request.head?

    (base || []) | [ApplicationRecord::InProductTargeting]
  end
end
