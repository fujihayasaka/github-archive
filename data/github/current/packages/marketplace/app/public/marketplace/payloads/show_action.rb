# typed: strict
# frozen_string_literal: true

module Marketplace
  module Payloads
    class ShowAction
      include GitHub::Memoizer
      include ::Search::RepositoryActionIconHelper
      include UrlHelpers

      sig { returns(RepositoryAction) }
      attr_reader :repository_action

      sig { returns(T.nilable(String)) }
      attr_reader :selected_version

      sig { returns(T.nilable(User)) }
      attr_reader :current_user

      sig { returns(T.nilable(Release)) }
      attr_reader :selected_release

      sig { returns(ActiveRecord::Relation) }
      attr_reader :releases

      sig { returns(Release) }
      attr_reader :latest_release

      sig { returns(T::Boolean) }
      attr_reader :logged_in

      sig { returns(T::Boolean) }
      attr_reader :emu_contribution_blocked

      delegate :repository, to: :repository_action, private: true

      alias :logged_in? :logged_in

      sig do
        params(
          repository_action: RepositoryAction,
          selected_version: T.nilable(String),
          current_user: T.nilable(User),
          selected_release: T.nilable(Release),
          releases: ActiveRecord::Relation,
          latest_release: Release,
          logged_in: T::Boolean,
          emu_contribution_blocked: T::Boolean
        ).void
      end
      def initialize(
        repository_action:,
        selected_version:,
        current_user:,
        selected_release:,
        releases:,
        latest_release:,
        logged_in:,
        emu_contribution_blocked:
      )
        @repository_action = repository_action
        @selected_version = selected_version
        @current_user = current_user
        @selected_release = selected_release
        @releases = releases
        @latest_release = latest_release
        @logged_in = logged_in
        @emu_contribution_blocked = emu_contribution_blocked
      end

      sig do
        returns({
          action: Marketplace::Types::SerializedActionListing,
          readmeHtml: T.nilable(String),
          helpUrl: String,
          repository: Marketplace::Types::SerializedRepository,
          releaseData: Marketplace::Types::SerializedReleaseData,
          repoAdminableByViewer: T::Boolean,
          loggedIn: T::Boolean,
          starData: Marketplace::Types::SerializedStarData
        })
      end
      def call
        {
          action: Marketplace::Serializers::Action.serialize_model(repository_action),
          readmeHtml: readme_html,
          helpUrl: "#{GitHub.help_url}/articles/about-readmes/",
          repository: Marketplace::Serializers::Repository.new(repository: repository, current_user: current_user).call,
          releaseData: Marketplace::Serializers::ReleaseData.new(
            selected_release: selected_release,
            latest_release: latest_release,
            releases: releases
          ).call,
          repoAdminableByViewer: repo_viewer_can_administer?,
          loggedIn: logged_in?,
          starData: Marketplace::Serializers::StarData.new(
            logged_in: logged_in?,
            current_user: current_user,
            repository: repository,
            emu_contribution_blocked: emu_contribution_blocked
          ).call
        }
      end

      private

      sig { returns(T.nilable(String)) }
      def readme_html
        Marketplace::Actions::GetReadmeHtml.new(
          repository_action: repository_action, selected_version: selected_version
        ).call
      end

      sig { returns(T::Boolean) }
      def repo_viewer_can_administer?
        return false unless current_user

        repository.adminable_by?(current_user)
      end
    end
  end
end
