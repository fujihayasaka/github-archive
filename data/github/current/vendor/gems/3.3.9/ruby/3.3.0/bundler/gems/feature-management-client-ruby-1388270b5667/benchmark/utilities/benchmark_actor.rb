# frozen_string_literal: true
# typed: true

class BenchmarkActor
  include Vexi::Actor

  def initialize(id = "User:1234678")
    @id = id
  end

  def vexi_id
    return @id
  end

  def flipper_id
    return @id
  end
end
