# frozen_string_literal: true

module OutputHelpers
  def suppress_output
    original_stdout = $stdout
    $stdout = StringIO.new
    begin
      yield
    ensure
      $stdout = original_stdout
    end
  end

  def capture_output
    output = StringIO.new
    original_logger = Rails.logger
    Rails.logger = Logger.new(output)
    Rails.logger.level = Logger::DEBUG
    begin
      yield
    ensure
      Rails.logger = original_logger
    end
    output.string
  end
end
