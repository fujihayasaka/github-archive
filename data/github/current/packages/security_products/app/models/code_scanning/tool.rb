# typed: strict
# frozen_string_literal: true

module CodeScanning
  module Tool
    extend T::Sig

    sig { returns(String) }
    def self.default_tool_name
      "CodeQL"
    end

    sig { params(name: String).returns(String) }
    def self.canonical_name(name)
      case name.downcase
      when "codeql command-line toolchain" then "CodeQL"
      when "golang security checks by gosec" then "gosec"
      when "security audit for python by bandit" then "bandit"
      else name
      end
    end
  end
end
