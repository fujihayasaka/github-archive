# typed: true
# frozen_string_literal: true

class GitHubModels::DocumentationController < ApplicationController
  before_action :login_required
  before_action :github_models_required
  before_action :require_feature_enabled

  append_view_path "#{Rails.root}/app/components/github_models/documentation"

  def show
    key = GitHubModels::CatalogItem.key_for(registry: params[:registry], name: params[:model])
    model = GitHubModels::CatalogItem.find_by!(key: key)
    rendered_content = render_getting_started_content(model.to_model, model.to_schema)

    respond_to do |format|
      format.html do
        render json: rendered_content
      end
    end
  end

  # rubocop:disable GitHub/UseRestfulActions
  def render_getting_started_content(model, schema)
    data = GitHubModels::GettingStartedContent.build_template_data(model, schema)
    lang_sdk_list = data[:lang_sdk_list]
    model_name =  data[:model_name]

    # Exception holds documentation exception that are inconsistent with model capabilities from CatalogItem and the static docs
    # in GitHubModels::Payloads::GettingStartedContent.
    # Once migrated from GitHubModels::Payloads::GettingStartedContent, we can remove this and let the capabilities taked the lead.
    # For now, Its better to make sure the docs are the same.

    use_openai_preview_sdk = %w[o1 o1-mini o1-preview o3-mini]
    exceptions = {
      use_openai_preview_sdk: use_openai_preview_sdk,
      assistant_role: use_openai_preview_sdk.include?(model_name) ? "developer" : "system",
      hide_java_assistant: %w[o1-mini o1-preview]
    }

    result = {}
    lang_sdk_list.each do |lang|
      sdk_result = {}
      lang[:sdks].each do |sdk|

        code_sample = render_to_string(GitHubModels::Documentation::CodeSampleComponent.new(
          model_name: model_name,
          model_capabilities: data[:model_capabilities],
          task: lang[:task],
          language: lang[:lang],
          sdk: sdk[:sdk],
          exceptions: exceptions
          ), layout: false)

        content = render_to_string(GitHubModels::Documentation::GettingStartedComponent.new(sdk: sdk[:sdk], language: lang[:lang], task: lang[:task], code_sample: code_sample), layout: false)

        sdk_result[sdk[:sdk]] = {
          name: sdk[:name],
          content: content,
          code_sample: code_sample
        }
      end

      result[lang[:lang]] = {
        name: lang[:lang_name],
        sdks: sdk_result
      }
    end
    result
  end

  private

  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    current_user
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end

  def require_feature_enabled
    render_404 unless user_feature_enabled?(:github_models_dynamic_getting_started_content)
  end
end
