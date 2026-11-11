# typed: true
# frozen_string_literal: true

class ActionsWorkflowsLinkRenderer < WillPaginate::ActionView::LinkRenderer
  def prepare(collection, options, template)
    @collection = collection
    @options = options
    @template = template
  end

  # Used to override the URLs for Previous and Next page in the Actions tab when viewing a specific workflow
  def url(page)
    url_params = merge_get_params(default_url_params)
    url_params[:only_path] = true
    merge_optional_params(url_params)
    add_current_page_param(url_params, page)
    url_params.delete(:page) if page == 1

    return @template.workflow_runs_list_path(url_params) if url_params[:workflow_file_name].present?
    @template.actions_path(url_params)
  end
end
