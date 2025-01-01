# typed: true
# frozen_string_literal: true

module StatusCheckConfig::Defaults
  module Success
    def state
      StatusCheckConfig::States::SUCCESS
    end

    def sentence_for_status
      "All checks have passed"
    end
  end
end
