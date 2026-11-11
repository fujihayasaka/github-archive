# typed: strict
# frozen_string_literal: true

# Wraps an IssueFieldOption with a reference to the pre-loaded parent IssueField.
#
# This wrapper is used in two scenarios:
#   1. IssueFieldSingleSelect#options (sub-field): the parent field is already owner-preloaded
#      by Platform::Loaders::IssueFields, so no extra DB work is needed.
#   2. IssueFieldSingleSelectOption.load_from_global_id (direct node lookup): the parent field
#      is loaded async and its :owner is preloaded before the wrapper is created.
#
# In both cases the wrapper exposes async_owner via the already-loaded field owner, avoiding
# direct AR association loads that are refused inside GraphQL execution.
class Platform::Models::IssueFieldOptionWithFieldContext
  # Delegate missing methods (id, name, description, color, priority, …) to the raw option.
  delegate_missing_to :@object

  # The parent IssueField (potentially an IssueFieldWithRepoContext) with :owner preloaded.
  # Both IssueField and IssueFieldWithRepoContext now formally implement Issues::IIssueField.
  sig { returns(Issues::IIssueField) }
  attr_reader :field

  sig { returns(IssueFieldOption) }
  attr_reader :object

  sig { params(object: IssueFieldOption, field: Issues::IIssueField).void }
  def initialize(object, field:)
    @object = object
    @field  = field
  end

  # Return the org owner via the parent field's async_owner, which respects the platform
  # loader and avoids direct AR association loads inside GraphQL execution. When the field
  # already has :owner preloaded (e.g. from Platform::Loaders::IssueFields) the async call
  # returns immediately without an extra query.
  sig { returns(::Promise[T.untyped]) }
  def async_owner
    T.unsafe(@field).async_owner
  end
end
