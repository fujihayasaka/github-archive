# typed: strict
# frozen_string_literal: true

# This is a mixin that can be used to augment JobStatus objects with arbitrary context information.
#
# This is useful for when you need to track more than just the pending/success/error status of a job.
#
# USAGE:
#
#   class CustomJobStatus < JobStatus
#     include JobStatus::Context
#   end
#
#   status = CustomJobStatus.create
#   status.context = { error_details: ["Could not find project"] }
#   status.save
module JobStatus::Context
  extend T::Helpers

  requires_ancestor { JobStatus }

  sig { returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
  attr_accessor :context

  # Ideally this would be marked as `override`, but we cannot do so yet due to this bug:
  # https://github.com/sorbet/sorbet/issues/7110
  sig { params(attributes: T::Hash[T.untyped, T.untyped]).void }
  def initialize(attributes = {})
    super
    @context = T.let(attributes[:context], T.nilable(T::Hash[T.untyped, T.untyped]))
  end

  # Ideally this would be marked as `override`, but we cannot do so yet due to this bug:
  # https://github.com/sorbet/sorbet/issues/7110
  sig { returns(T::Hash[T.untyped, T.untyped]) }
  def as_json
    result = super
    result.merge!(context: @context) if @context.present?
    result
  end
end
