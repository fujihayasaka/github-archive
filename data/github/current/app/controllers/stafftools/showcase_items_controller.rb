# typed: true
# frozen_string_literal: true

class Stafftools::ShowcaseItemsController < StafftoolsController # rubocop:todo GitHub/ControllersShouldHaveTests
  include ShowcaseItemsControllerMethods

  before_action :showcase_disabled
  before_action :find_collection, except: [:perform_healthcheck]
  before_action :find_item, except: [:create, :perform_healthcheck]

  javascript_bundle :biztools

  def create
    create_item(:stafftools)
  end

  def update
    update_item(:stafftools)
  end

  def edit
    edit_item(:stafftools)
  end

  def destroy
    destroy_item(:stafftools)
  end
end
