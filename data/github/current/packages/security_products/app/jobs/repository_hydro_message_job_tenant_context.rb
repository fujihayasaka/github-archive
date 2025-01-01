# typed: strict
# frozen_string_literal: true

module RepositoryHydroMessageJobTenantContext
  extend T::Helpers
  abstract!

  # This mixin can only be included in classes that extend HydroMesageJob.
  requires_ancestor { HydroMessageJob }

  sig { params(base: Module).void }
  def self.included(base)
    T.unsafe(base).resolve_tenant_context do |_, job|
      next if job.repository_id.zero? || job.repository_id.nil?
      ::Repositories::Public.resolve_tenant(id: job.repository_id)
    end
  end

  sig { abstract.returns(Integer) }
  def repository_id; end
end
