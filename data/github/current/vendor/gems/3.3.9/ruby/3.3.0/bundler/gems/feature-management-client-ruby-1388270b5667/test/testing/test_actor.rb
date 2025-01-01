# frozen_string_literal: true
# typed: true

require "sorbet-runtime"

class TestActor
  extend T::Sig
  include Vexi::Actor

  def initialize(id)
    @id = T.let(id, String)
  end

  def vexi_id
    @id
  end
end
