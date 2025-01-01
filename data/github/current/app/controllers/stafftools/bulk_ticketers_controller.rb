# typed: true
# frozen_string_literal: true
class Stafftools::BulkTicketersController < StafftoolsController

  def show
    render "stafftools/bulk_ticketers/index", locals: {
      dmca_template: view.dmca_template,
    }
  end

  def create
    ticket_data, rejected, failed_lines = view.ticket_data_for_urls(params[:url_hits])
    render "stafftools/bulk_ticketers/built", locals: {
      cartridge: {
        action: "bulk-ticket",
        data: ticket_data,
        template: {
          subject: params[:subject_text],
          body: params[:body_text],
          tag: params[:tag_text],
        },
      },
      rejected: rejected,
      failed_lines: failed_lines,
    }
  end

  # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
  def view # rubocop:todo GitHub/UseRestfulActions # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @view ||= Stafftools::BulkTicketersView.new
  end
  # rubocop:enable GitHub/ControllersShouldUseMemoizeForMemoization
end
