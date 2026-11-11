# typed: strict
# frozen_string_literal: true

module ReactPartialHelper
  extend T::Helpers

  include React::TagDependency

  sig do
    params(
      name: String, # Name of the partial. Should match the directory name within react-partials
      props: T.nilable(T.any(T::Struct, T::Hash[Symbol, T.untyped])), # props to pass to the partial component
      ssr_hints: Alloy::SelectiveSsr::Hints,
      disable_ssr: T::Boolean, # Override Selective SSR and disable SSR
      force_ssr: T::Boolean, # Override Selective SSR and enable SSR
      class_name: T.nilable(String), # Additional css class/classes to add to the react-partial element
      origin: T.untyped # the request origin to use in the platform flow
    ).returns(T.untyped)
  end
  def render_react_partial(
    name: "",
    props: {},
    ssr_hints: Alloy::SelectiveSsr::Hints.new,
    disable_ssr: false,
    force_ssr: false,
    class_name: nil,
    origin: nil
  )
    React::PartialRenderer.new(
      controller: T.unsafe(self).controller,
      name: name,
      origin: origin,
      props: props,
      request: request,
      ssr_hints: ssr_hints,
      disable_ssr: disable_ssr,
      force_ssr: force_ssr,
      user: T.unsafe(current_user)
    ).render  do |ssr_response, embedded_data, attempted_ssr|
      render partial: "react/partial", locals: {
        name: name,
        attempted_ssr: attempted_ssr,
        ssr: ssr_response.success?,
        ssr_error_script_tag: html_safe_json_script_tag(ssr_response.error, "react-partial.ssrError"),
        data_script_tag: html_safe_json_script_tag(GitHub::JSON.dump(embedded_data), "react-partial.embeddedData"),
        react_root_tag: html_safe_react_root_tag(ssr_response.result, "react-partial.reactRoot"),
        class_name: class_name,
        profiling_mode_enabled: feature_enabled_globally_or_for_user?(subject: current_user, feature_name: :react_quality_profiling),
      }
    end
  end

  # Track performance of React partial replacements (vs Rails) in Datadog using a scientist-like interface.
  #
  # @param name [String] the name of the partial to replace with a React version.
  # @param react_enabled [Boolean] indicates whether to run the React or Rails code.
  #
  # Yields a React::FeatureTracking object. Executes the react block if react_enabled is true, otherwise executes the
  # rails block.
  #
  # Reports the rendering time to Datadog for either Rails and React, under the `react_partial_replacement.time` metric,
  # allowing performance comparisons between React and Rails implementations.
  #
  # Example:
  # <% react_partial_replacement(name: "merge-box", react_enabled: user&.feature_preview_enabled?(:mergebox_react_partial)) do |feature| %>
  #   <% feature.react do %>
  #     <%= render_react_partial :mergebox_partial %>
  #   <% end %>
  #   <% feature.rails do %>
  #     <%= do_whatever_rails_thing %>
  #   <% end %>
  # <% end %>
  #
  # Ensure correct usage of "<%= %>".
  # Metrics tags when react_enabled is true:
  # partial: "merge-box", is_react: true, staff: false, logged_in: false, controller: "pull_requests", action: "show"
  #
  # Metrics tags when react_enabled is false:
  # partial: "merge-box", is_react: false, staff: false, logged_in: false, controller: "pull_requests", action: "show"
  #
  # You also have an option to run this as a science experiment by setting the "experiment" param to true, which will
  # report the rendering time for both the React and Rails versions of the code under these metrics:
  # - `science.react_partial_replacement.time`
  # - `science.react_partial_replacement.cpu_time`
  #
  # Experiments can only be run when react_enabled is set to "true". This allows us to slowly ramp up the experiment
  # in small increments using the same feature flag that we use to ramp up react_enabled.
  sig { params(name: String, react_enabled: T::Boolean, experiment: T::Boolean, block: T.proc.params(feature: React::FeatureTracking).void).void }
  def react_partial_replacement(name: "", react_enabled: false, experiment: false, &block)
    feature = React::FeatureTracking.new
    yield feature

    if react_enabled
      timer = measure_partial_render_time { feature.react_behavior&.call }

      if experiment
        rails_timer = measure_partial_render_time { capture { feature.rails_behavior&.call } }

        report_react_partial_experiment_metric(name, timer.elapsed_ms, timer.elapsed_cpu_ms, partial_type: "react")
        report_react_partial_experiment_metric(name, rails_timer.elapsed_ms, rails_timer.elapsed_cpu_ms, partial_type: "rails")
      end
    else
      timer = measure_partial_render_time { feature.rails_behavior&.call }
    end

    report_react_partial_metric(name, react_enabled, timer.elapsed_ms, timer.elapsed_cpu_ms)
  end

  private

  sig { params(block: T.proc.returns(T.untyped)).returns(Timer) }
  def measure_partial_render_time(&block)
    timer = Timer.start
    result = yield
    timer.stop
    timer
  end

  # Report the elapsed time it took to render a partial to Datadog
  sig { params(name: String, react_enabled: T::Boolean, elapsed_ms: T.any(Integer, Float), elapsed_cpu_ms: T.any(Integer, Float)).void }
  def report_react_partial_metric(name, react_enabled, elapsed_ms, elapsed_cpu_ms)
    request_env = request.env
    partial_tags = [
      "staff:#{GitHub::TaggingHelper.is_staff?(request_env)}",
      "logged_in:#{GitHub::TaggingHelper.logged_in(request_env)}",
      "is_react:#{react_enabled}",
      "controller:#{GitHub::TaggingHelper.controller(request_env)}",
      "action:#{GitHub::TaggingHelper.action(request_env)}",
      "partial:#{name}",
    ]
    GitHub.dogstats.distribution("react_partial_replacement.time", elapsed_ms, tags: partial_tags)
    GitHub.dogstats.distribution("react_partial_replacement.cpu_time", elapsed_cpu_ms, tags: partial_tags)
  end

  sig { params(name: String, elapsed_ms: T.any(Integer, Float), elapsed_cpu_ms: T.any(Integer, Float), partial_type: String).void }
  def report_react_partial_experiment_metric(name, elapsed_ms, elapsed_cpu_ms, partial_type:)
    request_env = request.env
    partial_tags = [
      "staff:#{GitHub::TaggingHelper.is_staff?(request_env)}",
      "logged_in:#{GitHub::TaggingHelper.logged_in(request_env)}",
      "is_react:#{partial_type == "react"}",
      "controller:#{GitHub::TaggingHelper.controller(request_env)}",
      "action:#{GitHub::TaggingHelper.action(request_env)}",
      "partial:#{name}",
    ]
    GitHub.dogstats.distribution("science.react_partial_replacement.time", elapsed_ms, tags: partial_tags)
    GitHub.dogstats.distribution("science.react_partial_replacement.cpu_time", elapsed_cpu_ms, tags: partial_tags)
  end
end
