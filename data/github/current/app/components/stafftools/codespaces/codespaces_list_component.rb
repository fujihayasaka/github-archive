# typed: true
# frozen_string_literal: true

class Stafftools::Codespaces::CodespacesListComponent < ApplicationComponent
  attr_reader :active_codespaces, :deleted_codespaces, :user, :state

  LIST_STATES = %w[active deleted].freeze
  PER_PAGE = 20

  def initialize(user, active_codespaces, deleted_codespaces, state: :active)
    @user = user
    @active_codespaces = active_codespaces
    @deleted_codespaces = deleted_codespaces
    @state = state
  end

  def showing_active_codespaces?
    state&.to_s != "deleted"
  end

  def paginated_codespaces
    return paginated_active_codespaces if showing_active_codespaces?
    paginated_deleted_codespaces
  end

  def paginated_active_codespaces
    active_codespaces.paginate(page: params[:page], per_page: PER_PAGE, total_entries: active_codespaces.size)
  end

  def paginated_deleted_codespaces
    deleted_codespaces.paginate(page: params[:page], per_page: PER_PAGE, total_entries: deleted_codespaces.size)
  end

  def render?
    true if active_codespaces.size > 0 || deleted_codespaces.size > 0
  end

  def show_storage_utilization?(codespace)
    codespace.environment_data&.storage_utilization_in_gb.present? && get_storage_utilization_in_gb(codespace)
  end

  def get_sku(codespace)
    ::Codespaces::Skus.sku_by_name(codespace.sku_name)
  end

  def should_show_storage_utilization?(codespace)
    codespace.environment_data&.storage_utilization_in_gb.present? && get_storage_utilization_in_gb(codespace)
  end

  def get_storage_utilization_in_gb(codespace)
    return nil if codespace.environment_data&.storage_utilization_is_nil?
    return "0.0" if codespace.environment_data&.storage_utilization_is_zero?

    utilization = codespace.environment_data.storage_utilization_in_gb.round(2)

    return nil unless utilization
    return "#{utilization}" if utilization >= 0.1

    "<0.1"
  end
end
