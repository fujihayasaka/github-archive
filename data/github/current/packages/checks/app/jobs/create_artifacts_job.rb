# typed: true
# frozen_string_literal: true

class CreateArtifactsJob < ApplicationJob
  include GitHub::Tracing
  extend T::Sig

  queue_as :checks_create_artifacts

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  trace_method(
    :perform,
    span_attribute_extractor: -> (_instance, *_args, **kwargs) do
      {
        "gh.check_suite.id" => kwargs[:check_suite_id],
      }
    end
  )

  def perform(check_suite_id:, artifacts:)
    check_suite = CheckSuite.find_by!(id: check_suite_id)

    with_write do
      Checks::CreateArtifacts.call(
        check_suite: check_suite,
        artifacts: artifacts,
      )
    end
  end
end
