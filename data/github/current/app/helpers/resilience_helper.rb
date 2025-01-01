# typed: true
# frozen_string_literal: true

module ResilienceHelper
  extend T::Helpers

  include GitHub::ResilienceMixin

  # Getting a TypeError that references this line? You're probably trying to
  # use this helper outside the view layer, and you should use the
  # `GitHub::ResilienceMixin` instead.
  requires_ancestor { ActionView::Helpers::CaptureHelper }

  QUERY_TAG = "fallback:ResilienceHelper"

  HTML_ERB_OR_RB_EXTENSION = /(\.html\.erb)|(\.rb)\z/
  BACKTRACE_LINE_SUFFIX = /:.*/

  sig do
    params(
      allowed_error_types: T::Array[Class],
      excluded_error_types: T.nilable(T::Array[Class]),
      block: T.proc.void,
    ).returns(T.nilable(String)).checked(:always).on_failure(:raise)
  end
  def render_nothing_if_database_fails(allowed_error_types: GitHub::ResilienceMixin::DATABASE_ERROR_TYPES_ALLOWLIST, excluded_error_types: nil, &block)
    with_graceful_degradation_buffer do
      tag_queries do
        capture do
          yield
        end
      end
    end
  rescue StandardError => e # rubocop:todo Lint/GenericRescue
    graceful_error_handler = GracefulDegradationErrorHandler.new(e, allowed_errors: allowed_error_types, excluded_errors: excluded_error_types)

    Kernel.raise unless graceful_error_handler.degradable?

    graceful_error_handler.send_metrics("render_nothing_if_database_fails", @current_template)

    ""
  end

  sig { params(block: T.proc.void).returns(T.nilable(String)).checked(:always).on_failure(:raise) }
  def render_nothing_on_error(&block)
    with_graceful_degradation_buffer do
      tag_queries do
        capture do
          yield
        end
      end
    end
  rescue StandardError => e # rubocop:todo Lint/GenericRescue
    # We don't want to raise exceptions if a cluster is manually disabled.
    return "" if GitHub.disable_optional_clusters? && \
      e.is_a?(GitHub::DatabaseQueryDisabler::DatabaseDisabledError)

    # We don't want to hide exceptions in development/test environments
    Kernel.raise e if !Rails.env.production? &&
      !Thread.current.fetch(:skip_resilient_reraise, false) &&
      GitHub.environment["SKIP_RESILIENT_RERAISE"].blank?

    graceful_error_handler = GracefulDegradationErrorHandler.new(e, allowed_errors: [StandardError], excluded_errors: nil)
    graceful_error_handler.send_metrics("render_nothing_on_error", @current_template)

    ""
  end

  private

  sig do
    type_parameters(:T)
      .params(block: T.proc.returns(T.type_parameter(:T)))
      .returns(T.type_parameter(:T))
  end
  def tag_queries(&block)
    GitHub::MysqlInstrumenter.tag_queries(QUERY_TAG, &block)
  end
end
