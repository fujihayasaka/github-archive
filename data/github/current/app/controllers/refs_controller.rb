# typed: true
# frozen_string_literal: true

class RefsController < GitContentController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:tags]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :tags],
    optional: true

  CONDITIONAL_ACCESS_BYPASS_PUBLIC_REPO_ACTIONS = %w(index tags ref_list ref_list_select_menu).freeze
  NAME_PLACEHOLDER = "REPLACE_THIS_TOTALLY_UNIQUE_STRING_WITH_TARGET_NAME"
  TAGS_LIMIT = 100

  layout "repository"
  javascript_bundle :repositories
  stylesheet_bundle :code

  param_encoding :tags, :q, "ASCII-8BIT"
  param_encoding :ref_list_select_menu, :q, "ASCII-8BIT"

  def index
    url_prefix, url_suffix = ref_url_template_parts

    respond_to do |format|
      format.html do
        render partial: "refs/ref_list_content", layout: false, locals: {
          url_prefix: url_prefix,
          url_suffix: url_suffix,
          source_controller: params[:source_controller].to_s,
          source_action: params[:source_action].to_s,
        }
      end
    end
  rescue ActionController::UrlGenerationError
    render_404
  end

  def tags # rubocop:todo GitHub/UseRestfulActions
    search_query = params[:q].to_s
    tags = current_repository.tags.substring_filter(substring: search_query, limit: TAGS_LIMIT)
    url_prefix, url_suffix = ref_url_template_parts

    url_portion_callable = -> (tag) {
      escaped_tag = escape_url_branch(tag.name).gsub("%2B", "+")
      "#{url_prefix}#{escaped_tag}#{url_suffix}"
    }

    respond_to do |format|
      format.html do
        render "refs/tags",
          formats: :html,
          layout: false,
          locals: {
            url_portion_callable: url_portion_callable,
            current_tag_name: params[:tag_name],
            tags: tags,
          }
      end
    end
  rescue ActionController::UrlGenerationError
    render_404
  end

  # A JSON-only list of branches or tags used by the ref selector.
  def ref_list # rubocop:todo GitHub/UseRestfulActions
    cache_key = helpers.ref_list_cache_key
    # Please bump the version specifier in `ref_list_cache_key` if anything at
    # all about the response format changes!
    return unless stale?(etag: helpers.ref_list_cache_key, template: false)

    refs = case params[:type]
    when "branch"
      current_repository.heads.refs_with_default_first
    else
      current_repository.tags
    end

    respond_to do |format|
      format.json do
        render json: { refs: refs.map(&:name), cacheKey: cache_key }
      end

      format.html_fragment do
        render partial: "refs/ref_selector_items", layout: false, formats: [:html], locals: {
          refs: refs,
          repository: current_repository,
          tag_name: params[:tag_name]
        }
      end
    end
  end

  def ref_list_select_menu # rubocop:todo GitHub/UseRestfulActions
    search_query = params[:q].to_s

    respond_to do |format|
      format.any(:html, :html_fragment) do
        refs = case params[:type]
        when "branch"
          if !search_query.empty?
            current_repository.heads.substring_filter(substring: search_query, limit: TAGS_LIMIT)
          else
            current_repository.heads.refs_with_default_first
          end
        else
          current_repository.tags.substring_filter(substring: search_query, limit: TAGS_LIMIT)
        end
        refs.map! do |ref|
          {
            name: ref.name,
            default: ref.default_branch?
          }
        end
        render partial: "refs/ref_menu_list", layout: false, formats: [:html, :html_fragment], locals: {
          refs: refs,
          current_branch: params[:current_branch],
        }
      end
    end
  end

  private

  def ref_url_template_parts
    url_for(
      controller: params[:source_controller].to_s,
      action: params[:source_action].to_s,
      name: NAME_PLACEHOLDER,
      path: params[:path],
    ).split(NAME_PLACEHOLDER, 2)
  end

  def route_supports_advisory_workspaces?
    true
  end

  def load_objects_from_inputs(inputs)
    heads = inputs.map do |(_key, item)|
      item["head_commit"]
    end
    base = inputs.values.first["base_commit"]
    ahead_behind_values = current_repository.rpc.ahead_behind(base, heads)
    max_diverged = ahead_behind_values.map { |_, (ahead, behind)| ahead + behind }.max

    inputs.map do |(key, item)|
      [key, [ahead_behind_values[item["head_commit"]], max_diverged]]
    end
  end
end
