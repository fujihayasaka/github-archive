# typed: strict
# frozen_string_literal: true

module Storage::UserAssetTransfer
  module SavedReplyCopyDependency
    extend T::Sig
    extend T::Helpers
    extend ActiveSupport::Concern

    abstract!

    MemexProjectOrRepository = T.type_alias { T.nilable(T.any(MemexProject, Repository)) }

    sig { abstract.returns(T.nilable(String)) }
    def body; end

    sig { abstract.params(new_body: T.nilable(String)).returns(T.nilable(String)) }
    def body=(new_body); end

    sig { abstract.returns(MemexProjectOrRepository) }
    def saved_reply_copy_target; end

    included do
      T.bind(self, T.class_of(ActiveRecord::Base))
      before_save :replace_saved_reply_assets
    end

    sig { void }
    def replace_saved_reply_assets
      return if GitHub.enterprise?
      target = saved_reply_copy_target
      return unless target

      return unless self.body.present?

      urls = SavedReplyCopy.extract_urls_from_text(self.body)
      return if urls.empty?

      actor_id = GitHub.context[:actor_id]
      return unless actor_id.present?

      actor = User.find(actor_id)
      return unless actor.present?

      translations = SavedReplyCopy.copy_by_urls(target, actor, urls)
      return if translations.empty?

      translations.each { |t| self.body = T.must(self.body).gsub(t.original, t.translation) }
    end
  end
end
