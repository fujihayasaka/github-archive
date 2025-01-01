# typed: true
# frozen_string_literal: true

module NotificationSubscriptions
  class RepositoryFilterView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include UrlHelpers

    attr_reader :lists, :params

    def sorted_lists
      @sorted_lists ||= lists.sort_by { |list| list.name_with_display_owner }
    end

    def repository_url(list = nil)
      repository_param = list.present? ? list.global_relay_id : nil
      notification_subscriptions_path(link_params.merge(repository: repository_param))
    end

    def link_params
      @link_params ||= params.slice(:sort, :reason, :repository)
    end

    def repository_selected?(list)
      params[:repository] == list.global_relay_id
    end

    def no_repository_selected?
      params[:repository].nil?
    end

    def avatar_url(list)
      list.owner.primary_avatar_url
    end

    def label(list)
      list.name_with_display_owner
    end

    def reason
      link_params[:reason]
    end

    def sort
      link_params[:sort]
    end
  end
end
