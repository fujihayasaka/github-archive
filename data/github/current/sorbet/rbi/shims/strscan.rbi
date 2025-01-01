# typed: true
# frozen_string_literal: true

class StringScanner
  # Returns a hash of string variables matching the regular expression.
  #
  # ```ruby
  # scan = StringScanner.new('foobarbaz')
  # scan.match?(/(?<f>foo)(?<r>bar)(?<z>baz)/)
  # scan.named_captures # -> {"f"=>"foo", "r"=>"bar", "z"=>"baz"}
  # ```
  def named_captures; end
end
