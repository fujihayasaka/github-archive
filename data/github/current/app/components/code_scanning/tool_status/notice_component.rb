# typed: strict
# frozen_string_literal: true

class CodeScanning::ToolStatus::NoticeComponent < ApplicationComponent
  include ApplicationComponent::Rescuable
  extend T::Sig

  rescue_from ActiveRecord::ActiveRecordError, with: :nothing

  sig { params(messages: CodeScanning::Status::Messages, repository: Repository).void }
  def initialize(messages:, repository:)
    @messages = messages
    @repository = repository
  end

  sig { returns(Symbol) }
  def level
    case messages.overall_status
    when CodeScanning::Status::ATTENTION
      :warning
    when CodeScanning::Status::DANGER
      :danger
    else
      :default
    end
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
    render(GitHub::FlashActionDismissibleComponent.new(
       level: level,
       is_dismissible: false,
       test_selector: "tsp-entry-banner",
       text_align: :left,
       display_icon: true,
       my: 1
     )) do |flash|
      flash.with_title do
        title
      end
      flash.with_text do
        link_details = tsp_url_and_link_text
        if link_details.nil?
          next message
        end

        safe_join [
          message,
          " Check the ",
          render(link_details),
          " for help."
        ]
      end
    end

  end

  private

  sig { returns CodeScanning::Status::Messages }
  attr_reader :messages
end
