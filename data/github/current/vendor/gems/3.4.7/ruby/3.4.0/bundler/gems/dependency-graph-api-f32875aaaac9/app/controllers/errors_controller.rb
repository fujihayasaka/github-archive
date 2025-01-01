class ErrorsController < ApplicationController
  # Create a SinkError class to be utilized for error reporting.
  class SinkError < RuntimeError; end

  # POST /errors
  def report_error
    exception = SinkError.new(params[:message])

    if params[:backtrace]
      exception.set_backtrace(params[:backtrace].split("\n"))
    end

    Failbot.report(exception) unless Rails.env.development?

    render plain: "OK"
  end
end
