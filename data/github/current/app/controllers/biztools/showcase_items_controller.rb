# typed: true
# frozen_string_literal: true

class Biztools::ShowcaseItemsController < BiztoolsController # rubocop:todo GitHub/ControllersShouldHaveTests
  include ShowcaseItemsControllerMethods

  before_action :find_collection, except: [:perform_healthcheck]
  before_action :find_item, except: [:create, :perform_healthcheck]

  def create
    create_item(:biztools)
  end

  def update
    update_item(:biztools)
  end

  def edit
    edit_item(:biztools)
  end

  def destroy
    destroy_item(:biztools)
  end
end
