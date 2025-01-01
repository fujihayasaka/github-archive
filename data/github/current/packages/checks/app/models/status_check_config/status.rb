# typed: true
# frozen_string_literal: true

class StatusCheckConfig::Status
  include ActiveModel::Model

  attr_writer :verb,
    :adjective,
    :sort_order,
    :status_icon_color_class

  attr_accessor :enum,
    :state,
    :sentence_for_status,
    :icon,
    :status_sentence_color_class,
    :check_sentence_color_class,
    :check_description,
    :sentence_for_check,
    :sentence_for_job

  def is?(comparator_enum)
    enum == comparator_enum
  end

  def adjective
    @adjective || enum.try(:humanize, capitalize: false)
  end

  def verb
    @verb || enum.try(:humanize, capitalize: false)
  end

  def sort_order
    @sort_order || 0
  end

  def pending?
    state.to_s.casecmp?(StatusCheckConfig::States::PENDING)
  end

  def incomplete?
    state.to_s.casecmp?(StatusCheckConfig::States::INCOMPLETE)
  end

  def success?
    state.to_s.casecmp?(StatusCheckConfig::States::SUCCESS)
  end

  def failure?
    state.to_s.casecmp?(StatusCheckConfig::States::FAILURE)
  end

  def failure_or_incomplete?
    failure? || incomplete?
  end

  def status_icon_color_class
    @status_icon_color_class
  end
end
