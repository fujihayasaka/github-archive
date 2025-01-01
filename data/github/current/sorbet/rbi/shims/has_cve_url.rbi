# typed: strict
# frozen_string_literal: true

module HasCVEUrl
  sig { returns(T.nilable(String)) }
  def cve_id; end
end
