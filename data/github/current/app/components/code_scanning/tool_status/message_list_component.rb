# typed: true
# frozen_string_literal: true

class CodeScanning::ToolStatus::MessageListComponent < ApplicationComponent
  attr_reader :messages

  include ActionView::Helpers::TextHelper

  sig do
    params(
      messages: T::Array[::CodeScanning::Status::Error],
    ).void
  end
  def initialize(messages:)
    @messages = messages
  end

  def count_message
    suggestions = messages.count { |m| m.level == CodeScanning::Status::SUCCESS }
    warnings = messages.count { |m| m.level == CodeScanning::Status::ATTENTION }
    errors = messages.count { |m| m.level == CodeScanning::Status::DANGER }
    counts = []
    counts << pluralize(errors, "error") unless errors.zero?
    counts << pluralize(warnings, "warning") unless warnings.zero?
    counts << pluralize(suggestions, "suggestion") unless suggestions.zero?
    counts.to_sentence
  end

  def working_as_expected?
    messages.empty? || messages.all? { |m| m.level == CodeScanning::Status::SUCCESS }
  end

  class Icon < Primer::Beta::Octicon
    def self.octicon_kwargs_for(level:)
      case level
      when CodeScanning::Status::DANGER then { icon: "x-circle-fill", color: :danger, test_selector: "status-danger" }
      when CodeScanning::Status::ATTENTION then { icon: "alert-fill", color: :attention, test_selector: "status-attention" }
      when CodeScanning::Status::SUCCESS then { icon: "light-bulb", color: :muted, test_selector: "status-success" }
      else { icon: "question", color: :muted, test_selector: "status-question" }
      end
    end

    def initialize(level:, **kwargs)
      super(**Icon::octicon_kwargs_for(level: level), **kwargs)
    end
  end
end
