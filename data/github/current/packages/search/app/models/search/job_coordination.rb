# typed: true
# frozen_string_literal: true

module Search
  module JobCoordination
    include GitHub::Memoizer
    extend self

    sig { returns(::Redis) }
    memoize def redis
      if GitHub.single_or_multi_tenant_enterprise?
        GitHub.job_coord_redis
      else
        ::Redis.new(GitHub.read_redis_config("config/redis_search_index_job_coord.yml"))
      end
    end
  end
end
