# typed: true
# frozen_string_literal: true

# A helper for org-level discussions - largely focused on routing the various paths to the correct place given
# the current location of the user (allowing for DRYer controller actions)
# eg: /owner/repo/discussions/new -> /owner/repo/discussions/1
#     /orgs/org_name/discussions/new -> /orgs/org_name/discussions/1
module Discussions
  module OrgLevelDiscussionsUrlHelper
    extend T::Sig

    # org_param - the display_login of the Organization to use in routing, if working with org-level discussions
    # if org_params is passed in as nil, it will still get lumped into args
    sig { params(discussion: Discussion, org_param: T.nilable(String), args: T.untyped).returns(String) }
    def agnostic_discussion_path(discussion, org_param: nil, **args)
      if org_param.present?
        return UrlHelpers.org_discussion_path(org: org_param, number: discussion.number, **args)
      end

      # defined in UrlHelper, which includes this module
      T.unsafe(self).discussion_path(discussion, discussion.repository, **args)
    end

    # org_param - the display_login of the Organization to use in routing, if working with org-level discussions
    sig { params(discussion: Discussion, org_param: T.nilable(String), anchor: T.nilable(String)).returns(String) }
    def agnostic_discussion_url(discussion, org_param: nil, anchor: nil)
      if org_param.present?
        # Get *_url helper from `self` since UrlHelpers doesn't have a default host set
        T.unsafe(self).org_discussion_url(org: org_param, number: discussion.number, anchor: anchor)
      else
        # Get *_url helper from `self` since UrlHelpers doesn't have a default host set
        T.unsafe(self).discussion_url(discussion.repository_owner_login, discussion.repository&.name, discussion,
          anchor: anchor)
      end
    end

    # org_param - the display_login of the Organization to use in routing, if working with org-level discussions
    sig { params(repository: T.nilable(Repository), org_param: T.nilable(String), args: T.untyped).returns(String) }
    def agnostic_discussions_path(repository = nil, org_param: nil, **args)
      repository ||= T.unsafe(self).current_repository

      if org_param.present?
        UrlHelpers.org_discussions_path(org: org_param, **args)
      else
        UrlHelpers.discussions_path(repository&.owner_display_login, repository, **args)
      end
    end

    # org_param - the display_login of the Organization to use in routing, if working with org-level discussions
    sig do
      params(
        repository: T.nilable(Repository),
        org_param: T.nilable(String)
      ).returns(String)
    end
    def agnostic_categories_path(repository: nil, org_param: nil)
      if org_param.present?
        UrlHelpers.org_discussions_categories_path(org: org_param)
      else
        UrlHelpers.categories_path(repository&.owner_display_login, repository)
      end
    end

    # org_param - the display_login of the Organization to use in routing, if working with org-level discussions
    sig do
      params(
        repository: T.nilable(Repository),
        org_param: T.nilable(T.any(Organization, String)),
        args: T.untyped
      ).returns(String)
    end
    def agnostic_new_discussion_path(repository = nil, org_param: nil, **args)
      if org_param.present?
        UrlHelpers.new_org_discussion_path(org: org_param, **args)
      else
        UrlHelpers.new_discussion_path(repository&.owner_display_login, repository, **args)
      end
    end

    sig do
      params(
        repository: T.nilable(Repository),
        org: T.nilable(T.any(Organization, String)),
        args: T::Hash[T.any(String, Symbol), T.untyped]
      ).returns(String)
    end
    def agnostic_choose_category_discussion_path(repository = nil, org: nil, **args)
      repository ||= T.unsafe(self).current_repository

      if org.present?
        UrlHelpers.org_choose_category_discussion_path(org: org, **args)
      else
        UrlHelpers.choose_category_discussion_path(repository&.owner_display_login, repository, **args)
      end
    end
  end
end
