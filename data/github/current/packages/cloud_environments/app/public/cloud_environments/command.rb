# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module CloudEnvironments
  class Command < Codespaces::Command
    abstract!
  end
end
