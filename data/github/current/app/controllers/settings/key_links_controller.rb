# typed: true
# frozen_string_literal: true

class Settings::KeyLinksController < AbstractRepositoryController # rubocop:todo GitHub/ControllersShouldHaveTests

  before_action :login_required
  before_action :writable_repository_required
  before_action :sudo_filter, only: [:new, :create]
  before_action :ensure_admin_access
  before_action :ensure_custom_key_links_enabled

  depends_on_clusters ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    optional: false, only: [:index, :new]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :new], optional: true

  layout "repository"
  javascript_bundle :settings

  def index
    render "settings/key_links/index", locals: { key_links: KeyLinks::Public.find_all_with_owner!(current_repository) }
  end

  def new
    render "settings/key_links/new", locals: { key_link: KeyLinks::Public.instance_for_new_form }
  end

  def check # rubocop:todo GitHub/UseRestfulActions
    key_link = KeyLinks::Public.build(key_link_data)

    if key_link.valid?
      render partial: "settings/key_links/preview", locals: { key_link: key_link }, layout: false
    else
      head :unprocessable_entity
    end
  end

  def create
    GitHub.context.push(spamurai_form_signals: spamurai_form_signals)

    key_link = KeyLinks::Public.create(key_link_data)

    if key_link.valid?
      redirect_to key_links_path(current_repository.owner, current_repository)
    else
      flash.now[:error] = key_link.errors.full_messages.to_sentence
      GitHub.dogstats.increment("key_links", tags: ["action:create", "valid:false"])
      render "settings/key_links/new", locals: { key_link: key_link }
    end
  end

  def destroy
    KeyLinks::Public.destroy_by_id(params[:id].to_i)
    redirect_to key_links_path(current_repository.owner, current_repository)
  end

  private

  def key_link_data
    {
      key_prefix: key_link_params[:key_prefix],
      url_template: key_link_params[:url_template],
      owner: current_repository,
      is_alphanumeric: parse_bool(key_link_params[:is_alphanumeric])
    }
  end

  def key_link_params
    params.require(:key_link).permit(:key_prefix, :url_template, :is_alphanumeric)
  end

  def ensure_custom_key_links_enabled
    render_404 unless current_repository.plan_supports?(:custom_key_links)
  end

  def parse_bool(value)
    return nil if value.blank?

    ActiveRecord::Type::Boolean.new.deserialize(value)
  end

end
