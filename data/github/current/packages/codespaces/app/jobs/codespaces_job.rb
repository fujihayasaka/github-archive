# typed: true
# frozen_string_literal: true

class CodespacesJob < ApplicationJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
  CLIENT_TIMEOUTS = { open_timeout: 2, timeout: 60 }.freeze

  queue_as :kubernetes_codespaces # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit

  before_enqueue { throw(:abort) unless GitHub.codespaces_enabled? }

  around_perform do |_job, block|
    Codespaces::Client.with_timeouts(CLIENT_TIMEOUTS, &block)
  end

  def self.perform_after_waiting_period(waiting_period:, **kwargs)
    set(wait: waiting_period).perform_later(**kwargs)
  end

  def stats_tags
    first_arg = arguments.first
    return [] unless first_arg

    # allow for codespace as first arg or in kwargs hash
    codespace = if first_arg.is_a?(Codespace)
      first_arg
    elsif first_arg.respond_to?(:fetch)
      first_arg.fetch(:codespace, nil)
    end

    vscs_target = first_arg.fetch(:vscs_target, nil) if first_arg.respond_to?(:fetch)

    return [] unless codespace || vscs_target

    Codespaces::StatsTagger.new(
      codespace: codespace,
      vscs_target: vscs_target,
    ).datadog_tags
  end
end
