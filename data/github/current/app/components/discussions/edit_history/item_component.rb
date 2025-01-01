# typed: strict
# frozen_string_literal: true

module Discussions
  class EditHistory::ItemComponent < ApplicationComponent
    include BotHelper
    include GitHub::Memoizer

    sig do
      params(
        edit: T.any(DiscussionEdit, DiscussionCommentEdit),
        is_latest: T::Boolean,
        is_creation_edit: T::Boolean,
        ghost_user: User,
      ).void
    end
    def initialize(edit:, is_latest:, is_creation_edit:, ghost_user:)
      @edit             = edit
      @is_latest        = is_latest
      @is_creation_edit = is_creation_edit

      # We require passing in the preloaded `ghost` user so we don't have
      # to load it for every item.
      @ghost_user       = ghost_user
    end

    private

    sig { returns(T.any(DiscussionEdit, DiscussionCommentEdit)) }
    attr_reader :edit

    sig { returns(T::Boolean) }
    attr_reader :is_latest

    sig { returns(T::Boolean) }
    attr_reader :is_creation_edit

    alias :is_latest?        :is_latest
    alias :is_creation_edit? :is_creation_edit

    sig { returns(User) }
    memoize def editor
      edit.editor || @ghost_user
    end

    sig { returns(User) }
    memoize def deleter
      edit.deleted_by || @ghost_user
    end

    sig { returns(T::Boolean) }
    def deleted?
      edit.deleted_at.present?
    end

    sig { returns(T::Boolean) }
    def displayable?
      return false if deleted?
      safe_diff.present?
    end

    sig { returns(T.nilable(String)) }
    memoize def safe_diff
      edit.safe_diff
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    memoize def item_arguments
      args = {
        tag: :button,
        data: data_attributes,
        font_size: :small,
        classes: "lh-condensed",
        test_selector: "history-item-#{edit.id}",
      }

      if !displayable? && !deleted?
        args[:disabled] = true
      end

      args
    end

    sig { returns(T::Hash[String, String]) }
    memoize def data_attributes
      data = {
        "dialog-id" => "edit-history-dialog-#{edit.id}",
        "editor" => strip_tags(author_display_text),
      }

      if displayable?
        data["src"] = user_content_edit_path(id: edit.global_relay_id)
        data["action"] = "click:edit-history#displayDiffDialog"
      end

      if deleted?
        data["actor"] = strip_tags(author_display_text)
        data["datetime"] = edit.deleted_at&.iso8601
        data["action"] = "click:edit-history#displayDeletedDialog"
      end

      data
    end

    sig { returns(String) }
    def author_display_text
      if helpers.can_view_original_author?(edit.user_content)
        return editor.display_login unless helpers.posted_as_admin?(edit.user_content)

        author_display_name = deleted? ? deleter.display_login : editor.display_login
        safe_join(["Admin", dot_divider, author_display_name])
      else
        "Admin"
      end
    end

    sig { returns(String) }
    memoize def dot_divider
      content_tag(:span, " · ", class: "color-fg-muted f4")
    end

    sig { returns(String) }
    def action
      is_creation_edit? ? "created" : "edited"
    end

    sig { returns(T.nilable(String)) }
    def suffix
      if deleted?
        "(deleted)"
      elsif is_latest?
        "(most recent)"
      end
    end
  end
end
