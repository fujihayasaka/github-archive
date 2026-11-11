# typed: true
# frozen_string_literal: true

class Stafftools::GraphsController < StafftoolsController # rubocop:todo GitHub/ControllersShouldHaveTests

  skip_before_action :site_admin_only
  skip_before_action :sudo_filter
  skip_before_action :require_admin_frontend
  skip_before_action :ensure_stafftools_authorization unless GitHub.enterprise?
  before_action :site_graph_only

  def flamegraph # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render "stafftools/graphs/flamegraph", layout: false
      end
    end
  end
end
