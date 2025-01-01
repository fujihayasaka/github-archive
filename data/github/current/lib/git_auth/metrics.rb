# typed: true
# frozen_string_literal: true

module GitAuth
  class Metrics
    extend T::Sig

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
  end
end
