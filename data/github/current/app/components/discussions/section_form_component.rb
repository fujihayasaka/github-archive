# typed: strict
# frozen_string_literal: true

module Discussions
  class SectionFormComponent < ApplicationComponent
    extend T::Sig

    # org_param - the display_login of the Organization to use in routing, if working with org-level discussions
    sig { params(section: DiscussionSection, repository: Repository, org_param: T.nilable(String)).void }
    def initialize(section:, repository:, org_param: nil)
      @section = section
      @repository = repository
      @org_param = org_param
    end

    private

    sig { returns(Repository) }
    attr_reader :repository

    sig { returns(DiscussionSection) }
    attr_reader :section

    sig { returns(T.nilable(String)) }
    attr_reader :org_param

    sig { returns(String) }
    def current_emoji_html
      section.emoji_html
    end

    sig { returns(String) }
    def form_action
      if section.new_record?
        sections_path(repository.owner_display_login, repository)
      else
        section_path(user_id: repository.owner_display_login, repository: repository, slug: section.slug)
      end
    end

    sig { returns(String) }
    def form_method
      if section.new_record?
        "post"
      else
        "put"
      end
    end

    sig { returns(String) }
    def submit_text
      if section.new_record?
        "Create"
      else
        "Update"
      end
    end

    sig { returns(String) }
    def emoji_picker_path
      emoji_picker_categories_path(
        user_id: repository.owner_display_login,
        repository: repository,
        emoji: section.emoji
      )
    end

    sig { returns(String) }
    def all_discussions_octicon
      render Primer::Beta::Octicon.new(
        icon: "comment-discussion",
        m: 2,
      )
    end

    sig { params(category_id: Integer).returns(T::Boolean) }
    def category_checked?(category_id)
      section.discussion_category_ids.include?(category_id)
    end

    sig { returns(String) }
    def cancel_path
      agnostic_categories_path(repository: repository, org_param: org_param)
    end
  end
end
