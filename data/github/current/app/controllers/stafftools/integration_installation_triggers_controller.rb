# typed: true
# frozen_string_literal: true

module Stafftools
  class IntegrationInstallationTriggersController < StafftoolsController

    before_action :dotcom_required
    before_action :find_trigger, only: [:edit, :update, :destroy]

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Collab,
      ApplicationRecord::Ballast,
      ApplicationRecord::Configurations,
      ApplicationRecord::Repositories,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      only: [:edit]

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Collab,
      ApplicationRecord::Ballast,
      ApplicationRecord::Configurations,
      ApplicationRecord::Repositories,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      only: [:index]

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Collab,
      ApplicationRecord::Ballast,
      ApplicationRecord::Configurations,
      ApplicationRecord::Repositories,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      only: [:new]

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:edit, :new, :index], optional: true

    PER_PAGE = 30

    def index
      installation_trigger_ids = IntegrationInstallTrigger.install_types.flat_map do |type, _enum|
        IntegrationInstallTrigger.preload(integration: [:owner]).by_install_type(type).pluck(:id)
      end
      installation_triggers = IntegrationInstallTrigger.where(id: installation_trigger_ids).paginate(page: params[:page], per_page: PER_PAGE)

      render "stafftools/integration_installation_triggers/index", locals: { installation_triggers: installation_triggers }
    end

    def new
      @install_trigger = IntegrationInstallTrigger.new
      render "stafftools/integration_installation_triggers/new"
    end

    def edit
      render "stafftools/integration_installation_triggers/new"
    end

    def update
      update_params = installation_trigger_params.merge(integration_id: @install_trigger.integration_id, install_type: @install_trigger.install_type)
      @install_trigger = IntegrationInstallTrigger.new(update_params)

      if @install_trigger.save
        redirect_to stafftools_integration_installation_triggers_path,
          notice: "#{T.must(@install_trigger.integration).name} #{@install_trigger.install_type} trigger updated."
      else
        render "stafftools/integration_installation_triggers/new"
      end
    end

    def create
      integration = Integration.find_by(id: installation_trigger_params[:integration_id])

      if integration && (latest = IntegrationInstallTrigger.latest(integration: integration, install_type: installation_trigger_params[:install_type])) &&
          !latest.deactivated?
        flash[:notice] = "#{integration.name} is already installed automatically. Please update or disable here."
        return redirect_to(edit_stafftools_integration_installation_trigger_path(latest))
      end

      @install_trigger = IntegrationInstallTrigger.new(installation_trigger_params)

      if @install_trigger.save
        redirect_to stafftools_integration_installation_triggers_path,
          notice: "#{T.must(@install_trigger.integration).name} will now be installed automatically."
      else
        render "stafftools/integration_installation_triggers/new"
      end
    end

    def destroy
      deactivation = IntegrationInstallTrigger.deactivate(integration: @install_trigger.integration, install_type: @install_trigger.install_type)

      if deactivation.persisted?
        redirect_to stafftools_integration_installation_triggers_path,
          notice: "#{@install_trigger.integration.name} will no longer be installed automatically."
      else
        flash[:error] = "Automatic installation of #{@install_trigger.integration.name} was unable to be removed. Please try again."
        redirect_to stafftools_integration_installation_triggers_path
      end
    end

    private

    def installation_trigger_params
      params.require(:integration_install_trigger).permit(:integration_id, :install_type, :path, :reason)
    end

    def find_trigger
      @install_trigger = IntegrationInstallTrigger.find(params[:id])
    end
  end
end
