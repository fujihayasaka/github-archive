# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class RepositoryByName < Platform::Loader
      def self.load(user_id, name)
        # The database treats repository names in a case-insensitive manner.
        # That is, requesting a repo by the query "Hello" will return a repo with the name "helLo".
        # Unfortunately, Platform::Loader#perform fetches from a Hash, which has case-sensitive keys.
        # In order to get around this, we downcase the names here and in the #fetch method.
        # Downcasing gives us the same behavior as we expect from database accesses like
        #   Repository.where(name: "Hello") => #<Repository name="hello">
        self.for(user_id).load(name.to_s.downcase)
      end

      def self.load_all(user_id, names)
        Promise.all(names.map { |name| load(user_id, name) })
      end

      def initialize(user_id)
        @user_id = user_id
      end

      def fetch(names)
        ::Repository
          .where(owner_id: @user_id, name: names)
          .index_by { |r| r.name.downcase } # We downcase on purpose. Please see comment in .load above.
      end
    end
  end
end
