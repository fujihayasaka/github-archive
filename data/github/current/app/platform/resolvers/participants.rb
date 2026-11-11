# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class Participants < Platform::Resolvers::Users
      def resolve
        if object.is_a?(PullRequest)
          Loaders::ActiveRecord.load(::Issue, object.id, column: :pull_request_id).then do |_issue|
            Promise.all([object.async_base_repository,
                         object.async_user,
                         object.async_commenters,
                         object.async_changed_commits]).then do |_repository, _|

              filter_spam(ArrayWrapper.new(object.participants))
            end
          end
        else
          Promise.all([object.async_user, object.async_commenters]).then do
            filter_spam(ArrayWrapper.new(object.participants))
          end
        end
      end
    end
  end
end
