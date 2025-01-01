# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class VoteForUser < Platform::Loader
      def self.load(subject, user_id)
        subject_class = subject.class

        self.for(subject_class, user_id).load(subject.id)
      end

      def initialize(subject_class, user_id)
        assoc = subject_class.reflect_on_association(:votes)
        @vote_class = assoc.klass
        @subject_column = assoc.foreign_key.to_sym
        @user_id = user_id
      end

      def fetch(subject_ids)
        @vote_class.where({ @subject_column => subject_ids, :user_id => @user_id }).index_by(&@subject_column)
      end
    end
  end
end
