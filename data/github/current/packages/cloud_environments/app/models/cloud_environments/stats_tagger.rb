# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module CloudEnvironments
  class StatsTagger < Codespaces::StatsTagger
    include IStatsTagger
    # This should probably be the base and then extended for different experience types
  end
end
