# typed: strict
# frozen_string_literal: true

module Discussions
  class SectionRowComponent < ApplicationComponent
    extend T::Sig

    # org_param - the display_login of the Organization to use in routing, if working with org-level discussions
    sig do
      params(
        section: DiscussionSection,
        repository: Repository,
        modifiable_by_viewer: T::Boolean,
        org_param: T.nilable(String)
      ).void
    end
    def initialize(
      section:,
      repository:,
      modifiable_by_viewer:,
      org_param: nil
    )
      @section = section
      @repository = repository
      @modifiable_by_viewer = modifiable_by_viewer
      @org_param = org_param
    end

    private

    sig { returns(DiscussionSection) }
    attr_reader :section

    sig { returns(Repository) }
    attr_reader :repository

    sig { returns(T::Boolean) }
    attr_reader :modifiable_by_viewer

    sig { returns(T.nilable(String)) }
    attr_reader :org_param

    alias :modifiable_by_viewer? :modifiable_by_viewer

    sig { returns(String) }
    def agnostic_edit_section_path
      if org_param.present?
        edit_org_discussions_section_path(org: org_param, slug: section.slug)
      else
        edit_section_path(repository.owner_display_login, repository, slug: section.slug)
      end
    end

    sig { returns(T::Boolean) }
    def deletable?
      !modifiable_by_viewer?
    end

    sig { returns(String) }
    def delete_section_path
      section_path(repository.owner, repository, slug: section.slug)
    end
  end
end
