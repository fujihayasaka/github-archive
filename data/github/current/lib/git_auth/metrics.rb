# typed: true
# frozen_string_literal: true

module GitAuth
  class Metrics
    sig do
      type_parameters(:R)
      .params(
        stat: String,
        tags: T::Array[String],
        blk: T.proc.returns(T.type_parameter(:R))
      ).returns(T.type_parameter(:R))
    end
    def self.time(stat, tags: [], &blk)
      GitHub.dogstats.distribution_time("gitauth.#{stat}.duration", tags:) do
        yield
      end
    end

    def self.duration(stat, start_time, tags: [])
      GitHub.dogstats.distribution("gitauth.#{stat}.duration", GitHub::Dogstats.duration(start_time), tags:)
    end
  end
end
