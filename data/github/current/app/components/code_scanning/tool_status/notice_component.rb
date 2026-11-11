# typed: strict
# frozen_string_literal: true

class CodeScanning::ToolStatus::NoticeComponent < ApplicationComponent
  include ApplicationComponent::Rescuable

  rescue_from ActiveRecord::ActiveRecordError, with: :nothing

  sig { params(messages: CodeScanning::Status::Messages, repository: Repository).void }
  def initialize(messages:, repository:)
    @messages = messages
    @repository = repository
  end

  sig { returns(String) }
  def title
    case messages.overall_status
    when CodeScanning::Status::ATTENTION
      "Code scanning: one or more analysis tools are reporting problems"
    when CodeScanning::Status::DANGER
      "Code scanning configuration error"
    else
      # We expect to never show this since we should not be rendering in this case
      "Code scanning is working as expected"
    end
  end

  sig { returns(String) }
  def message
    messages.status_summary
  end

  sig { returns(T.nilable(Primer::Beta::Link)) }
  def tsp_url_and_link_text
    messages.error_link_component(@repository)
  end

  sig { returns(T::Boolean) }
  def render?
    return false if messages.nil?
    !messages.all_tools_successful?
  end

  sig { returns(String) }
  def call
    render(Primer::Alpha::Banner.new(
      scheme: banner_scheme,
      icon: banner_icon,
      my: 1,
      test_selector: "tsp-entry-banner"
    )) do
      link_details = tsp_url_and_link_text
      content = if link_details.nil?
        message
      else
        safe_join [
          message,
          " Check the ",
          render(link_details),
          " for help."
        ]
      end

      safe_join([
        content_tag(:strong, title),
        content_tag(:div, content)
      ])
    end
  end

  private

  sig { returns CodeScanning::Status::Messages }
  attr_reader :messages

  sig { returns(Symbol) }
  def banner_scheme
    case messages.overall_status
    when CodeScanning::Status::ATTENTION
      :warning
    when CodeScanning::Status::DANGER
      :danger
    else
      :default
    end
  end

  sig { returns(Symbol) }
  def banner_icon
    case messages.overall_status
    when CodeScanning::Status::ATTENTION
      :alert
    when CodeScanning::Status::DANGER
      :stop
    else
      :info
    end
  end
end
