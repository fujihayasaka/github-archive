# typed: true
# frozen_string_literal: true

module GitHub
  class PreReceiveHookEntry
    DISABLED = 0
    TESTING  = 1
    ENABLED  = 2

    DESCRIPTIONS = { DISABLED => "Disabled", TESTING => "Testing", ENABLED => "Enabled" }

    HOOK_STATS_LIMIT = 14 * 1024
    OVERFLOW = "hook-overflow".freeze

    attr_reader :environment_id, :checksum, :hook_id, :repository_id, :script, :enforcement, :final
    def initialize(environment_id, checksum, hook_id, repository_id, script, enforcement, final = nil)
      @environment_id = environment_id
      @checksum = checksum
      @hook_id = hook_id
      @repository_id = repository_id
      @script = script
      @enforcement = enforcement
      @final = final && final != 0
    end

    def self.from_hash(hook)
      new(hook["e"], hook["c"], hook["h"], hook["r"], hook["s"], hook["n"])
    end

    def final?
      final
    end

    def as_json
      { e: environment_id,
        c: checksum,
        h: hook_id,
        r: repository_id,
        s: script,
        n: enforcement,
      }
    end

    def to_json
      as_json.to_json
    end
  end
end
