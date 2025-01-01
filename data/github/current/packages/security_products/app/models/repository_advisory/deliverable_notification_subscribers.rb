# typed: strict
# frozen_string_literal: true

module RepositoryAdvisory::DeliverableNotificationSubscribers
  extend T::Helpers

  UserIdArray = T.type_alias { T::Array[Integer] }

  requires_ancestor { RepositoryAdvisory::DeliverableNotificationSubscribers::NotifiableComment }

  # Get deliverable user IDs for users mentioned in this comment.
  sig { params(direct_mention_user_ids: T.nilable(UserIdArray), actor_id: T.nilable(Numeric)).returns(T.nilable(UserIdArray)) }
  def deliverable_direct_mention_user_ids(direct_mention_user_ids, actor_id)
    return unless direct_mention_user_ids
    filter_for_writable_user_ids(direct_mention_user_ids, comment_author_id: actor_id)
  end

  # Get deliverable user IDs for this newsies comment.
  # comment_author_id refers to the "actor" of the newsies "comment".
  sig { params(comment_author_id: T.nilable(Numeric)).returns(UserIdArray) }
  def deliverable_user_ids(comment_author_id: nil)
    newsies_list = Newsies::List.to_object(T.must(repository_advisory).repository)
    newsies_thread = Newsies::Thread.to_object(repository_advisory, list: newsies_list)

    subscriber_set = GitHub.newsies.subscriber_set_for(
      list: newsies_list,
      thread: newsies_thread
    ).value!

    filter_for_writable_user_ids(subscriber_set.subscribed.keys, comment_author_id: comment_author_id)
  end

  # comment_author_id refers to the "actor" of the newsies "comment".
  sig { params(unfiltered_user_ids: UserIdArray, comment_author_id: T.nilable(Numeric)).returns(UserIdArray) }
  def filter_for_writable_user_ids(unfiltered_user_ids, comment_author_id: nil)
    unfiltered_user_ids.filter_map do |user_id|
      user_id if T.must(repository_advisory).writable_by?(User.find(user_id)) && user_id != comment_author_id
    end
  end

  # Required interface for modules including this mixin.
  module NotifiableComment
    extend T::Helpers

    interface!

    sig { abstract.returns(T.nilable(::RepositoryAdvisory)) }
    def repository_advisory; end
  end
end
