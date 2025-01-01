# typed: strict
# frozen_string_literal: true

module Repositories
  class HydroPushJobFlags
    FLAGS = T.let(
      %w[hydro_authentic_commits_job].freeze, T::Array[String])

    sig { params(enabled_flag_names: T.untyped).void }
    def initialize(enabled_flag_names)
      @enabled_flag_names = enabled_flag_names
    end

    sig { params(repository: T.untyped).returns(T::Array[String]) }
    def self.enabled_for_repo(repository)
      FLAGS.map { |flag| flag if GitHub.flipper[flag.to_sym].enabled?(repository) }.compact
    end

    sig { params(flag: T.untyped).returns(T::Boolean) }
    def enabled?(flag)
      FLAGS.include?(flag) && @enabled_flag_names.include?(flag)
    end
  end
end
