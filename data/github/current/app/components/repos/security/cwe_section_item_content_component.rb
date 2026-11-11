# typed: strict
# frozen_string_literal: true

class Repos::Security::CWESectionItemContentComponent < ApplicationComponent

  sig { returns(CWE) }
  attr_reader :cwe

  sig { returns(T.nilable(String)) }
  attr_reader :alternative_header_link

  sig { params(cwe: CWE, alternative_header_link: T.nilable(String)).void }
  def initialize(cwe:, alternative_header_link: nil)
    @cwe = cwe
    @alternative_header_link = alternative_header_link
  end

  sig { returns String }
  def header_link
    alternative_header_link || mitre_link
  end

  sig { returns String }
  def mitre_link
    cwe.mitre_link
  end
end
