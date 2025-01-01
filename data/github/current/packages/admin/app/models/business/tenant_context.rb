# typed: strict
# frozen_string_literal: true

# This interface allows a model to declare that it can be scoped to a particular Proxima tenant.
module Business::TenantContext
  extend T::Sig
  extend T::Helpers

  interface!

  # Returns the tenant to which this model should be scoped.
  #
  # This method can be used to encapsulate the logic for setting the current Proxima tenant. For example, a background
  # job might call this method from the `ActiveJob.resolve_tenant_context` hook in order to set the tenant context in
  # which the job should run.
  sig { abstract.returns(T.nilable(Business)) }
  def resolve_tenant; end
end
