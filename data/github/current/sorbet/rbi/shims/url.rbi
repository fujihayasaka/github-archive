# typed: strict
# frozen_string_literal: true

class Module
  sig do
    params(
      args: T.untyped,
      kwargs: T.untyped,
      block: T.nilable(T.proc.bind(Platform::Objects::Base::Field).params(arg0: Platform::Objects::Base::Field).void)
    ).returns(Platform::Objects::Base::Field)
  end
  def field(*args, **kwargs, &block); end
end
