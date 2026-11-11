# typed: strict
# frozen_string_literal: true

module Repositories
  module Cache::RepositorySerialization
    extend T::Helpers
    extend T::Generic

    CachedType = type_member

    private

    # ActiveRecord::Base#instantiate does not properly setup RepositoryCoder so we do that manually as we pull
    # the repository out of the cache
    sig { params(cached_value: Object).returns(T.nilable(Repository)) }
    def deserialize_repository(cached_value)
      cached_value = T.cast(cached_value, T::Hash[String, T.untyped])
      repository_attrs = cached_value["repository"] || {}
      return unless repository_attrs.present?
      repository_attrs = repository_attrs.dup

      coder = nil
      if repository_attrs["raw_data"]
        coder = Coders::Handler.new(Coders::RepositoryCoder).load(repository_attrs["raw_data"])
        repository_attrs.delete("raw_data")
      end

      repo = Repository.instantiate(repository_attrs)
      repo.raw_data = coder if coder

      repo
    end

    # If we call attributes_before_type_cast on a Repository out of the DB it will a ActiveModel::Type::Binary::Data
    # If we call attributes_before_type_cast on a Repository out of the cache it will be a Coders::RepositoryCoder
    # So normalize both to a String for comparison
    sig { params(cached_value: T.nilable(CachedType), db_value: T.nilable(CachedType)).returns([T::Hash[String, T.untyped], T::Hash[String, T.untyped]]) }
    def normalize_repository(cached_value, db_value)
      cached_attr = T.unsafe(cached_value)&.attributes_before_type_cast || {}
      db_attr = T.unsafe(db_value)&.attributes_before_type_cast || {}

      if cached_attr["raw_data"]&.is_a?(Coders::RepositoryCoder)
        cached_attr["raw_data"] = cached_attr["raw_data"].to_h
      end

      if db_attr["raw_data"]&.is_a?(ActiveModel::Type::Binary::Data)
        db_attr["raw_data"] = db_attr["raw_data"].to_s
      end

      if db_attr["raw_data"]&.is_a?(String)
        db_attr["raw_data"] = Coders::Handler.new(Coders::RepositoryCoder).load(db_attr["raw_data"]).to_h
      end

      [cached_attr, db_attr]
    end

    sig { params(cached_attr: T::Hash[String, T.untyped], db_attr: T::Hash[String, T.untyped]).returns(GitHub::RemoteCache::Comparison) }
    def compare_repository(cached_attr, db_attr)
      comparison = GitHub::RemoteCache::Comparison.new(Hashdiff.diff(cached_attr, db_attr))

      unless comparison.identical?
        comparison.mismatches.each do |mismatch|
          if mismatch == "pushed_at"
            GitHub.logger.info("repositories.cache.repository_serializer.mismatch",
              "cache": cached_attr["pushed_at"],
              "db": db_attr["pushed_at"]
           )
          end

          if mismatch.starts_with?("raw_data.")
            GitHub.logger.info("repositories.cache.repository_serializer.mismatch",
              "cache": cached_attr["raw_data"],
              "db": db_attr["raw_data"]
           )
          end
        end
      end

      comparison
    end
  end
end
