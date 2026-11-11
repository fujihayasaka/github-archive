# typed: true
# frozen_string_literal: true

require "iopromise"
require "iopromise/bertrpc"
require "iopromise/deferred"

class IOPromise::Base
  extend T::Generic

  Value = type_member
end

class IOPromise::Deferred::DeferredPromise
  extend T::Generic

  Value = type_member
end

class IOPromise::BERTRPC::Promise
  extend T::Generic

  Value = type_member
end
