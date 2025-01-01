# typed: true
# frozen_string_literal: true

class Repos::Security::CWESectionComponent < ApplicationComponent
  include HovercardHelper

  attr_reader :scheme

  # Supported schemes are :shield and :label
  # See https://github.com/github/security-products/issues/188 for standardising on one
  def initialize(cwe_numbers: [], show_no_cwes_message: false, scheme: :shield)
    @cwe_numbers = cwe_numbers
    @show_no_cwes_message = show_no_cwes_message
    @scheme = scheme
  end

  def render?
    @cwe_numbers.present? || @show_no_cwes_message
  end

  def cwe_id_from_number(number)
    "CWE-#{number}"
  end

  def mitre_link(number)
    CWE.mitre_link(number)
  end

  def hovercard_data_attributes(number)
    hovercard_data_attributes_for_cwe(id: number, hide_link: true)
  end

  def use_summary_discourse
    feature_enabled_globally_or_for_user?(feature_name: :cwe_summary_discourse)
  end
end
