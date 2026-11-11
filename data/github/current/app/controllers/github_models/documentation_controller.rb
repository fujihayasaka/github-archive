# typed: true
# frozen_string_literal: true

class GitHubModels::DocumentationController < ApplicationController
  before_action :login_required
  before_action :marketplace_required
  before_action :github_models_required

  append_view_path "#{Rails.root}/app/components/github_models/documentation"

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::GitHubModels,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:show],
    optional: true

  def show
    slug = GitHubModels.domain.models.slug_for(registry: params[:registry], name: params[:model])
    model = GitHubModels.domain.models.find!(slug: slug)
    models_user = GitHubModels::User.new(user: current_user)
    model_hash = models_user.model_hash(model)
    is_billing_enabled = current_user&.models_billing_enabled?
    rendered_content = render_getting_started_content(model_hash, model.to_schema, is_billing_enabled)

    respond_to do |format|
      format.html do
        render json: rendered_content
      end
    end
  end

  # rubocop:disable GitHub/UseRestfulActions
  def render_getting_started_content(model, schema, is_billing_enabled = false)
    data = GitHubModels::GettingStartedContent.build_template_data(model, schema)
    lang_sdk_list = data[:lang_sdk_list]
    model_name =  data[:model_name]
    model_prefix = data[:model_prefix]

    # Exception holds documentation exception that are inconsistent with model capabilities from GitHubModels::Model
    # and the static docs in GitHubModels::Payloads::GettingStartedContent.
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
          model_prefix: model_prefix,
          model_name: model_name,
          publisher_name: data[:publisher_name],
          model_capabilities: data[:model_capabilities],
          task: lang[:task],
          language: lang[:lang],
          sdk: sdk[:sdk],
          exceptions: exceptions,
          parameters_as_template: false
          ), layout: false)

        code_sample_templated = render_to_string(GitHubModels::Documentation::CodeSampleComponent.new(
          model_prefix: model_prefix,
          model_name: model_name,
          publisher_name: data[:publisher_name],
          model_capabilities: data[:model_capabilities],
          task: lang[:task],
          language: lang[:lang],
          sdk: sdk[:sdk],
          exceptions: exceptions,
          parameters_as_template: true
          ), layout: false)

        content = render_to_string(GitHubModels::Documentation::GettingStartedComponent.new(sdk: sdk[:sdk], language: lang[:lang], task: lang[:task], code_sample: code_sample, is_billing_enabled: is_billing_enabled), layout: false)

        sdk_result[sdk[:sdk]] = {
          name: sdk[:name],
          content: content,
          code_sample: code_sample_templated
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
end
