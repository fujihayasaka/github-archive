# typed: true
# frozen_string_literal: true

module Stafftools
  module User
    class PurgatoryView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      PER_PAGE = 100

      attr_reader :user

      def page
        @page ||= 1
      end
      attr_initializable :page

      # Public
      def title
        @title ||= "#{user}'s deleted repositories"
      end

      # returns WillPaginate::Collection
      def repos
        return @repos if defined?(@repos)

        @repos = ::Repositories::Public
          .deleted_owned_by(user.id)
          .includes(owner: :soft_deleted_organization)
          .order("updated_at DESC")
          .paginate(page: page, per_page: PER_PAGE)
      end

      # Public
      def any?
        repos.any?
      end

      def sort(repositories)
        repositories.sort do |a, b|
          if a.deleted_at && b.deleted_at
            b.deleted_at <=> a.deleted_at
          elsif a.deleted_at.nil? && b.deleted_at.nil?
            a.name <=> b.name
          elsif a.deleted_at.nil?
            1
          else
            -1
          end
        end
      end

      def repo_li_css(repo)
        "#{repo.public? ? "public" : "private"}#{private_fork?(repo) ? ' js-private-fork' : ''}#{repo.deleted_at.blank? ? ' js-no-deleted-at' : ''}"
      end

      def repo_span_symbol(repo)
        repo.public? ? "repo" : "lock"
      end

      def repo_purge_button_css(repo)
        "#{repo.owner.legal_hold? ? "disabled" : ""}"
      end

      def repo_checkbox_title(repo)
        if private_fork?(repo)
          "#{repo.name_with_owner} was a private fork"
        else
          "#{repo.name_with_owner} was #{repo.public ? 'public' : 'private'}"
        end
      end

      def private_fork?(repo)
        !repo.public && repo.parent_id
      end

      def legal_hold?
        LegalHold.where(user_id: user.id).any?
      end

      def belongs_to_a_soft_deleted_org?(repo)
        repo.owner.organization? && repo.owner.soft_deleted?
      end
    end
  end
end
