# typed: true
# frozen_string_literal: true

class Biztools::CouponBatchesController < BiztoolsController
  before_action :load_batch, only: [:show, :download_csv]

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Biztools::CouponBatchesController#create",
    "Biztools::CouponBatchesController#download_csv",
  ]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::IssuesPullRequests,
    only: [:index, :show, :new, :create, :download_csv]

  def index
    batches = CouponBatch.order(created_at: :desc).page(params[:page])
    coupons_counts = Coupon.where(coupon_batch_id: batches.map(&:id)).group(:coupon_batch_id).count
    render "biztools/coupon_batches/index", locals: { batches: batches, coupons_counts: coupons_counts }
  end

  def new
    batch = CouponBatch.new
    coupon = Coupon.new
    render "biztools/coupon_batches/new", locals: { batch: batch, coupon: coupon, couponable_product_targets: couponable_product_targets }
  end

  def create
    batch = CouponBatch.new(generation_params: coupon_params.merge(product_target_params), actor: current_user, **batch_params)
    validation_coupon = Coupon.new(coupon_params)

    batch.validate # Needed to show form errors if coupon is invalid
    if validation_coupon.valid? && batch.save
      flash[:notice] = "Coupons generation started, check back later for your coupon goodness!"
      redirect_to biztools_coupon_batch_path(batch)
    else
      flash.now[:error] = (batch.errors.full_messages + validation_coupon.errors.full_messages).join(", ")
      render "biztools/coupon_batches/new", locals: { batch: batch, coupon: validation_coupon, couponable_product_targets: couponable_product_targets }
    end
  end

  def show
    coupons = @batch.coupons.page(params[:page])
    tracking_issue_url = tracking_issue_url_for(@batch)
    render "biztools/coupon_batches/show", locals: { batch: @batch, coupons: coupons, tracking_issue_url: tracking_issue_url }
  end

  def download_csv # rubocop:todo GitHub/UseRestfulActions
    coupons = @batch.coupons.order(id: :asc)
    csv_data = generate_coupons_csv(coupons)
    filename = "coupon-batch-#{@batch.prefix.present? ? @batch.prefix : @batch.id}-#{Date.today}.csv"

    send_data csv_data,
      type: "text/csv",
      disposition: "attachment;filename=#{filename}"
  end

  private

  def generate_coupons_csv(coupons)
    CSV.generate do |csv|
      csv << ["Code", "Discount", "Group", "Expires At", "Duration", "Limit", "Note", "Product Key"]
      coupons.each do |coupon|
        csv << [
          coupon.code,
          coupon.human_discount,
          coupon.group,
          coupon.human_expires_at,
          coupon.human_duration,
          coupon.limit,
          coupon.note,
          coupon.product_target_name
        ]
      end
    end
  end

  memoize def couponable_product_targets
    if current_user.feature_flag_enabled?(:coupon_product_targets, default: false)
      Billing::ProductUUID.couponable.select(:product_type, :product_key, :name).distinct.to_a
    else
      []
    end
  end

  def load_batch
    @batch = CouponBatch.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def batch_params
    params.require(:coupon_batch).permit(:prefix, :quantity, :tracking_issue)
  end

  def coupon_params
    params.require(:coupon).permit(:discount, :group, :expires_at, :note, :duration, :limit, :staff_actor_only)
  end

  def product_target_params
    return {} unless params[:coupon_product_target].present?
    product_type, product_key = JSON.parse(params[:coupon_product_target])
    { product_type: product_type, product_key: product_key }
  end

  def tracking_issue_url_for(batch)
    return nil if batch.tracking_issue.blank?

    # If already a URL, use it; otherwise construct GitHub URL
    if batch.tracking_issue.start_with?("http")
      batch.tracking_issue
    else
      # Parse format like "owner/repo#123"
      match = batch.tracking_issue.match(%r{(?<nwo>[^#]+)#(?<number>\d+)})
      if match
        "#{GitHub.url}/#{match[:nwo]}/issues/#{match[:number]}"
      else
        nil
      end
    end
  end
  helper_method :tracking_issue_url_for
end
