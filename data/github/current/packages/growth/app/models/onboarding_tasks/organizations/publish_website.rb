# typed: strict
# frozen_string_literal: true

module OnboardingTasks
  module Organizations
    class PublishWebsite < Base
      extend T::Sig

      sig { override.returns(String) }
      def title
        "Publish a members-only website"
      end

      sig { returns(T::Boolean) }
      def require_demo_repository?
        true
      end

      sig { override.returns(T.nilable(String)) }
      def task_link
        return unless (repo = demo_repo)
        repository_pages_settings_path(organization, repo.name, show_tip: true)
      end

      sig { override.returns(String) }
      def icon_path
        "modules/dashboard/suggestions/private-pages.svg"
      end

      sig { override.returns(T::Boolean) }
      def verify_task
        return false unless (repo = demo_repo)

        repo.page.present?
      end
    end
  end
end
