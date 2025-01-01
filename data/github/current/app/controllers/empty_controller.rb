# typed: true
# frozen_string_literal: true

class EmptyController < ApplicationController
  # Intentionally left empty. This is a concrete implementation of ApplicationController
  # which is marked as abstract and therefore should never be instantiated. This class exists
  # only as a way to instantiate ApplicationController which is currently needed to
  # access an instance of the view context.
end
