# typed: strict
# frozen_string_literal: true

class Repos::Security::CWESectionItemComponent < ApplicationComponent

  extend T::Generic

  CWEInput = type_member { { fixed: T.any(CWE, Integer) } }

  sig { returns(CWEInput) }
  attr_reader :cwe

  sig { returns(T.nilable(String)) }
  attr_reader :alternative_header_link

  sig { returns(String) }
  attr_reader :test_selector

  sig { params(cwe: CWEInput, test_selector: String, alternative_header_link: T.nilable(String)).void }
  def initialize(cwe:, test_selector: "",  alternative_header_link: nil)
    @cwe = cwe
    @alternative_header_link = alternative_header_link
    @test_selector = test_selector
  end

  sig { returns(T.nilable(String)) }
  def fragment_path
    if cwe.is_a?(Integer)
      helpers.cwe_details_path(cwe)
    end
  end

  sig { returns(String) }
  def summary_text
    c = cwe
    if c.is_a?(Integer)
      "CWE-#{cwe}"
    else
      c.cwe_id
    end
  end

end
