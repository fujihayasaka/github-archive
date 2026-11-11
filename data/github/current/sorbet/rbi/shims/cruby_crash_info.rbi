# typed: true
# frozen_string_literal: true

module CRubyCrashInfo
  sig { returns(String) }
  def self.info; end

  sig { params(info: String).returns(String) }
  def self.info=(info); end
end
