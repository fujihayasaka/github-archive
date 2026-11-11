# typed: strict
# frozen_string_literal: true

class Rails::Application < ::Rails::Engine
  sig { params(block: T.proc.bind(Rails::Application).void).void }
  def self.configure(&block); end

  sig { params(block: T.proc.bind(Rails::Application).void).void }
  def configure(&block); end
end
