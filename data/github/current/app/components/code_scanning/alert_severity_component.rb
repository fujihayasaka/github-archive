# typed: true
# frozen_string_literal: true

class CodeScanning::AlertSeverityComponent < ApplicationComponent
  # NB the parameters are symbols, not enum values like
  # ::Turboscan::Proto::RuleSeverity::WARNING
  #
  # large_label defaults to true as that is what the SecurityShowPageComponent needs
  # in its use of this component for a component slot. We can't set these parameters
  # for every user of that component slot - they'd all have to do it explicitly.
  def initialize(severity:, security_severity:, filter_url: nil, large_label: true, additional_classes: "")
    @active_severity = if security_severity.nil? || security_severity == :NO_SECURITY_SEVERITY
      severity
    else
      security_severity
    end
    @active_severity = nil if @active_severity == :NONE
    @url = filter_url
    @large_label = large_label
    @additional_classes = additional_classes
  end

  def render?
    @active_severity.present?
  end

  def subclass
    display_info_hash[:subclass]
  end

  def octicon
    display_info_hash.fetch(:octicon, nil)
  end

  def label_text
    @active_severity.to_s.capitalize
  end

  private

  def display_info_hash
    case @active_severity
    # Security severities
    when :LOW
      {
        subclass: "Label--secondary",
      }
    when :MEDIUM
      {
        subclass: "Label--warning",
      }
    when :HIGH
      {
        subclass: "Label--orange",
      }
    when :CRITICAL
      {
        subclass: "Label--danger",
      }
    # Rule severities
    when :NOTE
      {
        subclass: "Label--secondary",
        octicon: {
          octicon: "note",
          color: :default
        }
      }
    when :WARNING
      {
        subclass: "Label--secondary",
        octicon: {
          octicon: "alert",
          color: :attention
        }
      }
    when :ERROR
      {
        subclass: "Label--secondary",
        octicon: {
          octicon: "circle-slash",
          color: :danger
        }
      }
    else
      {
        subclass: "Label--secondary",
      }
    end
  end
end
