# typed: true
# frozen_string_literal: true

class Rational
  # patch this method to ensure that when a Rational has #to_json called on it
  # the ActiveSupport#to_json patch herehttps://github.com/github/github/blob/8f6df98c79c69f126c8a06c18dc3e926d5c3e226/lib/github/json/active_support_patch.rb#L19-L24
  # can successfully encode the result of calling `obj.as_json` where obj is an instance of a Rational.
  # without this, Rational#as_json returns the instance of the rational--this is the intended behavior see source here https://github.com/rails/rails/blob/75a9e1be75769ae633a938d81d51e06852a69ea3/activesupport/lib/active_support/core_ext/object/json.rb#L104
  # But `GitHub::JSON#encode` fails when called with something that the yajl ruby gem cannot encode here https://github.com/github/github/blob/8f6df98c79c69f126c8a06c18dc3e926d5c3e226/lib/github/json.rb#L19.
  # So, we must ensure that the result of Rational#as_json is something that the Yajl::Encoder can encode
  def as_json(options = nil)
    self.to_s
  end
end
