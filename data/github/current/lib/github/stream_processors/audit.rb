# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Audit
      autoload :EnterpriseDriftwoodProcessor, "github/stream_processors/audit/enterprise_driftwood_processor"
      autoload :DevelopmentDriftwoodProcessor, "github/stream_processors/audit/development_driftwood_processor"
    end
  end
end
