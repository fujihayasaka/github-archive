# typed: true

class Twirp::ClientResp
  extend T::Sig
  extend T::Generic

  Elem = type_member

  sig { returns(Elem) }
  def data; end

  sig { returns(Twirp::Error) }
  def error; end
end

class Twirp::Error
  extend T::Sig

  sig { returns(Numeric) }
  def code; end

  sig { returns(String) }
  def code; end
end
