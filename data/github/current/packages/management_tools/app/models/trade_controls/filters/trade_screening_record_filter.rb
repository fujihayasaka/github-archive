# typed: true
# frozen_string_literal: true

class TradeControls::Filters::TradeScreeningRecordFilter

  PER_PAGE = 20

  sig { returns(T::Array[Symbol]) }
  def self.options
    AccountScreeningProfile::VALID_SDN_STATUSES + [:flagged_marketplace_creator, :hit_in_review_breached]
  end

  def self.filter_records(**kargs)
    new(**T.unsafe(kargs)).filter_records
  end

  sig { params(trade_screening_status: String, current_page: Integer, per_page: Integer).void }
  def initialize(trade_screening_status:, current_page:, per_page: PER_PAGE)
    @current_page = current_page
    @per_page = per_page
    @trade_screening_status = trade_screening_status
  end

  def filter_records
    filtered_records.paginate \
      page: current_page,
      per_page: per_page
  end

  private

  sig { returns(Integer) }
  attr_reader :current_page

  sig { returns(Integer) }
  attr_reader :per_page

  sig { returns(String) }
  attr_reader :trade_screening_status

  def filtered_records
    if filter_marketplace_creators?
      root_scope.sdn_blocked.marketplace_app_owners
    elsif filter_hit_in_review_breached?
      root_scope.hit_in_review_breached
    else
      root_scope.with_sdn_status(trade_screening_status)
    end
  end

  sig { returns(T::Boolean) }
  def filter_marketplace_creators?
    trade_screening_status.to_sym == :flagged_marketplace_creator
  end

  sig { returns(T::Boolean) }
  def filter_hit_in_review_breached?
    trade_screening_status.to_sym == :hit_in_review_breached
  end

  def root_scope
    AccountScreeningProfile.includes(:owner)
  end
end
