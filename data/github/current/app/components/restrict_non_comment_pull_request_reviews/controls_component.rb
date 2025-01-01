# typed: true
# frozen_string_literal: true

module RestrictNonCommentPullRequestReviews
  class ControlsComponent < ApplicationComponent
    def initialize(subject:)
      @subject = subject
    end

    private

    attr_reader :subject

    def behavior_for(model)
      case model
      when Repository
        RepositoryBehavior.new
      when Organization
        OrganizationBehavior.new
      when User
        UserBehavior.new
      end
    end

    def behavior
      behavior_for(subject)
    end

    delegate :directly_configurable?, :setting_target_description, to: :behavior, private: true

    def checked?
      subject.non_comment_pull_request_reviews_restricted?
    end

    memoize def inherited_setting_source
      subject.non_comment_pull_request_reviews_source
    end

    def setting_source_description
      behavior_for(inherited_setting_source).setting_source_description
    end

    def overridden?
      !inherited_setting_source.nil? && inherited_setting_source != subject
    end

    def set_locally?
      inherited_setting_source == subject
    end

    def can_enable?
      !checked? || !set_locally?
    end

    def can_disable?
      checked? || !set_locally?
    end

    def can_unset?
      !directly_configurable? && set_locally?
    end

    def form_path
      behavior.form_path_from(helpers, subject)
    end

    class RepositoryBehavior
      def directly_configurable?
        true
      end

      def setting_target_description
        "this repository"
      end

      def setting_source_description
        "this repository"
      end

      def form_path_from(helpers, repository)
        helpers.set_repository_code_review_limits_path(repository.owner_display_login, repository.name)
      end
    end

    class UserBehavior
      def directly_configurable?
        false
      end

      def setting_target_description
        "your public repositories"
      end

      def setting_source_description
        "the owner's account"
      end

      def form_path_from(helpers, user)
        helpers.set_user_code_review_limits_path
      end
    end

    class OrganizationBehavior
      def directly_configurable?
        false
      end

      def setting_target_description
        "public repositories within this organization"
      end

      def setting_source_description
        "the organization"
      end

      def form_path_from(helpers, organization)
        helpers.set_org_code_review_limits_path(organization.display_login)
      end
    end
  end
end
