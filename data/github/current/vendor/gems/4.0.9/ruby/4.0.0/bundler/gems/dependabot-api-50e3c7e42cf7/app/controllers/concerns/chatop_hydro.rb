# frozen_string_literal: true

require "terminal-table"

module ChatopHydro
  extend ActiveSupport::Concern

  FIDO_PROTECTED_ACTIONS = %i(hydro_pause hydro_resume).freeze

  # rubocop:disable Metrics/BlockLength
  included do
    before_action :require_fido_2fa, only: FIDO_PROTECTED_ACTIONS

    chatop :hydro_status,
           /hydro[-_]status/,
           "hydro-status - Show the status of Hydro processors" do
      processors = ProcessorManager.current_status
      table = Terminal::Table.new do |t|
        t.headings = %w(Processor Status)
        t.rows = processors
        t.align_column(1, :right)
        t.style = { border_top: false, border_bottom: false }
      end
      jsonrpc_success(["```", table.to_s, "```"].join("\n"))
    end

    chatop :hydro_pause,
           /hydro[-_]pause\s+(?<processor>\w+)/,
           "hydro-pause HANDLER - Pause hydro consumption in dependabot-api" do
      processor = jsonrpc_params[:processor]
      unless ProcessorManager.processor_exists?(processor)
        jsonrpc_failure "Didn't recognise the hydro processor, "\
                        "must be one of: "\
                        "#{ProcessorManager.processor_slug_list.join(', ')}"
        return
      end

      prev_state = ProcessorManager.paused?(processor)
      ProcessorManager.pause(processor)

      state = !prev_state ? "Paused" : "Already paused"
      jsonrpc_success "#{state} work on app: dependabot-api, "\
                      "hydro processor: #{processor}"
    end

    chatop :hydro_resume,
           /hydro[-_]resume\s+(?<processor>\w+)/,
           "hydro-resume HANDLER - "\
           "Resume hydro consumption in dependabot-api" do
      processor = jsonrpc_params[:processor]
      unless ProcessorManager.processor_exists?(processor)
        jsonrpc_failure "Didn't recognise the hydro processor, "\
                        "must be one of: "\
                        "#{ProcessorManager.processor_slug_list.join(', ')}"
        return
      end

      prev_state = ProcessorManager.paused?(processor)
      ProcessorManager.resume(processor)

      state = prev_state ? "Resumed" : "Already resumed"
      jsonrpc_success "#{state} work on app: dependabot-api, "\
                      "hydro handler: #{processor}"
    end
  end
  # rubocop:enable Metrics/BlockLength
end
