# typed: strict
# frozen_string_literal: true

module Repositories
  module IKeyLink
    extend T::Helpers

    include Kernel

    abstract!

    sig { abstract.returns(Integer) }
    def id; end

    sig { abstract.returns(::String) }
    def key_prefix; end

    sig { abstract.returns(::String) }
    def url_template; end

    sig { abstract.returns(T::Boolean) }
    def is_alphanumeric?; end

    sig { abstract.returns(::ActiveModel::Errors) }
    def errors; end

    sig { params(args: T.untyped).returns(T::Boolean) }
    def valid?(*args)
      GitHub::DomainIsolation.within_domain_of(self.class) { super }
    end
  end
end
