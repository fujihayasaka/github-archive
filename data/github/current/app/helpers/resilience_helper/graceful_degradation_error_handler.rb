# typed: strict
# frozen_string_literal: true

module ResilienceHelper
  # Helper class for error-related functionality for graceful degradation
  class GracefulDegradationErrorHandler
    FAILBOT_REPORTING_DENYLIST = [
      GitHub::RequestDurationManager::TimeBudgetIsOverError,
    ]
    Template = T.type_alias { T.any(ActionView::Template, ViewComponent::Base, ViewComponent::Template) }

    sig { params(error: Object, error_types: T.nilable(T::Array[T::Class[T.anything]])).returns(T::Boolean) }
    def self.is_error_type?(error, error_types)
      !!(error_types.present? && error_types.any? { |klass| error.is_a?(klass) })
    end

    sig { params(error: Exception, allowed_errors: T.nilable(T::Array[T::Class[T.anything]]), excluded_errors: T.nilable(T::Array[T::Class[T.anything]])).void }
    def initialize(error, allowed_errors:, excluded_errors:)
      @error = error
      @allowed_errors = allowed_errors
      @excluded_errors = excluded_errors
    end

    sig { returns(T::Boolean) }
    def degradable?
      # error isn't allowed if excluded_error_types includes the error's class
      return false if GracefulDegradationErrorHandler.is_error_type?(@error, @excluded_errors)

      # error also isn't allowed if allowed_error_types is empty or it doesn't
      # include the error's class
      GracefulDegradationErrorHandler.is_error_type?(@error, @allowed_errors)
    end

    sig { returns(T.nilable(T::Class[T.anything])) }
    def allowed_error_type
      @allowed_errors&.find { |klass| @error.is_a?(klass) }
    end

    sig { params(source_method: String, current_template: T.nilable(Template)).void }
    def send_metrics(source_method, current_template)
      Failbot.report(@error) unless FAILBOT_REPORTING_DENYLIST.any? { |error_type| @error.instance_of?(error_type) }

      GitHub::GracefulDegradationInstrumenter.track_handled_exception(@error)

      # Exceptions raised from an ActiveRecord adapter contain a connection pool that we can reference for DB info.
      pool = @error.try(:connection_pool)

      tags = [
        "root_error:#{@error.class.name}",
        "matched_error_type:#{allowed_error_type&.name || "nil"}",
        "resilience_method:#{source_method}",
        "view_template:#{most_recent_view_template(current_template) || "nil"}",
        "#{GitHub::TaggingHelper::CONTROLLER_TAG}:#{GitHub.context[:controller] || "unknown"}",
        "#{GitHub::TaggingHelper::ACTION_TAG}:#{GitHub.context[:controller_action] || "unknown"}",
        "#{GitHub::TaggingHelper::CATALOG_SERVICE_TAG}:#{GitHub.context[:catalog_service] || "unknown"}",
        "#{GitHub::TaggingHelper::DATABASE_CLUSTER_TAG}:#{pool ? pool.connection_class.name.demodulize : "unknown"}",
        "#{GitHub::TaggingHelper::DATABASE_CONNECTION_ROLE_TAG}:#{pool ? pool.role.to_s : "unknown"}",
      ]

      GitHub.dogstats.increment("request.resilience.caught_errors", tags: tags)
    end

    sig { params(current_template: T.nilable(Template)).returns(T.nilable(String)) }
    def most_recent_view_template(current_template)
      return nil if current_template.nil?
      return current_template.class.name if current_template.is_a?(ViewComponent::Base)
      return current_template.path if current_template.is_a?(ViewComponent::Template)

      if current_template.is_a?(ActionView::Template)
        template_backtrace_line = @error.backtrace&.find { |line| line =~ /#{Rails.root + "app/views"}/ }
        return nil if template_backtrace_line.nil?

        template_path = Pathname.new(template_backtrace_line.sub(BACKTRACE_LINE_SUFFIX, "")).relative_path_from(Rails.root).to_s
        return template_path.sub(HTML_ERB_OR_RB_EXTENSION, "")
      end

      begin
        # Fail a static type check for an unhandled Template type
        T.absurd(current_template)
      rescue TypeError => e
        # Don't explode at runtime for an unknown template type
        Failbot.report(e)
        nil
      end
    end
  end
end
