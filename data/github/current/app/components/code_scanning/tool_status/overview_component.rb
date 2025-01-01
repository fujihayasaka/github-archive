# typed: true
# frozen_string_literal: true

class CodeScanning::ToolStatus::OverviewComponent < ApplicationComponent
  attr_reader :current_repository

  sig do
    params(
      current_repository: Repository,
      tools: T::Enumerable[Turboscan::Proto::ToolStatus],
      messages: CodeScanning::Status::Messages,
    ).void
  end
  def initialize(current_repository:, tools:,  messages:)
    @current_repository = current_repository
    @tool_names = tools.map(&:name)
    @messages = messages
  end

  sig { returns(String) }
  def linked_tool
    @tool_names.detect { |tool_name| tool_name == "CodeQL" } || @tool_names.first
  end

  sig { returns(Integer) }
  def tools_count
    @tool_names.count
  end

  sig { returns(T::Boolean) }
  def has_configured_tools?
    tools_count > 0
  end

  sig { returns(T.nilable(Integer)) }
  def status
    @messages.overall_status
  end

  sig { returns(T.nilable(Primer::Beta::Link)) }
  def error_link_component
    @messages.error_link_component(@current_repository)
  end

  sig { returns(T.nilable(String)) }
  def status_text
    return unless has_configured_tools?

    @messages.status_summary
  end
end
